extends RefCounted
## 은신과 감지(룰북 5단계 '은신과 감지', 4단계 빛·가려짐). 상태 없음 — 알아챔 상태는 관찰자 생물(awareness)에 둔다.
##
## - 시야 원뿔: 관찰자가 바라보는 쪽 90°, 길이 sight_tiles(기본 8칸), 벽·시야를 끊는 구름에서 끊긴다.
## - 원뿔 안 칸의 빛(관찰자 기준 가려짐)으로 결과가 갈린다: 밝음 = 숨어도 바로 발견, 어스름 = 은신 대 수동 지각,
##   어둠 = 눈으로는 발견 못 함(암시야는 한 단계 낮춰 본다).
## - 은신 판정은 원뿔에 들어갈 때 1번, 같은 원뿔 안에 머물면 턴 틱(6초)마다 다시.
## - 발견 이후: 의심(마지막 위치로 시선을 돌림) → 수색(2칸 안 감지 행동) → 발견(alerted).

const Resolver := preload("res://scripts/rules/resolver.gd")

## 수색에서 숨은 존재를 감지하는 거리(5단계: 감지 행동 2칸)
const SEARCH_TILES := 2


const Area := preload("res://scripts/rules/area.gd")
## 시야 원뿔 반각 45°(90° 원뿔 — changes.md)
const CONE_HALF := PI / 4


## 시야 원뿔: 관찰자 칸 가운데에서 바라보는 쪽으로 반각 45°, 길이 sight_tiles + 0.5의 매끄러운 원뿔.
## 칸 → 덮인 비율(Area.cov_cone, 벽에 막힌 칸 제외). 시야를 끊는 구름은 시야선으로 따로 본다.
static func cone_coverage(grid: Node, observer: Node) -> Dictionary:
	var o: Vector2i = grid.cell_of(observer)
	var f := Vector2(observer.facing).normalized()
	if f == Vector2.ZERO:
		f = Vector2(0, 1)
	var cov := Area.cov_cone(grid, o, Vector2(o) + Vector2(0.5, 0.5) + f, int(observer.sight_tiles), CONE_HALF)
	for c: Vector2i in cov.keys():
		if not grid.has_line_of_sight(o, c):
			cov.erase(c)
	return cov


static func cone_cells(grid: Node, observer: Node) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Vector2i in cone_coverage(grid, observer):
		out.append(c)
	return out


## 대상이 원뿔에 덮인 정도(0이면 밖, FULL 미만이면 원뿔 가장자리에 걸침)
static func cone_fraction(grid: Node, observer: Node, target: Node) -> float:
	return Area.creature_cover(grid, cone_coverage(grid, observer), target)


static func in_cone(grid: Node, observer: Node, target: Node) -> bool:
	return cone_fraction(grid, observer, target) > 0.0


## 수동 지각 = 10 + 지혜 수정치 + 지각 기능 보너스(SRD).
static func passive_perception(c: Node) -> int:
	return 10 + c.ability_mod("wis") + int(c.skill_bonuses.get("perception", 0))


static func stealth_bonus(c: Node) -> int:
	var b: int = c.ability_mod("dex") + int(c.skill_bonuses.get("stealth", 0))
	for m in c.modifier_entries():
		var e: Dictionary = m["effect"]
		if e["type"] == "modify" and e["stat"] == "stealth":
			b += int(e.get("add", 0))  # Pass without Trace +10
	return b


## 관찰자가 대상을 눈으로 어떻게 보는가: "bright"(바로 발견) | "dim"(은신 판정) | "dark"(못 봄) | "none"(원뿔 밖·시야 막힘)
static func sight_of(grid: Node, observer: Node, target: Node) -> String:
	if observer.has_condition("blinded") or not in_cone(grid, observer, target):
		return "none"
	var best := 2
	for c in grid.occupied_cells(target):
		best = mini(best, grid.obscurity_for(observer, c))
	if target.has_condition("invisible") and not (observer.senses.has("see_invisible") or observer.senses.has("truesight")):
		best = 2
	return ["bright", "dim", "dark"][best]


