extends RefCounted
## 데이터 검증 본체. tools/validate_data.gd(명령줄)와 tests/가 같이 쓴다.
##
## 검사 항목
## 1·2. data/ 아래 모든 JSON이 읽히고 스키마를 통과하며 ID가 겹치지 않는가
##      (scripts/rules/data_loader.gd — 게임 시작 때 RulesDB도 같은 검사를 한다)
## 3. 다른 데이터를 가리키는 ID(클래스·종족·상태·표면)가 실제로 있는가
##    대상 종류의 데이터가 아직 하나도 없으면 경고만 내고 건너뛴다.
## 3-1. 맵 stamps가 가리키는 지형 프리셋이 있고 지도 안에 들어가는가, 프리셋 글자가 범례에 있는가
## 4. "script": "<id>"마다 res://scripts/rules/effects/<id>.gd가 있고 컴파일되는가
## 5. data/·scenes/·scripts/에 tools/banned_names.txt의 금지어가 없는가

const DataLoader := preload("res://scripts/rules/data_loader.gd")
const EventBusScript := preload("res://scripts/rules/event_bus.gd")
const MapStamps := preload("res://scripts/rules/map_stamps.gd")

const DATA_DIR := "res://data"
const EFFECTS_DIR := "res://scripts/rules/effects"
const BANNED_FILE := "res://tools/banned_names.txt"
const BANNED_SCAN_DIRS := ["res://data", "res://scenes", "res://scripts"]
const TEXT_EXTS := ["json", "gd", "tscn", "tres", "gdshader", "cfg", "txt", "md"]

## 참조 필드 → 가리키는 종류. 경로는 항목 안 위치, "[]"는 배열 원소.
const REFS := {
	"spell": [
		["classes[]", "class"],
		["granted_by[]", "species"],
	],
	"condition": [
		["includes[]", "condition"],
		["also_applies[]", "condition"],
		["condition_immunities[]", "condition"],
		["removes_on_apply[]", "condition"],
		["suppresses[]", "condition"],
	],
	"surface": [
		["expires_to", "surface"],
	],
	"material": [
		["burns_to", "material"],
	],
	"reaction": [
		["result.replace_surface", "surface"],
		["result.create_surface", "surface"],
		["result.create_cloud", "surface"],
		["target@surface:", "surface"],
		["cause@surface:", "surface"],
	],
}
## 효과 종류별로 "id"가 가리키는 종류.
const EFFECT_ID_REFS := {
	"apply_condition": "condition",
	"remove_condition": "condition",
	"create_surface": "surface",
	"create_cloud": "surface",
}

var errors := PackedStringArray()
var warnings := PackedStringArray()
var info := PackedStringArray()

## kind → { id → { "entry": Dictionary, "file": String } }
var entries: Dictionary = {}
var _hooks: PackedStringArray = []


func run() -> bool:
	errors.clear()
	warnings.clear()
	info.clear()
	entries.clear()
	var bus: Node = EventBusScript.new()
	_hooks = bus.hook_names()
	bus.free()

	var loader := DataLoader.new()
	loader.load_dir(DATA_DIR)
	errors.append_array(loader.errors)
	entries = loader.entries
	info.append("JSON %d개 검사" % loader.files_loaded)
	_check_refs()
	_check_stamps()
	_check_class_builds()
	_check_caps()
	_check_scripts()
	_check_banned_names()
	return errors.is_empty()


# ---------- 3-3. 능력 태그(caps)·고르는 기능 ----------

