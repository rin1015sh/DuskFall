extends RefCounted
## 캐릭터 생성 화면의 상태(룰북 6단계: 포인트 구매 27점, 능력치 자유 배분, 체형 틀 선택).
## 화면(character_creation.gd)은 이 모델을 바꾸고 다시 그리기만 한다. 규칙 검증은 CharacterBuilder가 한다.

const Builder := preload("res://scripts/rules/character_builder.gd")
const ABILITIES := ["str", "dex", "con", "int", "wis", "cha"]

var spec: Dictionary = {}


func _init(class_id: String = "fighter") -> void:
	reset(class_id)


func reset(class_id: String) -> void:
	spec = Builder.default_spec(class_id, 1)
	spec["scores"] = {"str": 8, "dex": 8, "con": 8, "int": 8, "wis": 8, "cha": 8}
	spec["bonus"] = {}
	spec["skills"] = []
	spec["name"] = {"ko": "", "en": ""}


# ---------- 포인트 구매 ----------

func points_used() -> int:
	return Builder.point_cost(spec["scores"])


func points_left() -> int:
	return Builder.POINT_BUDGET - points_used()


func can_raise(a: String) -> bool:
	var v: int = spec["scores"][a]
	if v >= 15:
		return false
	return Builder.POINT_COST[v + 1] - Builder.POINT_COST[v] <= points_left()


func raise(a: String) -> bool:
	if not can_raise(a):
		return false
	spec["scores"][a] += 1
	return true


func lower(a: String) -> bool:
	if spec["scores"][a] <= 8:
		return false
	spec["scores"][a] -= 1
	return true


# ---------- 능력치 보너스(+2/+1 또는 +1/+1/+1) ----------

func set_bonus_two_one(plus2: String, plus1: String) -> void:
	spec["bonus"] = {plus2: 2} if plus2 == plus1 else {plus2: 2, plus1: 1}


func set_bonus_ones(a: String, b: String, c: String) -> void:
	spec["bonus"] = {a: 1, b: 1, c: 1}


func final_score(a: String) -> int:
	return int(spec["scores"][a]) + int(spec["bonus"].get(a, 0))


# ---------- 출신·클래스 ----------

func set_class(class_id: String) -> void:
	var keep := {"name": spec["name"], "scores": spec["scores"], "bonus": spec["bonus"], "species": spec["species"],
		"lineage": spec.get("lineage", ""), "background": spec["background"], "size": spec.get("size", "")}
	spec = Builder.default_spec(class_id, 1)
	spec.merge(keep, true)
	spec["skills"] = []


func set_species(id: String) -> void:
	spec["species"] = id
	spec["lineage"] = ""
	var sp := RulesDB.get_entry("species", id)
	spec["size"] = sp.get("size", "medium")
	if sp.get("lineage_required", false):
		for lid: String in lineages(id):
			spec["lineage"] = lid
			break


func lineages(species_id: String) -> Array:
	return RulesDB.ids("species").filter(func(i: String) -> bool: return RulesDB.get_entry("species", i).get("parent", "") == species_id)


func species_list() -> Array:
	return RulesDB.ids("species").filter(func(i: String) -> bool: return not RulesDB.get_entry("species", i).has("parent"))


## 체형 틀(1단계): 보통(인간·엘프·티플링·오크), 작은(하플링·노움), 드워프는 작은 체형 변형. 고를 수 있는 종족은 크기를 따른다.
func body_frame() -> String:
	var sp := RulesDB.get_entry("species", spec["species"])
	if sp.get("body", "medium") == "dwarf":
		return "dwarf"
	return "small" if spec.get("size", sp.get("size", "medium")) == "small" else "medium"


func toggle_skill(s: String) -> bool:
	var cls := RulesDB.get_entry("class", spec["class"])
	var list: Array = spec["skills"]
	if s in list:
		list.erase(s)
		return true
	if not s in cls["skills"]["from"] or list.size() >= int(cls["skills"]["choose"]):
		return false
	list.append(s)
	return true


# ---------- 결과 ----------

func errors() -> PackedStringArray:
	var e := Builder.validate(spec)
	if points_left() < 0:
		e.append("포인트 초과")
	return e


func preview() -> Dictionary:
	var r := Builder.build(spec)
	var c: Node = r["creature"]
	if c == null:
		return {"errors": r["errors"]}
	var out := {"errors": r["errors"], "hp": c.hp_max, "ac": c.ac(), "speed": c.speed_tiles, "darkvision": c.darkvision_tiles,
		"saves": {}, "abilities": c.abilities.duplicate(), "spells": c.spells.duplicate(), "features": c.features.duplicate(),
		"body": body_frame()}
	for a: String in ABILITIES:
		out["saves"][a] = c.save_bonus(a)
	c.free()
	return out
