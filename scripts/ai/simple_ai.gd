extends RefCounted
## 간단한 전투 AI(4단계 시험용). 한 생물의 턴을 끝까지 둔다.
## 쓰러진 아군 돕기 → 회복(Healing Word) → 근접 공격 → 사거리 주문·원거리 공격 → 다가가기.
## 적 AI의 난이도·성격은 5단계 이후에 데이터로 옮긴다.

const SpellRoles := preload("res://scripts/ai/spell_roles.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const DiceExpr := preload("res://scripts/rules/dice_expr.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")


const Tactics := preload("res://scripts/ai/tactics.gd")

static func take_turn(world: Dictionary, c: Node) -> void:
	if c.dead or c.is_down() or c.has_flag("cannot_act"):
		return
	if c.has_condition("maddened"):
		_maddened_turn(world, c)
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
			var heal := ""
			for sid: String in SpellRoles.known(c, "heal"):
				if Spellcasting.can_cast(world, c, sid, grid.cell_of(ally)) == "":
					heal = sid
					break
			if heal != "":
				Spellcasting.cast(world, c, heal, grid.cell_of(ally))
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
		elif when == "ally_buff":
			for ally: Node in _allies(world, c):
				if ally != c and not ally.is_down() and Features.use(world, c, fid, ally).get("ok", false):
					break  # 바드의 영감 등: 받을 수 있는 첫 아군
	Tactics.pre_turn(world, c)
	_cast_best_area(world, c)
	_cast_best_single(world, c)
	_light_up(world, c)
	# 2. 공격 행동(기능 ai.when before_attack — 인접한 적이 있으면 먼저: 무모한 공격)
	var first := Tactics.pick_target(world, c)
	if first != null and grid.distance_between(c, first) <= Combat.reach_of(c):
		_use_when(world, c, "before_attack", first)
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
			decide_toggles(world, c, foe)
			if try_weapon_action(world, c, foe):
				continue
			if not Combat.attack(world, c, foe).get("ok", false):
				break
			continue
		# 주문 공격(소마법)
		var cast := false
		for sid: String in SpellRoles.known(c, "attack_cantrip"):
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
				decide_toggles(world, c, foe)
				if try_weapon_action(world, c, foe):
					continue
				if Combat.attack(world, c, foe).get("ok", false):
					continue
		if c.active_set != "melee":
			Combat.switch_weapon_set(c)
		if not _approach(world, c, foe):
			break
	# 2-2. 공격 뒤 보너스 행동 기능(ai.when after_attack — 몽크 연타·보너스 비무장 공격, ai.priority 높은 것 먼저)
	var near := Tactics.pick_target(world, c)
	if near != null and not c.dead and grid.distance_between(c, near) <= 1:
		_use_when(world, c, "after_attack", near)
	# 3. 남은 이동으로 가장 가까운 적에게 붙기
	var f := _nearest_foe(world, c)
	if f != null and not c.dead and grid.distance_between(c, f) > 1:
		_approach(world, c, f)
	# 4. 턴 끝 기능(ai.when end_of_turn — 분노 연장: 스크립트가 필요할 때만 쓴다)
	if not c.dead:
		_use_when(world, c, "end_of_turn", null)


## ai.when이 그 시점인 기능을 우선순위(ai.priority) 순서로 하나 쓴다(자원·비용이 없으면 다음).
static func _use_when(world: Dictionary, c: Node, when: String, target: Node) -> void:
	var Features := preload("res://scripts/rules/features.gd")
	var fids: Array = c.feature_data.keys().filter(func(fid: String) -> bool:
		return str(c.feature_data[fid].get("ai", {}).get("when", "")) == when)
	fids.sort_custom(func(a: String, b: String) -> bool:
		return int(c.feature_data[a]["ai"].get("priority", 0)) > int(c.feature_data[b]["ai"].get("priority", 0)))
	for fid: String in fids:
		var res := str(c.feature_data[fid].get("resource", ""))
		if res != "" and c.resource(res) <= 0:
			continue
		var t: Variant = target if str(c.feature_data[fid].get("target", "self")) in ["enemy", "creature"] else null
		if Features.use(world, c, fid, t).get("ok", false):
			return


static func _approach(world: Dictionary, c: Node, target: Node) -> bool:
	var grid: Node = world["grid"]
	var best := Vector2i(-1, -1)
	var best_cost := 1 << 30
	var budget := int(c.turn.get("movement", 0))
	if budget <= 0:
		return false
	var allies: Array = grid.creatures().filter(func(o: Node) -> bool: return o != c and not o.is_hostile_to(c))
	var danger := _danger_map(grid, c)
	for cell in grid.occupied_cells(target):
		for d in grid.DIRS_8:
			var n: Vector2i = cell + d
			if not grid.in_bounds(n) or grid.blocks_movement(n) or grid.creature_at(n) != null:
				continue
			var p: Dictionary = grid.find_path(c, n, -1, allies, danger)
			if not p.is_empty() and p["cost"] < best_cost:
				best_cost = p["cost"]
				best = n
	if best.x < 0:
		return false
	# 이동력이 모자라면 경로를 따라 갈 수 있는 데까지
	var path: Dictionary = grid.find_path(c, best, -1, allies, danger)
	var stop: Vector2i = grid.cell_of(c)
	var spent := 0
	var cur: Vector2i = stop
	for n: Vector2i in path["path"]:
		spent += grid.step_cost(cur, n)
		if spent > budget:
			break
		cur = n
		if grid.creature_at(n) == null and not danger.has(n):
			stop = n  # 위험한 표면 위에서는 멈추지 않는다
	if stop == grid.cell_of(c):
		return false
	return Combat.move(world, c, stop).get("ok", false)


## AI 경로 가중치: 위험한 표면 칸(피해·연소 — Tactics.surface_danger)은 돌아가게. 비행하면 무시.
static func _danger_map(grid: Node, c: Node) -> Dictionary:
	var out := {}
	if c.has_flag("flying"):
		return out
	for cell in grid.all_cells():
		var sid: String = grid.surface_id(cell)
		if sid != "":
			var n: int = Tactics.surface_danger(sid)
			if n > 0:
				out[cell] = 6 * n
	return out


## 광기의 관: 건 생물이 아닌 가장 가까운 생물(아군이어도)에게 다가가 근접 공격 한 번.
static func _maddened_turn(world: Dictionary, c: Node) -> void:
	var grid: Node = world["grid"]
	var src: Variant = c.condition_instance("maddened").get("source")
	var best: Node = null
	for o: Node in grid.creatures():
		if o == c or o == src or o.dead or o.is_down():
			continue
		if best == null or grid.distance_between(c, o) < grid.distance_between(c, best):
			best = o
	if best == null:
		return
	if grid.distance_between(c, best) > 1:
		_approach(world, c, best)
	if grid.distance_between(c, best) <= 1:
		var w: String = c.weapon("main")
		Combat.attack(world, c, best, {} if w != "" and not Combat.is_ranged_weapon(Combat.weapon_data(w)) else {"weapon": "unarmed"})


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
	_monster_bonus(world, m, "start")
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
						and int(m.turn.get("attacks_left", 0)) <= 0 and _area_ok(world, m, a, foe):
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
	_monster_bonus(world, m)


## 범위 행동(숨결 등): 같은 편이 맞으면 적이 더 많이 맞을 때만 쓴다(BG3 AI는 아군 피격을 꺼린다).
static func _area_ok(world: Dictionary, m: Node, a: Dictionary, foe: Node) -> bool:
	if not a.has("area"):
		return true
	var hit: Array = Combat.monster_area_targets(world, m, a, foe)
	var friends := hit.filter(func(o: Node) -> bool: return not m.is_hostile_to(o)).size()
	var foes := hit.filter(func(o: Node) -> bool: return m.is_hostile_to(o)).size()
	return foes > 0 and friends * 2 < foes


## 몬스터 보너스 행동(데이터 bonus_actions, 이름이 아니라 필드로):
##   move "half_toward_enemy" — 턴 앞에서 속도 절반만큼 더 다가간다(돌진류).
##   options ["disengage", "hide"] — 턴 끝에 적과 붙어 있으면 숨기(안 보일 때) 또는 이탈(날렵한 탈출류).
static func _monster_bonus(world: Dictionary, m: Node, phase: String = "end") -> void:
	if m.dead or m.is_down() or int(m.turn.get("bonus", 0)) <= 0:
		return
	var grid: Node = world["grid"]
	var foe := _nearest_foe(world, m)
	if foe == null:
		return
	for b: Dictionary in m.get_meta("monster", {}).get("bonus_actions", []):
		if phase == "start" and str(b.get("move", "")) == "half_toward_enemy" and grid.distance_between(m, foe) > 1:
			m.turn["bonus"] = int(m.turn["bonus"]) - 1
			m.turn["movement"] = int(m.turn.get("movement", 0)) + m.speed() / 2
			_approach(world, m, foe)
			return
		if phase == "end" and b.has("options") and grid.distance_between(m, foe) <= 1:
			if "hide" in b["options"] and Combat.hide(world, m, "bonus").get("ok", false):
				return
			if "disengage" in b["options"]:
				Combat.disengage(m, "bonus")
				return


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
		for sid: String in SpellRoles.known(c, "light"):
			if Spellcasting.can_cast(world, c, sid, cell) == "":
				Spellcasting.cast(world, c, sid, cell)
				return


## 범위 주문: 아군을 맞히지 않고 적을 둘 이상 맞히는 조준을 찾는다(높은 레벨 주문부터).
## 슬롯을 쓸 만한 강한 적(지금 HP 기준 — 사용자 결정 전 1차 기준값).
const WORTHY_HP := 40


## 지금 집중 중이면 다른 집중 주문은 쓰지 않는다(쓰면 먼저 건 집중이 끊긴다).
static func _breaks_concentration(c: Node, spell: Dictionary) -> bool:
	return bool(spell.get("concentration", false)) and not c.concentration.is_empty()


static func _cast_best_area(world: Dictionary, c: Node) -> void:
	var grid: Node = world["grid"]
	var order: Array = SpellRoles.known(c, "aura") + SpellRoles.known(c, "area")  # 주문 데이터로 분류(높은 레벨부터)
	for sid: String in order:
		if not c.spells.has(sid) or int(c.turn.get("action", 0)) <= 0:
			continue
		var spell := RulesDB.get_entry("spell", sid)
		if _breaks_concentration(c, spell):
			continue
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
			if SpellRoles.role_of(spell) == "aura":
				var rad := int(spell.get("area", {}).get("radius_tiles", 3)) + 1
				foes = _foes(world, c).filter(func(o: Node) -> bool: return grid.distance_between(c, o) <= rad).size()
				friends = 0
			# 적 둘 이상, 또는 강한 적 하나(HP WORTHY_HP 이상 — 큰 몬스터에게도 범위 주문을 쓴다)
			var score := foes
			if foes == 1 and SpellRoles.role_of(spell) == "area":
				var one: Array = hit.filter(func(o: Node) -> bool: return c.is_hostile_to(o) and not o.dead)
				if not one.is_empty() and int(one[0].hp) >= WORTHY_HP and _deals_area_damage(spell):
					score = 2
			if friends == 0 and score > best:
				best = score
				best_cell = cell
		if best_cell.x >= 0:
			Spellcasting.cast(world, c, sid, best_cell)
			return


static func _deals_area_damage(spell: Dictionary) -> bool:
	for e: Dictionary in spell.get("effects", {}).get("fail", []):
		if str(e.get("type", "")) == "damage":
			return true
	return false


## 단일 대상 슬롯 주문: 사거리 안 보이는 적 중 HP가 가장 많은 적(WORTHY_HP 이상)에게 가장 높은 레벨 주문 하나.
static func _cast_best_single(world: Dictionary, c: Node) -> void:
	if int(c.turn.get("action", 0)) <= 0:
		return
	var grid: Node = world["grid"]
	var foes: Array = _foes(world, c).filter(func(o: Node) -> bool: return int(o.hp) >= WORTHY_HP and grid.can_see(c, o))
	if foes.is_empty():
		return
	foes.sort_custom(func(a: Node, b: Node) -> bool: return a.hp > b.hp)
	for sid: String in SpellRoles.known(c, "single"):
		var spell := RulesDB.get_entry("spell", sid)
		if _breaks_concentration(c, spell):
			continue
		for f: Node in foes:
			if _already_has(f, spell):
				continue
			if Spellcasting.can_cast(world, c, sid, grid.cell_of(f)) == "":
				Spellcasting.cast(world, c, sid, grid.cell_of(f), {"targets": [f]})
				return


## 같은 상태를 이미 건 대상에게는 또 걸지 않는다(속박·추방 등).
static func _already_has(t: Node, spell: Dictionary) -> bool:
	for e: Dictionary in spell.get("effects", {}).get("fail", []):
		if str(e.get("type", "")) == "apply_condition" and t.has_condition(str(e["id"])):
			return true
	return false


## 명중 −5 / 피해 +10 재주(기능 ai.toggle accuracy_trade — 대형 무기 달인·저격수): 이 대상에게 켠 쪽의 기대 피해가 크면 켠다.
static func decide_toggles(world: Dictionary, c: Node, foe: Node) -> void:
	for fid: String in c.feature_data:
		if str(c.feature_data[fid].get("ai", {}).get("toggle", "")) != "accuracy_trade":
			continue
		c.options[fid] = "off"
		var off := Combat.preview_attack(world, c, foe)
		c.options[fid] = "on"
		var on := Combat.preview_attack(world, c, foe)
		if not off.get("valid", false) or not on.get("valid", false):
			c.options[fid] = "off"
			continue
		var avg := 0.0
		for p: Dictionary in off.get("attack", {}).get("damage", []):
			avg += float(DiceExpr.stats(str(p["dice"])).get("avg", 0.0))
		avg += float(off.get("attack", {}).get("flat_damage", 0))
		var gain_on := float(on.get("hit_chance", 0.0)) * (avg + 10.0)
		var gain_off := float(off.get("hit_chance", 0.0)) * avg
		c.options[fid] = "on" if gain_on > gain_off else "off"


## 무기 액션·특수 공격(BG3): 턴의 첫 공격에서, 대상에게 쓸 수 있는 공격형 무기 액션(자원이 남은 것)을 하나 쓴다.
## 자원이 짧은 휴식마다 회복되는 것만(무기 액션 1회·기법 주사위 등). 대상이 이미 그 효과에 걸렸으면 건너뛴다.
static func try_weapon_action(world: Dictionary, c: Node, foe: Node) -> bool:
	if c.turn.get("ai_wa_used", false) or c.has_meta("monster"):
		return false
	var Actions := preload("res://scripts/rules/actions.gd")
	for key: String in Actions.weapon_actions_for(c):
		var wa := RulesDB.get_entry("weapon_action", key)
		if str(wa.get("cost", "")) != "action" or str(wa.get("kind", "")) in ["self_buff", "ally_temp_hp", "passive", "command"]:
			continue
		if str(wa.get("target", "enemy")) != "enemy":
			continue
		var cond := str(wa.get("condition", ""))
		if cond != "" and foe.has_condition(cond):
			continue
		if Actions.unavailable(world, c, key) != "":
			continue
		var r: Dictionary = Actions.execute(world, c, key, world["grid"].cell_of(foe))
		if r.get("ok", true):
			c.turn["ai_wa_used"] = true
			return true
	return false