func _check_caps() -> void:
	var known: Dictionary = entries.get("capability", {})
	var check := func(where: String, cap: Variant) -> void:
		if not known.has(str(cap)):
			errors.append("%s: 능력 태그 '%s'가 data/rules/capabilities.json에 없다" % [where, cap])
	var feature_lists := []  # [where, features]
	for cid: String in entries.get("class", {}).keys():
		var rec: Dictionary = entries["class"][cid]
		feature_lists.append(["%s: class '%s'" % [rec["file"], cid], rec["entry"].get("features", [])])
		for sc: Dictionary in rec["entry"].get("subclasses", []):
			feature_lists.append(["%s: class '%s'/%s" % [rec["file"], cid, sc.get("id", "")], sc.get("features", [])])
	for sid: String in entries.get("species", {}).keys():
		var rec: Dictionary = entries["species"][sid]
		feature_lists.append(["%s: species '%s'" % [rec["file"], sid], rec["entry"].get("features", [])])
	for fl: Array in feature_lists:
		for f: Dictionary in fl[1]:
			var where := "%s 기능 %s" % [fl[0], f.get("id", "")]
			for cap: Variant in f.get("caps", []):
				check.call(where, cap)
			for cap: Variant in f.get("grants", {}).get("caps", []):
				check.call(where + " grants", cap)
			for opt: String in f.get("choice_grants", {}).keys():
				for cap: Variant in f["choice_grants"][opt].get("caps", []):
					check.call(where + " choice_grants." + opt, cap)
				if not opt in f.get("choices", []):
					errors.append("%s: choice_grants '%s'가 choices에 없다" % [where, opt])
			if str(f.get("choice_kind", "")) == "feat":
				for ch: Variant in f.get("choices", []):
					if not entries.get("feat", {}).has(str(ch)):
						errors.append("%s: 고르는 재주 '%s'가 없다" % [where, ch])
			if f.has("toggle") and f["toggle"].get("values", []).size() < 2:
				errors.append("%s: toggle 값이 둘 이상이어야 한다" % where)
	for fid: String in entries.get("feat", {}).keys():
		for cap: Variant in entries["feat"][fid]["entry"].get("tags", []):
			check.call("%s: feat '%s' tags" % [entries["feat"][fid]["file"], fid], cap)
	for aid: String in entries.get("action", {}).keys():
		var req := str(entries["action"][aid]["entry"].get("requires", ""))
		if req != "":
			check.call("%s: action '%s' requires" % [entries["action"][aid]["file"], aid], req)


# ---------- 3-2. 클래스 추천 빌드(default_build) 교차 참조 ----------

func _check_class_builds() -> void:
	for cid: String in entries.get("class", {}).keys():
		var rec: Dictionary = entries["class"][cid]
		var cls: Dictionary = rec["entry"]
		var where := "%s: class '%s' default_build" % [rec["file"], cid]
		var b: Dictionary = cls.get("default_build", {})
		if b.is_empty():
			errors.append("%s: class '%s'에 default_build(추천 빌드)가 없다 — 동료·시험·생성 화면이 쓴다" % [rec["file"], cid])
			continue
		var refs := [["species", "species"], ["lineage", "species"], ["background", "background"], ["armor", "armor"], ["origin_feat", "feat"]]
		for r: Array in refs:
			var v := str(b.get(r[0], ""))
			if v != "" and not entries.get(r[1], {}).has(v):
				errors.append("%s.%s: %s '%s'가 없다" % [where, r[0], r[1], v])
		var list := str(cls.get("spellcasting", {}).get("list", cid))
		for k: String in ["spells", "cantrips"]:
			for v: Variant in b.get(k, []):
				if not entries.get("spell", {}).has(str(v)):
					errors.append("%s.%s: 주문 '%s'가 없다" % [where, k, v])
				elif not list in entries["spell"][str(v)]["entry"].get("classes", []):
					errors.append("%s.%s: 주문 '%s'가 %s 주문 목록(주문 classes)에 없다" % [where, k, v, list])
		for sc: Dictionary in cls.get("subclasses", []):
			for lvk: String in sc.get("always_prepared", {}).keys():
				for v: Variant in sc["always_prepared"][lvk]:
					if not entries.get("spell", {}).has(str(v)):
						errors.append("%s: class '%s'/%s always_prepared 주문 '%s'가 없다" % [rec["file"], cid, sc.get("id", ""), v])
		for v: Variant in b.get("masteries", []):
			if not entries.get("weapon", {}).has(str(v)):
				errors.append("%s.masteries: 무기 '%s'가 없다" % [where, v])
		for slot: String in ["melee", "ranged"]:
			for hand: String in ["main", "off"]:
				var w := str(b.get("weapons", {}).get(slot, {}).get(hand, ""))
				if w != "" and not entries.get("weapon", {}).has(w):
					errors.append("%s.weapons.%s.%s: 무기 '%s'가 없다" % [where, slot, hand, w])
		var subs: Array = cls.get("subclasses", []).map(func(x: Dictionary) -> String: return str(x.get("id", "")))
		if str(b.get("subclass", "")) != "" and not str(b["subclass"]) in subs:
			errors.append("%s.subclass: 하위 클래스 '%s'가 없다" % [where, b["subclass"]])
		for sk: Variant in b.get("skills", []):
			if not str(sk) in cls.get("skills", {}).get("from", []):
				errors.append("%s.skills: '%s'는 클래스 기능 목록에 없다" % [where, sk])


