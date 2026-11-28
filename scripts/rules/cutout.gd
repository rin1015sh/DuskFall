extends RefCounted
## 컷아웃 모습(룰북 1단계 '스프라이트 방향' — 데이터만, 상태 없음): 생물 → 체형 틀·피부·머리 색·부가 부위·장비 모양.
## 그리기는 표현 계층(scenes/battle/cutout_rig.gd). 데이터: data/rules/body_templates.json(뼈·순서·애니메이션),
## data/rules/cutout_looks.json(종족 모습·재질 색·무기/갑옷 모양).

const Equipment := preload("res://scripts/rules/equipment.gd")

## 갑옷을 입지 않았을 때 옷 색(클래스마다 다르게 — 클래스 id의 해시로 고른다, 이름을 코드에 적지 않는다)
const TUNICS := ["#7a3b2e", "#2f4a6b", "#4b5e34", "#5a3e6b", "#6b5a2e", "#3a5a5a", "#6b2e48", "#4a4a52"]


## 컷아웃으로 그릴 생물인가: 종족이 있는 사람(파티·동료·NPC). 몬스터는 그림 그대로. art.cutout = false면 끈다.
static func enabled_for(c: Node) -> bool:
	if c == null or str(c.species_id) == "" or c.has_meta("monster"):
		return false
	return bool(c.get_meta("art", {}).get("cutout", true))


static func template(id: String) -> Dictionary:
	var t := RulesDB.get_entry("body_template", id)
	return t if not t.is_empty() else RulesDB.get_entry("body_template", "medium")


## 그림 안 얼굴·전신 자리(그림 px): 초상은 얼굴, 소지품 창은 전신을 자른다. 원점(발)은 그림 아래에서 12px 위.
static func portrait_regions(template_id: String) -> Dictionary:
	var t := template(template_id)
	var canvas: Array = t.get("canvas", [160, 240])
	var w := float(canvas[0])
	var foot := float(canvas[1]) - 12.0
	var up := 0.0
	var head_len := 26.0
	for b: Dictionary in t.get("bones", []):
		if str(b["id"]) in ["hips", "neck", "head"]:
			up += absf(float(b["y"]))
		if str(b["id"]) == "head":
			head_len = float(b["len"])
	var r := float(t.get("proportions", {}).get("head_r", 12.0))
	var head_c := Vector2(w * 0.5 + 2.0, foot - up - r)
	var top := foot - up - head_len - 8.0
	return {"face": Rect2(head_c - Vector2(r * 2.6, r * 2.4), Vector2(r * 5.2, r * 5.2)),
		"body": Rect2(Vector2(w * 0.5 - (foot - top) * 0.33, top), Vector2((foot - top) * 0.66, foot - top + 8.0))}


static func species_look(species_id: String) -> Dictionary:
	var sid := species_id
	if not RulesDB.has_entry("cutout_look", sid):
		var lin := RulesDB.get_entry("species", sid)
		sid = str(lin.get("parent", "human"))  # 혈통은 부모 종족 모습
	var e := RulesDB.get_entry("cutout_look", sid)
	return e if not e.is_empty() else RulesDB.get_entry("cutout_look", "human")


## 아이템 → 모양. 무기 종류(바탕 아이템 look_<바탕>)가 부품 틀(shape)·동작(motion)·기본 외형을 정하고,
## 아이템 외형(item_looks의 look_<아이템 id>)이 있으면 그 위에 덮어쓴다(색·날 빛·코등이 등 — 동작·틀은 종류 그대로). 없으면 {}.
const LOOK_LOCKED := ["id", "shape", "motion", "material"]


static func item_look(item_id: String) -> Dictionary:
	if item_id == "":
		return {}
	var e := RulesDB.get_entry("cutout_look", "look_" + Equipment.base_of(item_id))
	if e.is_empty():
		return {}
	var out := e.duplicate()
	var own := RulesDB.get_entry("cutout_look", "look_" + item_id) if item_id != Equipment.base_of(item_id) else {}
	for k: String in own:
		if k not in LOOK_LOCKED:
			out[k] = own[k]
	out["item"] = item_id
	out["color"] = str(out["color"]) if out.has("color") else material_color(str(e["material"]))  # 아이템 색이 따로 있으면 그것
	var rar := str(Equipment.entry(item_id).get("rarity", "common"))
	out["rarity"] = rar  # 등급 — 색 바꾸기(테두리 빛)
	var props: Array = Equipment.entry(Equipment.base_of(item_id)).get("properties", [])
	out["two_handed"] = "two_handed" in props  # 인형: 두 손으로 쥔다(활·석궁은 제 동작)
	out["versatile"] = "versatile" in props  # 보조 손이 비면 두 손으로
	return out


static func material_color(mat_id: String) -> String:
	return str(RulesDB.get_entry("cutout_look", mat_id).get("color", "#808080"))


## 생물의 모습 한 벌. key는 같은 모습이면 같다(그림 다시 만들기 판단용).
static func look(c: Node) -> Dictionary:
	var sp := species_look(str(c.species_id))
	var eq: Dictionary = c.equipment
	var set_name: String = str(c.active_set) if str(c.active_set) != "" else "melee"
	var main := str(eq.get(set_name + "_main", ""))
	var off := str(eq.get(set_name + "_off", ""))
	if main == "":
		main = str(c.weapon("main"))
	if off == "" and set_name == "melee" and bool(c.get_meta("shield", false)):
		off = "shield"
	var tunic: String = TUNICS[absi(hash(str(c.class_id))) % TUNICS.size()]
	var out := {
		"template": str(sp.get("template", "medium")),
		"skin": str(sp.get("skin", "#c99a7a")),
		"hair": str(sp.get("hair", "#4a3222")),
		"extras": Array(sp.get("extras", [])).duplicate(),
		"tunic": tunic,
		"armor": item_look(str(eq.get("armor", ""))),
		"helmet": str(eq.get("head", "")) != "",
		"cloak": str(eq.get("cloak", "")) != "",
		"gloves": str(eq.get("hands", "")) != "",
		"boots": str(eq.get("feet", "")) != "",
		# 착용 아이템 모양(간이 3D 인형이 관절에 붙인다 — 머리·망토·손·발)
		"head_look": item_look(str(eq.get("head", ""))),
		"cloak_look": item_look(str(eq.get("cloak", ""))),
		"hands_look": item_look(str(eq.get("hands", ""))),
		"feet_look": item_look(str(eq.get("feet", ""))),
		"weapon": item_look(main),
		"offhand": item_look(off),
		"set": set_name,
	}
	out["key"] = JSON.stringify(out)
	return out
