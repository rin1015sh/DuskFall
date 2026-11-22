extends RefCounted
## 간단한 전투 AI(4단계 시험용). 한 생물의 턴을 끝까지 둔다.
## 쓰러진 아군 돕기 → 회복(Healing Word) → 근접 공격 → 사거리 주문·원거리 공격 → 다가가기.
## 적 AI의 난이도·성격은 5단계 이후에 데이터로 옮긴다.

const Combat := preload("res://scripts/rules/combat.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")


static func take_turn(world: Dictionary, c: Node) -> void:
	if c.dead or c.is_down() or c.has_flag("cannot_act"):
		return
	var grid: Node = world["grid"]
	if c.has_condition("prone"):
		Combat.stand_up(c)
	# 1. 쓰러진 아군
	for ally: Node in _allies(world, c):
		if ally.is_down():
			if c.spells.has("healing_word") and Spellcasting.can_cast(world, c, "healing_word", grid.cell_of(ally)) == "":
				Spellcasting.cast(world, c, "healing_word", grid.cell_of(ally))
			elif grid.distance_between(c, ally) <= 1:
				Combat.help(world, c, ally)
			else:
				_approach(world, c, ally)
				if grid.distance_between(c, ally) <= 1:
					Combat.help(world, c, ally)
	# 2. 공격 행동
	var guard := 0
	while guard < 6 and not c.dead and not c.is_down():
		guard += 1
		var foe := _nearest_foe(world, c)
		if foe == null:
			return
		if int(c.turn.get("action", 0)) <= 0 and int(c.turn.get("attacks_left", 0)) <= 0:
			break
		if grid.distance_between(c, foe) <= Combat.reach_of(c):
			if c.active_set != "melee":
				Combat.switch_weapon_set(c)
			if not Combat.attack(world, c, foe).get("ok", false):
				break
			continue
		# 주문 공격(소마법)
		var cast := false
		for sid: String in ["fire_bolt", "sacred_flame", "ray_of_frost"]:
			if c.spells.has(sid) and Spellcasting.can_cast(world, c, sid, grid.cell_of(foe)) == "" and grid.can_see(c, foe):
				Spellcasting.cast(world, c, sid, grid.cell_of(foe))
				cast = true
				break
		if cast:
			continue
		# 원거리 무기(위협받지 않을 때)
		var ranged: String = c.weapon_sets.get("ranged", {}).get("main", "")
		if ranged != "" and not Combat.is_threatened(world, c):
			if c.active_set != "ranged":
				Combat.switch_weapon_set(c)
			var p := Combat.preview_attack(world, c, foe)
			if p.get("valid", false):
				if Combat.attack(world, c, foe).get("ok", false):
					continue
		if c.active_set != "melee":
			Combat.switch_weapon_set(c)
		if not _approach(world, c, foe):
			break
	# 3. 남은 이동으로 가장 가까운 적에게 붙기
	var f := _nearest_foe(world, c)
	if f != null and not c.dead and grid.distance_between(c, f) > 1:
		_approach(world, c, f)


static func _approach(world: Dictionary, c: Node, target: Node) -> bool:
	var grid: Node = world["grid"]
	var best := Vector2i(-1, -1)
	var best_cost := 1 << 30
	var budget := int(c.turn.get("movement", 0))
	if budget <= 0:
		return false
	var allies: Array = grid.creatures().filter(func(o: Node) -> bool: return o != c and not o.is_hostile_to(c))
	for cell in grid.occupied_cells(target):
		for d in grid.DIRS_8:
			var n: Vector2i = cell + d
			if not grid.in_bounds(n) or grid.blocks_movement(n) or grid.creature_at(n) != null:
				continue
			var p: Dictionary = grid.find_path(c, n, -1, allies)
			if not p.is_empty() and p["cost"] < best_cost:
				best_cost = p["cost"]
				best = n
	if best.x < 0:
		return false
	# 이동력이 모자라면 경로를 따라 갈 수 있는 데까지
	var path: Dictionary = grid.find_path(c, best, -1, allies)
	var stop: Vector2i = grid.cell_of(c)
	var spent := 0
	var cur: Vector2i = stop
	for n: Vector2i in path["path"]:
		spent += grid.step_cost(cur, n)
		if spent > budget:
			break
		cur = n
		if grid.creature_at(n) == null:
			stop = n
	if stop == grid.cell_of(c):
		return false
	return Combat.move(world, c, stop).get("ok", false)


static func _nearest_foe(world: Dictionary, c: Node) -> Node:
	var grid: Node = world["grid"]
	var best: Node = null
	var best_d := 1 << 30
	for o: Node in grid.creatures():
		if o.dead or o.is_down() or not c.is_hostile_to(o):
			continue
		var d: int = grid.distance_between(c, o)
		if d < best_d:
			best_d = d
			best = o
	return best


static func _allies(world: Dictionary, c: Node) -> Array:
	return world["grid"].creatures().filter(func(o: Node) -> bool: return o != c and not o.dead and o.team == c.team)