# ---------- 3-1. 지형 도장(맵 stamps → terrain_preset) ----------

func _check_stamps() -> void:
	var presets := {}
	for id: String in entries.get("terrain_preset", {}).keys():
		presets[id] = entries["terrain_preset"][id]["entry"]
	for id: String in entries.get("map", {}).keys():
		var rec: Dictionary = entries["map"][id]
		for e in MapStamps.check(rec["entry"], presets):
			errors.append("%s: map '%s' %s" % [rec["file"], id, e])
	for id: String in presets.keys():
		var pre: Dictionary = presets[id]
		for row: Variant in pre.get("grid", []):
			for ch: String in String(row):
				if ch != "." and ch != " " and not pre.get("legend", {}).has(ch):
					errors.append("%s: terrain_preset '%s' 글자 '%s'가 범례에 없다" % [entries["terrain_preset"][id]["file"], id, ch])


# ---------- 3. ID 참조 ----------

func _check_refs() -> void:
	var skipped := {}
	for kind: String in entries.keys():
		for id: String in entries[kind].keys():
			var rec: Dictionary = entries[kind][id]
			var where := "%s: %s '%s'" % [rec["file"], kind, id]
			for ref: Array in REFS.get(kind, []):
				for value: Variant in _values_at(rec["entry"], ref[0]):
					_check_ref(where, ref[0], str(value), ref[1], skipped)
			for effect: Dictionary in _effects_in(rec["entry"]):
				var target_kind: String = EFFECT_ID_REFS.get(effect.get("type", ""), "")
				if target_kind != "" and effect.has("id"):
					_check_ref(where, "effect %s" % effect["type"], str(effect["id"]), target_kind, skipped)
			_check_hook(where, rec["entry"])
	for target_kind: String in skipped.keys():
		warnings.append("%s 데이터가 아직 없어 %s 참조 %d건을 건너뛰었다" % [target_kind, target_kind, skipped[target_kind]])


func _check_ref(where: String, field: String, value: String, target_kind: String, skipped: Dictionary) -> void:
	if entries.get(target_kind, {}).is_empty():
		skipped[target_kind] = skipped.get(target_kind, 0) + 1
		return
	if not entries[target_kind].has(value):
		errors.append("%s: %s가 가리키는 %s '%s'가 없다" % [where, field, target_kind, value])


## 데이터의 훅 이름(cast.trigger, hook, hooks의 키)이 EventBus 훅 목록에 있는지 본다.
## 룰북 8단계 훅 표에 없는 이름은 룰북 결정이 필요해 경고로 남긴다.
func _check_hook(where: String, entry: Dictionary) -> void:
	var names: Array = []
	if entry.has("hook"):
		names.append(entry["hook"])
	if typeof(entry.get("hooks")) == TYPE_DICTIONARY:
		names.append_array(entry["hooks"].keys())
	if typeof(entry.get("cast")) == TYPE_DICTIONARY and entry["cast"].has("trigger"):
		names.append(entry["cast"]["trigger"])
	for n: Variant in names:
		if not _hooks.has(str(n)):
			warnings.append("%s: 훅 '%s'가 룰북 8단계 훅 표(EventBus)에 없다" % [where, n])


## 필드 경로의 값들. "a.b"는 중첩, "a[]"는 배열 원소, "a@접두어"는 접두어로 시작하는 문자열에서 접두어를 뗀 값.
func _values_at(entry: Dictionary, field: String) -> Array:
	var prefix := ""
	if field.contains("@"):
		prefix = field.get_slice("@", 1)
		field = field.get_slice("@", 0)
	var is_array := field.ends_with("[]")
	var node: Variant = entry
	for part in field.trim_suffix("[]").split("."):
		if typeof(node) != TYPE_DICTIONARY or not node.has(part):
			return []
		node = node[part]
	var values: Array = (node if typeof(node) == TYPE_ARRAY else []) if is_array else [node]
	if prefix == "":
		return values
	var out: Array = []
	for v: Variant in values:
		if typeof(v) == TYPE_STRING and v.begins_with(prefix):
			out.append(v.trim_prefix(prefix))
	return out


