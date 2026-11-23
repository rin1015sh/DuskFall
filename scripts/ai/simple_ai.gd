extends RefCounted
## 간단한 전투 AI(4단계 시험용). 한 생물의 턴을 끝까지 둔다.
## 쓰러진 아군 돕기 → 회복(Healing Word) → 근접 공격 → 사거리 주문·원거리 공격 → 다가가기.
## 적 AI의 난이도·성격은 5단계 이후에 데이터로 옮긴다.

const Combat := preload("res://scripts/rules/combat.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")


const Tactics := preload("res://scripts/ai/tactics.gd")

static func take_turn(world: Dictionary, c: Node) -> void:
	if c.dead or c.is_down() or c.has_flag("cannot_act"):
		return
	if c.has_meta("monster"):
		monster_turn(world, c)
		return
	var grid: Node = world["grid"]
	if c.has_condition("restrained") and c.condition_instance("restrained").get("params", {}).has("escape_dc"):
		Combat.escape(world, c)
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
	# 1-2. 기능: 기능 데이터 ai.when(HP 절반 이하·적 둘 이상)이 맞으면 쓴다(재기의 숨결·행동 연쇄 등), 영체 수호자·범위 주문
	var Features := preload("res://scripts/rules/features.gd")
	for fid: String in c.feature_data.keys():
		var when := str(c.feature_data[fid].get("ai", {}).get("when", ""))
		var res := str(c.feature_data[fid].get("resource", ""))
		if when == "" or when == "never" or (res != "" and c.resource(res) <= 0):
			continue
		if (when == "hp_below_half" and c.hp <= c.hp_max / 2) or (when == "foes_2plus" and _foes(world, c).size() >= 2):
			Features.use(world, c, fid)
	Tactics.pre_turn(world, c)
	_cast_best_area(world, c)
	_light_up(world, c)
	# 2. 공격 행동
	var guard := 0
	while guard < 6 and not c.dead and not c.is_down():
		guard += 1
		var foe := Tactics.pick_target(world, c)
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


# ======================================================================
# 몬스터(데이터의 actions·multiattack·재충전)
# ======================================================================

static func monster_turn(world: Dictionary, m: Node) -> void:
	var MF := preload("res://scripts/rules/monster_factory.gd")
	var grid: Node = world["grid"]
	if m.has_condition("prone"):
		Combat.stand_up(m)
	if m.has_condition("restrained") and m.condition_instance("restrained").get("params", {}).has("escape_dc"):
		Combat.escape(world, m)
		return
	Tactics.pre_turn(world, m)
	var guard := 0
	while guard < 8 and not m.dead and not m.is_down():
		guard += 1
		var foe := Tactics.pick_target(world, m)
		if foe == null:
			return
		if int(m.turn.get("action", 0)) <= 0 and int(m.turn.get("attacks_left", 0)) <= 0:
			break
		var dist: int = grid.distance_between(m, foe)
		var did := false
		# 재충전 능력(내성 행동) 먼저
		for a: Dictionary in MF.actions(m):
			if a["type"] == "save" and int(m.cooldowns.get(a["id"], 0)) == 0 and not a.get("replaces_attack", false):
				var rng: Variant = a.get("range_tiles", 1)
				if dist <= (int(rng) if typeof(rng) != TYPE_ARRAY else int(rng[0])) and grid.can_see(m, foe) \
						and int(m.turn.get("attacks_left", 0)) <= 0:
					did = Combat.monster_action(world, m, a["id"], foe).get("ok", false)
					break
		if did:
			continue
		var best := ""
		var use := "melee"
		for a: Dictionary in MF.actions(m):
			if a["type"] != "attack":
				continue
			var kind: String = a.get("kind", "melee")
			if kind in ["melee", "both"] and dist <= int(a.get("reach_tiles", 1)):
				best = a["id"]
				use = "melee"
				break
		if best == "" and not Combat.is_threatened(world, m):
			for a: Dictionary in MF.actions(m):
				if a["type"] == "attack" and a.get("kind", "melee") in ["ranged", "both"]:
					var atk := MF.to_attack(a, "ranged")
					var ctx := Combat.attack_context(world, m, foe, atk)
					if not ctx.has("invalid"):
						best = a["id"]
						use = "ranged"
						break
		if best != "":
			if not Combat.monster_action(world, m, best, foe, use).get("ok", false):
				break
			continue
		# 행동을 아직 안 썼으면 다가간다
		if not _approach(world, m, foe):
			break
	var f := _nearest_foe(world, m)
	if f != null and not m.dead and grid.distance_between(m, f) > 1 and int(m.turn.get("movement", 0)) > 0:
		_approach(world, m, f)


