extends RefCounted
## 데이터 검증 본체. tools/validate_data.gd(명령줄)와 tests/가 같이 쓴다.
##
## 검사 항목
## 1. data/ 아래 모든 JSON이 읽히고, 최상위 "schema": "<kind>_v<n>"에 맞는
##    data/schema/<kind>.schema.json을 통과하는가
## 2. 같은 종류 안에서 ID가 겹치지 않는가
## 3. 다른 데이터를 가리키는 ID(클래스·종족·상태·표면)가 실제로 있는가
##    대상 종류의 데이터가 아직 하나도 없으면 경고만 내고 건너뛴다.
## 4. "script": "<id>"마다 res://scripts/rules/effects/<id>.gd가 있고 컴파일되는가
## 5. data/·scenes/·scripts/에 tools/banned_names.txt의 금지어가 없는가

const SchemaValidator := preload("res://tools/schema_validator.gd")
const EventBusScript := preload("res://scripts/rules/event_bus.gd")

const DATA_DIR := "res://data"
const SCHEMA_DIR := "res://data/schema"
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

	var files := _list_files(DATA_DIR, ["json"])
	var checked := 0
	for path in files:
		if path.begins_with(SCHEMA_DIR + "/"):
			continue
		if _check_file(path):
			checked += 1
	info.append("JSON %d개 검사" % checked)
	_check_refs()
	_check_scripts()
	_check_banned_names()
	return errors.is_empty()


# ---------- 1·2. 파일·스키마·ID ----------

func _check_file(path: String) -> bool:
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append("%s:%d: JSON 문법 오류 — %s" % [path, json.get_error_line(), json.get_error_message()])
		return false
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY or not data.has("schema"):
		errors.append("%s: 최상위에 \"schema\": \"<kind>_v<n>\"가 없다" % path)
		return false
	var m := RegEx.create_from_string("^([a-z][a-z0-9_]*)_v[0-9]+$").search(str(data["schema"]))
	if m == null:
		errors.append("%s: schema 값 '%s'가 <kind>_v<n> 모양이 아니다" % [path, data["schema"]])
		return false
	var kind := m.get_string(1)
	var schema_path := "%s/%s.schema.json" % [SCHEMA_DIR, kind]
	if not FileAccess.file_exists(schema_path):
		errors.append("%s: 스키마 파일 %s가 없다" % [path, schema_path])
		return false
	var schema: Variant = JSON.parse_string(FileAccess.get_file_as_string(schema_path))
	if typeof(schema) != TYPE_DICTIONARY:
		errors.append("%s: 스키마 JSON을 읽을 수 없다" % schema_path)
		return false
	for e in SchemaValidator.new().validate(data, schema):
		errors.append("%s: %s" % [path, e])
	_collect_entries(kind, data, path)
	return true


## 최상위가 항목 하나("id" 있음)이거나, 최상위 배열에 항목들이 들어 있다.
func _collect_entries(kind: String, data: Dictionary, path: String) -> void:
	var items: Array = []
	if data.has("id"):
		items.append(data)
	for key: String in data.keys():
		if typeof(data[key]) == TYPE_ARRAY:
			for item: Variant in data[key]:
				if typeof(item) == TYPE_DICTIONARY and item.has("id"):
					items.append(item)
	if not entries.has(kind):
		entries[kind] = {}
	for item: Dictionary in items:
		var id := str(item["id"])
		if entries[kind].has(id):
			errors.append("%s: %s ID '%s'가 겹친다(먼저 나온 곳 %s)" % [path, kind, id, entries[kind][id]["file"]])
		else:
			entries[kind][id] = {"entry": item, "file": path}


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


## 데이터의 훅 이름(cast.trigger, hook)이 EventBus 훅 목록에 있는지 본다.
## 룰북 8단계 훅 표에 없는 이름은 룰북 결정이 필요해 경고로 남긴다.
func _check_hook(where: String, entry: Dictionary) -> void:
	var names: Array = []
	if entry.has("hook"):
		names.append(entry["hook"])
	if typeof(entry.get("cast")) == TYPE_DICTIONARY and entry["cast"].has("trigger"):
		names.append(entry["cast"]["trigger"])
	for n: Variant in names:
		if not _hooks.has(str(n)):
			warnings.append("%s: 훅 '%s'가 룰북 8단계 훅 표(EventBus)에 없다" % [where, n])


func _values_at(entry: Dictionary, field: String) -> Array:
	var key := field.trim_suffix("[]")
	var value: Variant = entry.get(key)
	if value == null:
		return []
	if field.ends_with("[]"):
		return value if typeof(value) == TYPE_ARRAY else []
	return [value]


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
	var out := PackedStringArray()
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for f in da.get_files():
		if exts.has(f.get_extension().to_lower()):
			out.append(dir.path_join(f))
	for d in da.get_directories():
		if d.begins_with("."):
			continue
		out.append_array(_list_files(dir.path_join(d), exts))
	out.sort()
	return out