## 항목 안의 모든 효과({"type": ...}를 가진 Dictionary)를 찾는다.
func _effects_in(node: Variant, out: Array = []) -> Array:
	if typeof(node) == TYPE_DICTIONARY:
		if node.has("type") and typeof(node["type"]) == TYPE_STRING and EFFECT_ID_REFS.has(node["type"]):
			out.append(node)
		for v: Variant in node.values():
			_effects_in(v, out)
	elif typeof(node) == TYPE_ARRAY:
		for v: Variant in node:
			_effects_in(v, out)
	return out


# ---------- 4. 스크립트 효과 ----------

func _check_scripts() -> void:
	var used := {}  # script id → [항목 설명]
	for kind: String in entries.keys():
		for id: String in entries[kind].keys():
			var rec: Dictionary = entries[kind][id]
			var entry: Dictionary = rec["entry"]
			for sid: String in _script_ids(entry):
				if not used.has(sid):
					used[sid] = []
				used[sid].append("%s '%s'" % [kind, id])
			var upcast: Variant = entry.get("upcast")
			if typeof(upcast) == TYPE_DICTIONARY and typeof(upcast.get("per_slot_level")) == TYPE_DICTIONARY \
					and upcast["per_slot_level"].get("script", false) and not entry.has("script"):
				# 업캐스트를 스크립트로 처리하라는 표시인데 연결할 스크립트 ID가 없다. 어디에 구현할지 정해야 해 경고로 둔다.
				warnings.append("%s: %s '%s': upcast.per_slot_level.script가 true인데 연결할 script 필드가 없다" % [rec["file"], kind, id])
	var stubs := 0
	for sid: String in used.keys():
		var path := "%s/%s.gd" % [EFFECTS_DIR, sid]
		if not FileAccess.file_exists(path):
			errors.append("스크립트 효과 %s가 없다(쓰는 곳: %s)" % [path, ", ".join(used[sid])])
			continue
		var script: Variant = load(path)
		if script == null or not (script is GDScript) or not script.can_instantiate():
			errors.append("스크립트 효과 %s를 불러올 수 없다(문법 오류?)" % path)
			continue
		var inst: Object = script.new()
		if not inst.has_method("is_implemented"):
			errors.append("스크립트 효과 %s가 effect_script.gd를 상속하지 않는다" % path)
		elif not inst.is_implemented():
			stubs += 1
	info.append("스크립트 효과 %d개 참조, 그중 미구현 빈 파일 %d개" % [used.size(), stubs])


func _script_ids(node: Variant, out: Array = []) -> Array:
	if typeof(node) == TYPE_DICTIONARY:
		for k: Variant in node.keys():
			if k == "script" and typeof(node[k]) == TYPE_STRING:
				out.append(node[k])
			else:
				_script_ids(node[k], out)
	elif typeof(node) == TYPE_ARRAY:
		for v: Variant in node:
			_script_ids(v, out)
	return out


# ---------- 5. 금지어 ----------

func _check_banned_names() -> void:
	var patterns: Array[RegEx] = []
	var words: PackedStringArray = []
	for line in FileAccess.get_file_as_string(BANNED_FILE).split("\n"):
		var w := line.strip_edges()
		if w == "" or w.begins_with("#"):
			continue
		# 대소문자 무시, 단어 단위(앞뒤가 글자·숫자·_가 아님).
		var re := RegEx.create_from_string("(?i)(?<![\\p{L}\\p{N}_])" + _regex_escape(w) + "(?![\\p{L}\\p{N}_])")
		patterns.append(re)
		words.append(w)
	var hits := 0
	for dir: String in BANNED_SCAN_DIRS:
		for path in _list_files(dir, TEXT_EXTS):
			var lines := FileAccess.get_file_as_string(path).split("\n")
			for i in lines.size():
				for j in patterns.size():
					if patterns[j].search(lines[i]) != null:
						errors.append("%s:%d: 금지어 '%s'" % [path, i + 1, words[j]])
						hits += 1
	info.append("금지어 %d개로 검사, %d건 발견" % [words.size(), hits])


func _regex_escape(s: String) -> String:
	var out := ""
	for c in s:
		if "\\^$.|?*+()[]{}".contains(c):
			out += "\\"
		out += c
	return out


# ---------- 공통 ----------

func _list_files(dir: String, exts: Array) -> PackedStringArray:
	return DataLoader.list_files(dir, exts)
