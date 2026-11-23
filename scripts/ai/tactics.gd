extends RefCounted
## 전술 AI(구현 어려운 것 묶음 2): 단순 AI 앞에서 한 번 '좋은 수'를 찾아 쓴다. 규칙은 Combat·Physics·Spellcasting이 처리한다.
##   1. 목표 고르기: 가깝고, HP 비율이 낮고, 집중 중인 시전자를 먼저(쓰러진 적은 노리지 않음 — 보통 난이도).
##   2. 위험 지형 밀치기(파티 AI만 — 적은 밀치기를 쓰지 않음): 인접 적을 2단계 이상 낙하나 피해 표면으로 밀 수 있으면(성공 확률 35% 이상) 보너스 행동으로 민다.
##   3. 폭발물: 내용물이 있는 물체(기름통 등) 반경 안에 적이 둘 이상이고 아군이 없으면 그 물체를 쏜다.
##   4. 고지: 원거리 공격자는 이동력 안에서 2단계 이상 높고, 목표가 사거리·시야 안이며, 적과 붙지 않는 칸으로 먼저 간다.
##   5. 물약: 파티원은 HP 30% 이하이고 물약이 있으면 보너스 행동으로 마신다.

const Combat := preload("res://scripts/rules/combat.gd")
const Physics := preload("res://scripts/rules/physics.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Interact := preload("res://scripts/rules/interact.gd")
const MF := preload("res://scripts/rules/monster_factory.gd")


## 목표 점수(낮을수록 먼저): 거리 + HP 비율×4 − 집중 중이면 2
static func pick_target(world: Dictionary, c: Node) -> Node:
	var grid: Node = world["grid"]
	var best: Node = null
	var best_s := INF
	for o: Node in grid.creatures():
		if o.dead or o.is_down() or not c.is_hostile_to(o) or o.has_flag("ethereal"):
			continue
		var s: float = grid.distance_between(c, o) + 4.0 * float(o.hp) / maxf(o.hp_max, 1)
		if not o.concentration.is_empty():
			s -= 2.0
		if not grid.can_see(c, o):
			s += 3.0
		if s < best_s:
			best_s = s
			best = o
	return best


## 턴 앞부분에 한 번: 쓸 만한 수가 있으면 쓰고 true
static func pre_turn(world: Dictionary, c: Node) -> bool:
	var used := false
	if c.team == "party" and _drink(world, c):
		used = true
	if _shove_hazard(world, c):
		used = true
	if _explode(world, c):
		used = true
	if _high_ground(world, c):
		used = true
	return used


static func _drink(world: Dictionary, c: Node) -> bool:
	if float(c.hp) / maxf(c.hp_max, 1) > 0.3 or int(c.turn.get("bonus", 0)) <= 0:
		return false
	for item: String in ["potion_of_healing", "potion_of_greater_healing", "potion_of_superior_healing"]:
		if Interact.count(world, item, c) > 0:
			var r := Combat.drink_potion(c, RulesDB.get_entry("item", item).get("effects", []), null, world)
			if r.get("ok", false):
				Interact.take(world, item, 1, c)
				return true
	return false


static func _hazard(grid: Node, cell: Vector2i) -> bool:
	var sid: String = grid.surface_id(cell)
	if sid == "":
		return false
	var def := RulesDB.get_entry("surface", sid)
	for e: Dictionary in def.get("on_enter_or_turn_start", []) + def.get("on_move", []):
		if e.get("type", "") == "damage":
			return true
	return false


static func _shove_hazard(world: Dictionary, c: Node) -> bool:
	# 적은 밀치기를 쓰지 않는다(사용자 결정 2026-11-22). 파티 AI(자동 전투)만 쓴다.
	if c.team != "party" or c.has_meta("monster") or int(c.turn.get("bonus", 0)) <= 0:
		return false
	var grid: Node = world["grid"]
	for o: Node in grid.creatures():
		if o.dead or not c.is_hostile_to(o) or grid.distance_between(c, o) > 1:
			continue
		var p := Physics.preview_shove(grid, c, o)
		if not p.get("valid", false) or float(p.get("chance", 0.0)) < 0.35:
			continue
		if int(p["fall_levels"]) >= 2 or _hazard(grid, p["landing"]):
			return Combat.shove(world, c, o).get("ok", false)
	return false


static func _explode(world: Dictionary, c: Node) -> bool:
	if int(c.turn.get("action", 0)) <= 0:
		return false
	var grid: Node = world["grid"]
	for cell in grid.objects.keys():
		var obj: Dictionary = grid.objects[cell]
		var contents: Dictionary = obj.get("contents", {})
		if contents.is_empty():
			continue
		var r: int = int(contents.get("radius", 0)) + 1
		var foes := 0
		var friends := 0
		for o: Node in grid.creatures():
			if o.dead or grid.distance(grid.cell_of(o), cell) > r:
				continue
			if c.is_hostile_to(o):
				foes += 1
			elif o.team == c.team:
				friends += 1
		if foes < 2 or friends > 0:
			continue
		if c.has_meta("monster"):
			continue  # 몬스터 행동은 데이터 공격만(물체 공격 미지원)
		var ranged: String = c.weapon_sets.get("ranged", {}).get("main", "")
		if ranged == "" or not grid.has_line_of_sight(grid.cell_of(c), cell):
			continue
		if c.active_set != "ranged":
			Combat.switch_weapon_set(c)
		if Combat.attack_object(world, c, cell).get("ok", false):
			return true
	return false


static func _high_ground(world: Dictionary, c: Node) -> bool:
	var grid: Node = world["grid"]
	var ranged := false
	if c.has_meta("monster"):
		for a: Dictionary in MF.actions(c):
			ranged = ranged or a.get("kind", "") in ["ranged", "both"]
	else:
		var role := str(RulesDB.get_entry("class", c.class_id).get("ai_role", "melee"))  # 클래스 데이터 ai_role
		ranged = c.weapon_sets.get("ranged", {}).get("main", "") != "" and role in ["ranged", "caster"]
	if not ranged or int(c.turn.get("movement", 0)) <= 0 or Combat.is_threatened(world, c):
		return false
	var target := pick_target(world, c)
	if target == null:
		return false
	var here: int = grid.height(grid.cell_of(c))
	var budget: int = int(c.turn["movement"])
	var allies: Array = grid.creatures().filter(func(o: Node) -> bool: return o != c and not o.is_hostile_to(c))
	var best := Vector2i(-1, -1)
	var best_h := here + 1
	var o: Vector2i = grid.cell_of(c)
	for dy in range(-budget, budget + 1):
		for dx in range(-budget, budget + 1):
			var n := o + Vector2i(dx, dy)
			if not grid.in_bounds(n) or grid.blocks_movement(n) or grid.creature_at(n) != null:
				continue
			var h: int = grid.height(n)
			if h <= best_h or grid.distance(n, grid.cell_of(target)) > 12 or not grid.has_line_of_sight(n, grid.cell_of(target)):
				continue
			var near_foe := false
			for f: Node in grid.creatures():
				if not f.dead and c.is_hostile_to(f) and grid.distance(grid.cell_of(f), n) <= 1:
					near_foe = true
			if near_foe:
				continue
			var p: Dictionary = grid.find_path(c, n, budget, allies)
			if p.is_empty():
				continue
			best = n
			best_h = h
	if best.x < 0:
		return false
	return Combat.move(world, c, best).get("ok", false)