## 한 관찰자가 한 대상을 살핀다. entering = 원뿔에 막 들어옴(또는 틱마다 다시 굴림).
## 결과: "" | "suspicious" | "alerted"
static func observe(grid: Node, observer: Node, target: Node) -> String:
	if observer.dead or observer.is_incapacitated() or target.dead or not observer.is_hostile_to(target):
		return ""
	var seen := sight_of(grid, observer, target)
	var aw: Dictionary = observer.awareness.get(target, {})
	var state: String = aw.get("state", "")
	if seen == "none" or seen == "dark":
		if target.has_condition("invisible") and grid.distance_between(observer, target) <= SEARCH_TILES and state == "":
			return _mark(observer, target, "suspicious", grid)  # 투명이어도 가까우면 기척을 느낀다
		return ""
	if not target.sneaking and not target.has_condition("invisible"):
		return _mark(observer, target, "alerted", grid)
	if seen == "bright":
		return _mark(observer, target, "alerted", grid)  # 밝은 곳에서는 숨어도 바로 발견(4단계)
	# 어스름: 은신(능동) 대 수동 지각
	var r := Resolver.ability_check(target, "dex", passive_perception(observer), {"skill": "stealth",
		"bonus": stealth_bonus(target) - target.ability_mod("dex") - int(target.skill_bonuses.get("stealth", 0))})
	target.set_meta("stealth_total", r["total"])
	# 은신 합계가 찾는 쪽의 DC다: 수동 지각 ≥ 합계면 발견(SRD Hide). 자연 20·1은 능력 판정 규칙대로.
	var nat := int(r["natural"])
	var hidden: bool = nat == 20 or (nat != 1 and int(r["total"]) > passive_perception(observer))
	if hidden:
		return ""
	return _mark(observer, target, "suspicious" if state == "" else "alerted", grid)


## 수색: 의심·수색 상태의 관찰자가 마지막 위치 2칸 안에서 숨은 존재 감지(지각 대 은신 합계).
static func search(grid: Node, observer: Node, target: Node) -> String:
	var aw: Dictionary = observer.awareness.get(target, {})
	if aw.is_empty() or aw["state"] == "alerted":
		return ""
	if grid.distance_between(observer, target) > SEARCH_TILES:
		return ""  # 멀면 마지막 위치 쪽을 바라보기만 한다(의심 유지)
	var dc: int = int(target.get_meta("stealth_total", 10 + stealth_bonus(target)))
	var r := Resolver.ability_check(observer, "wis", dc, {"skill": "perception"})
	if r["success"]:
		return _mark(observer, target, "alerted", grid)
	observer.awareness[target]["state"] = "searching"
	return ""


static func _mark(observer: Node, target: Node, state: String, grid: Node) -> String:
	observer.awareness[target] = {"state": state, "last": grid.cell_of(target)}
	if state == "suspicious":
		face_toward(grid, observer, grid.cell_of(target))
	Dice.log_text("%s: %s %s" % [observer.label(), target.label(), {"suspicious": "?", "alerted": "!", "searching": "…"}[state]])
	return state


static func face_toward(grid: Node, c: Node, cell: Vector2i) -> void:
	var d: Vector2i = cell - grid.cell_of(c)
	if d != Vector2i.ZERO:
		c.facing = Vector2i(signi(d.x), signi(d.y))


static func is_aware(observer: Node) -> bool:
	for k in observer.awareness.keys():
		if observer.awareness[k].get("state", "") != "":
			return true
	return false


## 숨은 채 공격: 피격자 쪽 적 전원이 공격 방향을 보고 수색 상태가 되고, 은신 유지 판정은 불리(9단계 악용 4).
static func after_hidden_attack(grid: Node, attacker: Node, target: Node) -> void:
	for o: Node in grid.creatures():
		if o.dead or not o.is_hostile_to(attacker) or o.team != target.team:
			continue
		face_toward(grid, o, grid.cell_of(attacker))
		o.awareness[attacker] = {"state": "searching", "last": grid.cell_of(attacker)}