static func _foes(world: Dictionary, c: Node) -> Array:
	return world["grid"].creatures().filter(func(o: Node) -> bool: return not o.dead and not o.is_down() and c.is_hostile_to(o))


## 빛 주문: 파티 누구도 보지 못하는 적이 있으면 Dancing Lights(없으면 Light)로 그 자리를 밝힌다(예시 전투 1).
static func _light_up(world: Dictionary, c: Node) -> void:
	if int(c.turn.get("action", 0)) <= 0:
		return
	var grid: Node = world["grid"]
	var allies: Array = _allies(world, c) + [c]
	for f: Node in _foes(world, c):
		if allies.any(func(a: Node) -> bool: return grid.can_see(a, f)):
			continue
		var cell: Vector2i = grid.cell_of(f)
		if c.spells.has("dancing_lights") and Spellcasting.can_cast(world, c, "dancing_lights", cell) == "":
			Spellcasting.cast(world, c, "dancing_lights", cell)
			return


## 범위 주문: 아군을 맞히지 않고 적을 둘 이상 맞히는 조준을 찾는다(높은 레벨 주문부터).
static func _cast_best_area(world: Dictionary, c: Node) -> void:
	var grid: Node = world["grid"]
	var order := ["spirit_guardians", "fireball", "lightning_bolt", "shatter", "burning_hands", "thunderwave", "sleep", "hypnotic_pattern"]
	for sid: String in order:
		if not c.spells.has(sid) or int(c.turn.get("action", 0)) <= 0:
			continue
		var spell := RulesDB.get_entry("spell", sid)
		var best_cell := Vector2i(-1, -1)
		var best := 1
		var candidates: Array = []
		for f: Node in _foes(world, c):
			candidates.append(grid.cell_of(f))
		if spell["range"]["type"] == "self":
			candidates = [grid.cell_of(c) + Vector2i(1, 0), grid.cell_of(c) + Vector2i(-1, 0), grid.cell_of(c) + Vector2i(0, 1),
				grid.cell_of(c) + Vector2i(0, -1), grid.cell_of(c) + Vector2i(1, 1), grid.cell_of(c) + Vector2i(-1, -1),
				grid.cell_of(c) + Vector2i(1, -1), grid.cell_of(c) + Vector2i(-1, 1)]
		for cell: Vector2i in candidates:
			if Spellcasting.can_cast(world, c, sid, cell) != "":
				continue
			var cells := Spellcasting.area_cells(world, c, spell, cell)
			var hit: Array = preload("res://scripts/rules/area.gd").creatures_in(grid, cells)
			var foes := hit.filter(func(o: Node) -> bool: return c.is_hostile_to(o) and not o.dead).size()
			var friends := hit.filter(func(o: Node) -> bool: return not c.is_hostile_to(o) and o != c).size()
			if sid == "spirit_guardians":
				foes = _foes(world, c).filter(func(o: Node) -> bool: return grid.distance_between(c, o) <= 4).size()
				friends = 0
			if friends == 0 and foes > best:
				best = foes
				best_cell = cell
		if best_cell.x >= 0:
			Spellcasting.cast(world, c, sid, best_cell)
			return
