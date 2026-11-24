extends SceneTree
## 6단계 주문 변환표: docs/rules/spells_table.md를 data/content/spells.json에서 새로 만든다(손으로 고치지 않는다).
## 실행: godot --headless --path . -s res://tools/spells_table.gd
## 수치는 데이터가 원천이다(BG3 수치 우선 — 2026-11-24). 게임 메모 = 주문 notes_ko.

const OUT := "res://docs/rules/spells_table.md"
const CLASS_ABBR := {"bard": "바드", "cleric": "클", "druid": "드", "paladin": "팔", "ranger": "레", "sorcerer": "소", "warlock": "워", "wizard": "위"}
const COST := {"action": "행동", "bonus_action": "보너스", "reaction": "반응", "explore": "탐험 전용", "attack": "공격(공격 행동)"}
const ABILITY := {"str": "근력", "dex": "민첩", "con": "건강", "int": "지능", "wis": "지혜", "cha": "매력"}
const DTYPE := {"acid": "산", "bludgeoning": "타격", "cold": "냉기", "fire": "화염", "force": "역장", "lightning": "번개", "necrotic": "사령",
	"piercing": "관통", "poison": "독", "psychic": "정신", "radiant": "광휘", "slashing": "참격", "thunder": "천둥", "chosen": "고른 유형"}
const STATUS := {"excluded_v1": "**1차 제외**", "candidate_exclusion": "**제외 후보**"}
var _done := false


func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	var db: Node = root.get_node("RulesDB")
	var spells: Array = db.entries("spell").duplicate()
	spells.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["level"]) < int(b["level"]) or (int(a["level"]) == int(b["level"]) and str(a["name"]["en"]) < str(b["name"]["en"])))
	var lines := PackedStringArray()
	lines.append("# 6단계 주문 변환표")
	lines.append("")
	lines.append("> `tools/spells_table.gd`가 `data/content/spells.json`에서 만든다(손으로 고치지 않는다). 수치는 BG3 우선(2026-11-24 — bg3.wiki 대조), BG3에 없는 주문은 SRD 5.2.1 원문을 6단계 공통 변환 규칙으로 바꾼 값이다.")
	lines.append("")
	lines.append("읽는 법: 사용은 클래스 주문 목록(바드·클 = 클레릭·드 = 드루이드·팔 = 팔라딘·레 = 레인저·소 = 소서러·워 = 워락·위 = 위저드), 괄호는 종족·혈통. 1칸 = 1.5m, 10턴 = 1분, '긴 휴식까지' = 원문 1시간 이상, '탐험 전용' = 시전 시간 1분 이상. 출처의 '자체'는 SRD 밖 BG3 주문을 자체 이름으로 만든 것. '공통 규칙대로'는 변환 규칙 밖의 별도 처리가 없다는 뜻이다.")
	lines.append("")
	var counts := {}
	for s: Dictionary in spells:
		counts[int(s["level"])] = int(counts.get(int(s["level"]), 0)) + 1
	var cur := -1
	for s: Dictionary in spells:
		var lv := int(s["level"])
		if lv != cur:
			if cur != -1:
				lines.append("")
			cur = lv
			lines.append("### %s (%d개)" % ["소마법" if lv == 0 else "%d레벨" % lv, int(counts[lv])])
			lines.append("")
			lines.append("| 주문 | 이름 | 사용 | 시전 | 사거리 | 범위 | 지속 | 판정·효과 | 게임 메모 |")
			lines.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
		lines.append("| %s | %s | %s | %s | %s | %s | %s | %s | %s |" % [s["name"]["en"] + (" (자체)" if str(s.get("source", "")) == "original" else ""),
			str(s["name"].get("ko", "")), _users(db, s), _cast(s), _range(s), _area(s), _duration(s), _check(s), _memo(s)])
	lines.append("")
	lines.append("### 7~9레벨")
	lines.append("")
	lines.append("레벨 상한 12(BG3식, 2026-11-23)에 맞춰 7~9레벨 주문은 게임에서 뺐다. 주문은 6레벨까지.")
	lines.append("")
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	print("썼다: %s (%d개)" % [OUT, spells.size()])
	quit()
	return true


