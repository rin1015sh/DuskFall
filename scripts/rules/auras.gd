extends RefCounted
## 오라(팔라딘 보호의 오라·용기의 오라·헌신의 오라 — SRD 5.2.1): 기능 데이터 "aura"
##   {"range_by_level": {"6": 2, "18": 6}(칸), "save_bonus": "cha"(내성 + 그 수정치, 최소 1), "immune": ["frightened"]}
## 생성기가 기능들의 aura를 생물 meta "aura"로 합친다(범위는 range_by_level이 있는 기능 것, 면역은 모두).
## 주인 자신과 적대하지 않는 생물이 범위 안에 있으면 받는다. 주인이 무력화·쓰러지면 꺼진다. 여러 팔라딘의 내성 보너스는 가장 큰 하나만.


static func _grid() -> Node:
	var rq: Node = EventBus.reaction_queue
	if rq == null or not is_instance_valid(rq) or not rq.world.has("grid"):
		return null
	return rq.world["grid"]


static func range_of(owner: Node) -> int:
	var a: Dictionary = owner.get_meta("aura", {})
	var lv: int = owner.feature_level(str(a.get("feature", "")))
	var best := 0
	var best_lv := 0
	for k: String in a.get("range_by_level", {}):
		if lv >= int(k) and int(k) >= best_lv:
			best_lv = int(k)
			best = int(a["range_by_level"][k])
	return best


## c에게 닿는 오라 주인들.
static func owners_for(c: Node) -> Array:
	var grid := _grid()
	if grid == null or not grid.creatures().has(c):
		return []
	var out: Array = []
	for o: Node in grid.creatures():
		if not o.has_meta("aura") or o.dead or o.hp <= 0 or o.is_incapacitated():
			continue
		if o != c and o.is_hostile_to(c):
			continue
		if o == c or grid.distance_between(o, c) <= range_of(o):
			out.append(o)
	return out


static func save_bonus(c: Node) -> int:
	var best := 0
	for o: Node in owners_for(c):
		var ab := str(o.get_meta("aura").get("save_bonus", ""))
		if ab != "":
			best = maxi(best, maxi(1, o.ability_mod(ab)))
	return best


static func immune(c: Node, condition_id: String) -> bool:
	for o: Node in owners_for(c):
		if condition_id in o.get_meta("aura").get("immune", []):
			return true
	return false