static func _users(db: Node, s: Dictionary) -> String:
	var out: Array = []
	for c: String in s.get("classes", []):
		out.append(CLASS_ABBR.get(c, c))
	var sp: Array = []
	for g: String in s.get("granted_by", []):
		var e: Dictionary = db.get_entry("species", g)
		sp.append(str(e.get("name", {}).get("ko", g)) if not e.is_empty() else g)
	var txt := "·".join(out)
	if not sp.is_empty():
		txt += "(%s)" % "·".join(sp)
	return txt if txt != "" else "—"


static func _cast(s: Dictionary) -> String:
	var c: Dictionary = s["cast"]
	var t: String = COST.get(str(c["cost"]), str(c["cost"]))
	if c.get("ritual", false):
		t += "·의식"
	if s.has("recast"):
		t += " (다시 쓰기: %s)" % COST.get(str(s["recast"]["cost"]), "")
	return t


static func _range(s: Dictionary) -> String:
	var r: Dictionary = s["range"]
	match str(r["type"]):
		"tiles":
			return "%d칸" % int(r["tiles"])
		"touch":
			return "접촉"
		"self":
			return "자신"
	return str(r["type"])


static func _area(s: Dictionary) -> String:
	var a: Variant = s.get("area")
	if a == null:
		return "—"
	var t := ""
	match str(a["shape"]):
		"sphere":
			t = "구 반경 %d칸" % int(a["radius_tiles"])
		"cylinder":
			t = "원기둥 반경 %d칸" % int(a["radius_tiles"])
		"emanation":
			t = "자신 주변 %d칸" % int(a["radius_tiles"])
		"cone":
			t = "원뿔 %d칸" % int(a["length_tiles"])
		"line":
			t = "선 %d칸" % int(a["length_tiles"])
		"cube":
			t = "정육면체 %d칸" % int(a["size_tiles"])
		"square":
			t = "%d×%d칸" % [int(a["size_tiles"]), int(a["size_tiles"])]
		_:
			t = str(a["shape"])
	match str(s.get("area_targets", "")):
		"allies":
			t += "(아군)"
		"enemies":
			t += "(적)"
	return t


static func _duration(s: Dictionary) -> String:
	var d: Dictionary = s["duration"]
	var t := ""
	match str(d["type"]):
		"instant":
			t = "즉시"
		"turns":
			t = "%d턴" % int(d["turns"])
		"until_long_rest":
			t = "긴 휴식까지"
		"permanent":
			t = "영구"
		_:
			t = str(d["type"])
	return ("집중 " + t) if s.get("concentration", false) else t


static func _check(s: Dictionary) -> String:
	var e: Dictionary = s.get("effects", {})
	var parts: Array = []
	var ch: Dictionary = e.get("check", {})
	if ch.get("type") == "attack":
		parts.append("%s 주문 공격" % ("근접" if ch.get("kind") == "melee" else "원거리"))
	elif ch.get("type") == "save":
		parts.append("%s 내성" % ABILITY.get(str(ch.get("ability", "")), str(ch.get("ability", ""))))
	if s.has("hp_pool"):
		parts.append("HP 총량 %d" % int(s["hp_pool"]["base"]))
	var dmg: Array = []
	for k: String in ["hit", "fail", "apply"]:
		for x: Dictionary in e.get(k, []):
			if x.get("type") == "damage":
				dmg.append("%s %s" % [x["dice"], DTYPE.get(str(x["damage_type"]), str(x["damage_type"]))])
			elif x.get("type") == "heal":
				dmg.append("회복 %s%s" % [x.get("dice", ""), " + 수정치" if x.get("add") == "spell_mod" else ""])
	if not dmg.is_empty():
		parts.append(", ".join(dmg))
	return ", ".join(parts) if not parts.is_empty() else "—"


static func _memo(s: Dictionary) -> String:
	var m := str(s.get("notes_ko", "")).replace("|", "/").replace("\n", " ")
	if m == "":
		m = "공통 규칙대로"
	var st: String = STATUS.get(str(s.get("game_status", "")), "")
	return (st + " — " + m) if st != "" else m
