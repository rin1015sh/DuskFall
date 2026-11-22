extends RefCounted
## 전투 행동(상태 없음). 룰북 3단계 '턴 자원', '행동 목록', 기회 공격·근접 위협, 6단계 무기 마스터리.
## 행동 비용을 확인·소모하고 Resolver·Physics·GridWorld를 불러 결과를 낸다.
## 모든 함수는 첫 인자로 world를 받는다: {"grid", "surfaces", "reactions"(ReactionQueue, 없으면 null)}

const Resolver := preload("res://scripts/rules/resolver.gd")
const Physics := preload("res://scripts/rules/physics.gd")
const Area := preload("res://scripts/rules/area.gd")

## 비무장 공격(SRD Unarmed Strike: 1 + 근력 수정치 타격).
const UNARMED := {"id": "unarmed", "damage": "1", "damage_type": "bludgeoning", "properties": [],
	"category": "simple_melee", "mastery": ""}


# ======================================================================
# 비용
# ======================================================================

static func can_spend(c: Node, cost: String) -> bool:
	match cost:
		"free":
			return true
		"reaction":
			return c.can_react()
	return int(c.turn.get(cost, 0)) > 0


static func spend(c: Node, cost: String) -> bool:
	if not can_spend(c, cost):
		return false
	if cost != "free":
		c.turn[cost] = int(c.turn.get(cost, 0)) - 1
	return true


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


# ======================================================================
# 무기 공격
# ======================================================================

static func weapon_data(id: String) -> Dictionary:
	if id == "" or id == "unarmed":
		return UNARMED
	return RulesDB.get_entry("weapon", id)


static func is_ranged_weapon(w: Dictionary) -> bool:
	return str(w.get("category", "")).ends_with("ranged")


## 무기의 도달(칸): 기본 1, 리치 무기 2(3단계 기회 공격).
static func reach_of(c: Node) -> int:
	var w := weapon_data(c.weapon_sets.get("melee", {}).get("main", ""))
	return 2 if "reach" in w.get("properties", []) else 1


## 무기 공격 정의(Resolver.attack용)를 만든다. opts: {"hand": "main"|"off", "thrown": bool}
## 능력: 원거리 무기는 민첩, 교묘(finesse)는 근력·민첩 중 큰 쪽, 나머지는 근력.
## 보조 공격(off)은 피해에 능력 수정치를 더하지 않는다(음수면 더함, Two-Weapon Fighting이면 더함).
static func build_weapon_attack(c: Node, weapon_id: String, opts: Dictionary = {}) -> Dictionary:
	var w := weapon_data(weapon_id)
	var props: Array = w.get("properties", [])
	var ranged: bool = is_ranged_weapon(w) or opts.get("thrown", false)
	var ability := "dex" if is_ranged_weapon(w) else "str"
	if "finesse" in props and c.ability_mod("dex") > c.ability_mod("str"):
		ability = "dex"
	var mod: int = c.ability_mod(ability)
	var proficient: bool = w["id"] == "unarmed" or c.weapon_proficiencies.has(w["id"]) \
		or c.weapon_proficiencies.has(str(w.get("category", "")).get_slice("_", 0))
	var dice: String = w["damage"]
	if "versatile" in props and opts.get("two_handed", false) and c.weapon("off") == "":
		dice = w["versatile_damage"]
	var dmg_mod := mod
	if opts.get("hand", "main") == "off" and mod > 0 and not c.features.has("two_weapon_fighting"):
		dmg_mod = 0
	if opts.get("no_ability_damage", false) and mod > 0:
		dmg_mod = 0
	var expr := dice if dmg_mod == 0 else "%s%+d" % [dice, dmg_mod]
	if w["id"] == "unarmed":
		expr = str(maxi(1 + mod, 0)) if mod != 0 else "1"
	var dis: Array = []
	if "heavy" in props and ((not ranged and c.abilities["str"] < 13) or (ranged and c.abilities["dex"] < 13)):
		dis.append("무거운 무기")
	var extra_adv: Array = []
	for r: Dictionary in c.attack_riders:
		if r.get("when", "") == "advantage":
			extra_adv.append({"dice": r["dice"], "damage_type": r.get("damage_type", w["damage_type"])})
	return {"name": w.get("name", {}).get("en", w["id"]) if w.has("name") else w["id"], "weapon_id": w["id"],
		"extra_if_advantage": extra_adv,
		"bonus": mod + (c.proficiency_bonus if proficient else 0), "ability": ability, "ability_mod": mod,
		"kind": "ranged" if ranged else "melee", "weapon": true, "properties": props,
		"mastery": w.get("mastery", "") if c.weapon_masteries.has(w["id"]) else "",
		"damage": [{"dice": expr, "damage_type": w["damage_type"]}], "extra_disadvantage": dis,
		"range_tiles": w.get("range_tiles", [reach_of(c), reach_of(c)]) if ranged else [1, 1]}


## 공격 상황: 격자 ctx + 사거리(먼 사거리 불리) + 근접 위협(원거리 공격 불리) + 무거운 무기.
## 사거리 밖이면 {"invalid": 이유}.
static func attack_context(world: Dictionary, attacker: Node, target: Node, atk: Dictionary) -> Dictionary:
	var grid: Node = world["grid"]
	var ctx: Dictionary = grid.attack_context(attacker, target)
	ctx["disadvantage"].append_array(atk.get("extra_disadvantage", []))
	var dist: int = ctx["distance_tiles"]
	if atk["kind"] == "melee":
		var reach := 2 if "reach" in atk.get("properties", []) else 1
		if dist > reach:
			ctx["invalid"] = "도달 밖"
	else:
		var rng: Array = atk.get("range_tiles", [1, 1])
		var normal: int = grid.effective_range(attacker, grid.cell_of(target), rng[0])
		var long: int = grid.effective_range(attacker, grid.cell_of(target), rng[1])
		if dist > long:
			ctx["invalid"] = "사거리 밖"
		elif dist > normal:
			ctx["disadvantage"].append("먼 사거리")
		if is_threatened(world, attacker):
			ctx["disadvantage"].append("근접 위협")
	return ctx


## 근접 위협: 인접 8칸에 나를 볼 수 있고 무력화되지 않은 적이 있다(3단계).
static func is_threatened(world: Dictionary, c: Node) -> bool:
	var grid: Node = world["grid"]
	for other: Node in grid.creatures():
		if other == c or other.dead or not other.is_hostile_to(c) or other.is_incapacitated():
			continue
		if grid.distance_between(c, other) <= 1 and grid.can_see(other, c):
			return true
	return false


## 공격 행동의 공격 한 번. 첫 공격이 행동을 쓰고, 추가 공격은 같은 행동의 남은 공격을 쓴다.
## opts: {"weapon": 무기 ID(기본 쥔 무기), "thrown", "two_handed", "cleave_target"}
static func attack(world: Dictionary, attacker: Node, target: Node, opts: Dictionary = {}) -> Dictionary:
	if int(attacker.turn.get("attacks_left", 0)) <= 0:
		if not spend(attacker, "action"):
			return _fail("행동이 없다")
		attacker.turn["attacks_left"] = attacker.attacks_per_action
	var wid: String = opts.get("weapon", attacker.weapon("main"))
	var atk := build_weapon_attack(attacker, wid, opts)
	var res := _do_attack(world, attacker, target, atk)
	if not res.get("ok", true):
		return res
	attacker.turn["attacks_left"] -= 1
	if "light" in atk["properties"]:
		attacker.turn["light_attack_done"] = true
	apply_mastery(world, attacker, target, atk, res, opts)
	return res


## 가벼운 무기 보조 공격(보너스 행동). 같은 턴 공격 행동에서 가벼운 무기로 공격했어야 한다.
## 다른 가벼운 무기로, 피해에 능력 수정치 없음. Nick 마스터리면 보너스 행동 대신 공격 행동의 일부(턴당 1회).
static func offhand_attack(world: Dictionary, attacker: Node, target: Node) -> Dictionary:
	var off: String = attacker.weapon("off")
	var w := weapon_data(off)
	if off == "" or not "light" in w.get("properties", []) or not "light" in weapon_data(attacker.weapon("main")).get("properties", []):
		return _fail("양손에 가벼운 무기가 필요하다")
	if not attacker.turn.get("light_attack_done", false):
		return _fail("이번 턴 공격 행동에서 가벼운 무기로 공격해야 한다")
	var nick: bool = w.get("mastery", "") == "nick" and attacker.weapon_masteries.has(off) and not attacker.turn.get("nick_used", false)
	if nick:
		attacker.turn["nick_used"] = true
	elif not spend(attacker, "bonus"):
		return _fail("보너스 행동이 없다")
	var atk := build_weapon_attack(attacker, off, {"hand": "off"})
	var res := _do_attack(world, attacker, target, atk)
	attacker.turn["light_attack_done"] = false
	apply_mastery(world, attacker, target, atk, res, {})
	return res


## 기회 공격(반응): 쥔 근접 무기로 근접 공격 1회.
static func opportunity_attack(world: Dictionary, attacker: Node, target: Node) -> Dictionary:
	if not spend(attacker, "reaction"):
		return _fail("반응이 없다")
	var atk := build_weapon_attack(attacker, attacker.weapon_sets.get("melee", {}).get("main", ""))
	atk["name"] = "기회 공격(%s)" % atk["name"]
	var res := _do_attack(world, attacker, target, atk, true)
	apply_mastery(world, attacker, target, atk, res, {})
	return res


static func _do_attack(world: Dictionary, attacker: Node, target: Node, atk: Dictionary, skip_range: bool = false) -> Dictionary:
	var ctx := attack_context(world, attacker, target, atk)
	if ctx.has("invalid") and not skip_range:
		return _fail(ctx["invalid"])
	var res := Resolver.attack(attacker, target, atk, ctx)
	res["ok"] = res["valid"]
	if not res["valid"]:
		res["reason"] = res.get("reason", "")
	return res


static func preview_attack(world: Dictionary, attacker: Node, target: Node, opts: Dictionary = {}) -> Dictionary:
	var atk := build_weapon_attack(attacker, opts.get("weapon", attacker.weapon("main")), opts)
	var ctx := attack_context(world, attacker, target, atk)
	if ctx.has("invalid"):
		return {"valid": false, "reason": ctx["invalid"]}
	return Resolver.preview_attack(attacker, target, atk, ctx)


# ======================================================================
# 무기 마스터리(SRD 5.2.1 Mastery Properties, 명중·빗나감마다 상시 — 룰북 6단계 결정 2)
# ======================================================================

static func apply_mastery(world: Dictionary, attacker: Node, target: Node, atk: Dictionary, res: Dictionary,
		opts: Dictionary) -> void:
	var m: String = atk.get("mastery", "")
	if m == "" or not res.get("valid", false):
		return
	var hit: bool = res.get("hit", false)
	var dealt: int = int(res.get("damage", {}).get("total", 0))
	match m:
		"cleave":
			if hit and atk["kind"] == "melee" and not attacker.turn.get("cleave_used", false):
				var second: Node = opts.get("cleave_target", _cleave_target(world, attacker, target))
				if second != null:
					attacker.turn["cleave_used"] = true
					var atk2 := build_weapon_attack(attacker, atk["weapon_id"], {"no_ability_damage": true})
					atk2["mastery"] = ""
					res["cleave"] = _do_attack(world, attacker, second, atk2)
		"graze":
			if not hit and atk.get("ability_mod", 0) > 0 and not target.dead:
				res["graze"] = Resolver.apply_damage(target, [{"amount": atk["ability_mod"],
					"damage_type": atk["damage"][0]["damage_type"]}])
		"push":
			if hit and not target.dead and world["grid"].size_of(target) <= 2:
				res["push"] = _push_up_to(world, attacker, target, 2)
		"sap":
			if hit and not target.dead:
				target.extra_modifiers.append({"effect": {"type": "advantage", "roll": "attack", "side": "self",
					"value": "disadvantage"}, "source": "sap", "consume_on_attack": true, "until_turn_start_of": attacker})
		"slow":
			if hit and dealt > 0 and not target.dead:
				for old in target.extra_modifiers.duplicate():
					if old.get("source") == "slow":
						target.extra_modifiers.erase(old)  # 여러 번 맞아도 10피트까지만
				target.extra_modifiers.append({"effect": {"type": "modify", "stat": "speed_tiles", "add": -2},
					"source": "slow", "until_turn_start_of": attacker})
		"topple":
			if hit and not target.dead:
				var dc: int = 8 + int(atk["ability_mod"]) + attacker.proficiency_bonus
				var s := Resolver.saving_throw(target, "con", dc, {"source": attacker})
				res["topple"] = s
				if not s["success"]:
					target.apply_condition("prone", -1, attacker)
		"vex":
			if hit and dealt > 0 and not target.dead:
				attacker.extra_modifiers.append({"effect": {"type": "advantage", "roll": "attack", "side": "self",
					"value": "advantage"}, "source": "vex", "consume_on_attack": true, "target_only": target,
					"turn_ends_left": 2})


static func _cleave_target(world: Dictionary, attacker: Node, first: Node) -> Node:
	var grid: Node = world["grid"]
	for other: Node in grid.creatures():
		if other == first or other == attacker or other.dead or not attacker.is_hostile_to(other):
			continue
		if grid.distance_between(first, other) <= 1 and grid.distance_between(attacker, other) <= reach_of(attacker):
			return other
	return null


## Push 마스터리: 공격자에게서 곧장 멀어지는 쪽으로 최대 N칸(가능한 만큼). 강제 이동이라 기회 공격 없음.
static func _push_up_to(world: Dictionary, from: Node, target: Node, n: int) -> int:
	var grid: Node = world["grid"]
	var a: Vector2i = grid.cell_of(from)
	var cur: Vector2i = grid.cell_of(target)
	var dir := Vector2i(signi(cur.x - a.x), signi(cur.y - a.y))
	var start := cur
	var moved := 0
	for i in n:
		var nxt := cur + dir
		if Physics._push_step_blocked(grid, target, cur, nxt) != "":
			break
		cur = nxt
		moved += 1
	if moved > 0:
		grid.move_creature(target, cur)
		var drop: int = grid.height(start) - grid.height(cur)
		if drop > 0:
			Physics.fall(target, drop)
	return moved


# ======================================================================
# 이동
# ======================================================================

## 이동: 경로를 따라 한 칸씩. 적의 도달을 벗어날 때 기회 공격 창을 연다(이탈하면 없음).
## 아군 칸은 지나갈 수 있지만 멈출 수 없다(SRD Moving Around Other Creatures).
## 결과: {"ok", "moved": 칸 수, "cost", "stopped": 이유}
static func move(world: Dictionary, c: Node, to: Vector2i) -> Dictionary:
	var grid: Node = world["grid"]
	var other: Node = grid.creature_at(to)
	if other != null and other != c:
		return _fail("다른 생물이 있는 칸에는 멈출 수 없다")
	var allies: Array = grid.creatures().filter(func(o: Node) -> bool: return o != c and not o.is_hostile_to(c))
	var p: Dictionary = grid.find_path(c, to, int(c.turn.get("movement", 0)), allies)
	if p.is_empty():
		return _fail("갈 수 없다(이동력 %d)" % int(c.turn.get("movement", 0)))
	var out := {"ok": true, "moved": 0, "cost": 0, "stopped": ""}
	var cur: Vector2i = grid.cell_of(c)
	for nxt: Vector2i in p["path"]:
		if not c.turn.get("disengaged", false):
			_opportunity_attacks(world, c, cur, nxt)
		if c.dead or c.is_down() or c.speed() == 0:
			out["stopped"] = "이동 중 쓰러지거나 멈춤"
			break
		var step: int = 0
		for fc in grid.footprint(nxt, grid.size_of(c)):
			step = maxi(step, grid.step_cost(fc - (nxt - cur), fc))
		c.turn["movement"] = int(c.turn["movement"]) - step
		out["cost"] += step
		grid.move_creature(c, nxt)
		out["moved"] += 1
		cur = nxt
	return out


## 이동 미리보기: 경로, 비용, 기회 공격이 일어날 칸(3단계 원칙 4).
static func preview_move(world: Dictionary, c: Node, to: Vector2i) -> Dictionary:
	var grid: Node = world["grid"]
	var allies: Array = grid.creatures().filter(func(o: Node) -> bool: return o != c and not o.is_hostile_to(c))
	var p: Dictionary = grid.find_path(c, to, int(c.turn.get("movement", c.speed())), allies)
	if p.is_empty():
		return {"valid": false}
	var oa: Array = []
	var cur: Vector2i = grid.cell_of(c)
	for nxt: Vector2i in p["path"]:
		for e in _provokers(world, c, cur, nxt):
			oa.append({"cell": cur, "by": e})
		cur = nxt
	return {"valid": true, "path": p["path"], "cost": p["cost"], "opportunity_attacks": oa}


## cur → nxt 걸음에서 도달을 벗어나는 적(볼 수 있고, 반응이 있고, 근접 세트를 든 적).
static func _provokers(world: Dictionary, mover: Node, cur: Vector2i, nxt: Vector2i) -> Array:
	var grid: Node = world["grid"]
	var out: Array = []
	var sz: int = grid.size_of(mover)
	for e: Node in grid.creatures():
		if e == mover or e.dead or not e.is_hostile_to(mover) or not e.can_react():
			continue
		if e.active_set != "melee" or is_ranged_weapon(weapon_data(e.weapon("main"))):
			continue  # 원거리 무기를 든 생물은 기회 공격 불가(3단계)
		var reach := reach_of(e)
		var before := _dist_cells(grid, grid.occupied_cells(e), grid.footprint(cur, sz))
		var after := _dist_cells(grid, grid.occupied_cells(e), grid.footprint(nxt, sz))
		if before <= reach and after > reach and grid.can_see(e, mover):
			out.append(e)
	return out


static func _dist_cells(grid: Node, a: Array, b: Array) -> int:
	var best := 1 << 30
	for x: Vector2i in a:
		for y: Vector2i in b:
			best = mini(best, grid.distance(x, y))
	return best


static func _opportunity_attacks(world: Dictionary, mover: Node, cur: Vector2i, nxt: Vector2i) -> void:
	var rq: Variant = world.get("reactions")
	var provokers := _provokers(world, mover, cur, nxt)
	# 반응 창이 여럿 열리면 이니셔티브 순으로 하나씩(8단계 우선순위 규칙 4).
	provokers.sort_custom(func(a: Node, b: Node) -> bool: return a.initiative > b.initiative)
	for e in provokers:
		if mover.dead or mover.is_down():
			return
		if rq != null:
			rq.offer(e, "opportunity_attack", {"target": mover},
				func() -> void: opportunity_attack(world, e, mover))
		elif e.reaction_setting("opportunity_attack") != "off":
			opportunity_attack(world, e, mover)


# ======================================================================
# 공통 행동
# ======================================================================

## 넘어짐에서 일어서기: 속도의 절반(내림) 소모. 속도가 0이면 못 일어선다(SRD Prone, 3단계).
static func stand_up(c: Node) -> Dictionary:
	if not c.has_condition("prone"):
		return _fail("넘어지지 않았다")
	var cost: int = c.speed() / 2
	if c.speed() == 0 or int(c.turn.get("movement", 0)) < cost:
		return _fail("이동력이 모자란다")
	c.turn["movement"] = int(c.turn["movement"]) - cost
	c.remove_condition("prone")
	return {"ok": true, "cost": cost}


static func dash(c: Node) -> Dictionary:
	if not spend(c, "action"):
		return _fail("행동이 없다")
	c.turn["movement"] = int(c.turn.get("movement", 0)) + c.speed()
	return {"ok": true}


static func disengage(c: Node) -> Dictionary:
	if not spend(c, "action"):
		return _fail("행동이 없다")
	c.turn["disengaged"] = true
	return {"ok": true}


## 돕기: 인접한 쓰러진 아군을 HP 1로 일으킨다(3단계, 7단계). 돕기의 다른 용도는 없다.
static func help(world: Dictionary, c: Node, ally: Node, range_tiles: int = 1) -> Dictionary:
	if not ally.is_down():
		return _fail("쓰러진 아군에게만")
	if world["grid"].distance_between(c, ally) > range_tiles:
		return _fail("너무 멀다")
	if not spend(c, "action"):
		return _fail("행동이 없다")
	Resolver.heal(ally, 1, c)
	return {"ok": true}


## 숨기: 적 누구의 시야에도 없을 때만 민첩(은신) DC 15. 성공하면 숨은 상태(투명, source "hide").
## 전투 중 비용은 행동(로그류 기능은 보너스 행동 — 6단계). 탐험 중 은신은 5단계.
static func hide(world: Dictionary, c: Node, cost: String = "action") -> Dictionary:
	var grid: Node = world["grid"]
	for e: Node in grid.creatures():
		if e != c and not e.dead and e.is_hostile_to(c) and grid.can_see(e, c):
			return _fail("적이 보고 있다(9단계 충돌 B)")
	if not spend(c, cost):
		return _fail("비용이 없다")
	var r := Resolver.ability_check(c, "dex", 15, {"skill": "stealth"})
	if r["success"]:
		c.apply_condition("invisible", -1, "hide", {"stealth_total": r["total"]})
	return {"ok": true, "success": r["success"], "check": r}


## 밀치기(보너스 행동, 인접 대상).
static func shove(world: Dictionary, c: Node, target: Node) -> Dictionary:
	var grid: Node = world["grid"]
	if grid.distance_between(c, target) > 1:
		return _fail("인접한 대상만")
	var plan := Physics.plan_shove(grid, c, target)
	if not plan["valid"]:
		return _fail(plan["reason"])  # 미리보기가 막는다 — 비용을 쓰지 않는다
	if not spend(c, "bonus"):
		return _fail("보너스 행동이 없다")
	var r := Physics.shove(grid, c, target, not c.is_hostile_to(target))
	r["ok"] = true
	return r


## 점프(보너스 행동 + 이동 2칸): 거리 3칸 + 근력 수정치 2당 1칸. 기회 공격 없음.
## 착지가 2단계 이상 낮으면 낙하 피해. 1단계보다 높은 곳으로는 못 뛴다.
static func jump(world: Dictionary, c: Node, to: Vector2i) -> Dictionary:
	var grid: Node = world["grid"]
	var from: Vector2i = grid.cell_of(c)
	var reach := jump_distance(c)
	if grid.distance(from, to) > reach:
		return _fail("너무 멀다(%d칸)" % reach)
	if grid.blocks_movement(to) or (grid.creature_at(to) != null and grid.creature_at(to) != c):
		return _fail("착지할 수 없다")
	if grid.height(to) - grid.height(from) > 1:
		return _fail("너무 높다")
	if int(c.turn.get("movement", 0)) < 2:
		return _fail("이동력이 모자란다")
	if not spend(c, "bonus"):
		return _fail("보너스 행동이 없다")
	c.turn["movement"] = int(c.turn["movement"]) - 2
	grid.move_creature(c, to)
	var drop: int = grid.height(from) - grid.height(to)
	var out := {"ok": true}
	if drop >= 2:
		out["fall"] = Physics.fall(c, drop)
	return out


static func jump_distance(c: Node) -> int:
	return 3 + maxi(c.ability_mod("str"), 0) / 2


## 던지기(행동): 즉석 무기 공격(근력, 숙련 없음 — SRD Improvised Weapons). 맞으면 무게 피해.
static func throw_object(world: Dictionary, c: Node, target: Node, weight_kg: float, range_tiles: int = 6) -> Dictionary:
	if weight_kg > Physics.max_throw_kg(c):
		return _fail("너무 무겁다")
	var grid: Node = world["grid"]
	if grid.distance_between(c, target) > grid.effective_range(c, grid.cell_of(target), range_tiles):
		return _fail("사거리 밖")
	if not spend(c, "action"):
		return _fail("행동이 없다")
	var atk := {"name": "던지기", "bonus": c.ability_mod("str"), "kind": "ranged", "weapon": false, "damage": []}
	var ctx: Dictionary = grid.attack_context(c, target)
	if is_threatened(world, c):
		ctx["disadvantage"].append("근접 위협")
	var res := Resolver.attack(c, target, atk, ctx)
	if res["hit"]:
		res["throw"] = Physics.throw_hit(grid, c, target, weight_kg)
	res["ok"] = true
	return res


## 물약 마시기(보너스 행동) / 먹이기(행동, 인접 아군).
static func drink_potion(c: Node, effects: Array, target: Node = null, world: Dictionary = {}) -> Dictionary:
	var who: Node = c if target == null else target
	if who != c and world.get("grid") != null and world["grid"].distance_between(c, who) > 1:
		return _fail("인접한 대상만")
	if not spend(c, "bonus" if who == c else "action"):
		return _fail("비용이 없다")
	for e: Dictionary in effects:
		if e["type"] == "heal":
			Resolver.heal(who, Dice.roll(e["dice"], "물약")["total"])
	return {"ok": true}


## 담그기(보너스 행동): 서 있거나 인접한 칸의 화염·독 표면에 무기를 담가 무기 담금 상태(4단계).
static func dip(world: Dictionary, c: Node) -> Dictionary:
	var grid: Node = world["grid"]
	var kind := ""
	var center: Vector2i = grid.cell_of(c)
	for cell in Area.circle(null, center, 1):
		var sid: String = grid.surface_id(cell)
		var coats: String = RulesDB.get_entry("surface", sid).get("coats", "") if sid != "" else ""
		if sid == "fire":
			coats = "fire"
		if coats != "":
			kind = coats
			break
	if kind == "":
		return _fail("담글 표면이 없다")
	if not spend(c, "bonus"):
		return _fail("보너스 행동이 없다")
	c.apply_condition("coated_weapon", 0, null, {"damage_type": kind})
	return {"ok": true, "damage_type": kind}


## 무기 세트 전환(무료).
static func switch_weapon_set(c: Node) -> void:
	c.active_set = "ranged" if c.active_set == "melee" else "melee"


## 단순 상호작용: 턴당 1회 무료, 그다음부터 행동(3단계).
static func interact(c: Node) -> Dictionary:
	if int(c.turn.get("interaction", 0)) > 0:
		c.turn["interaction"] -= 1
		return {"ok": true, "cost": "free"}
	if spend(c, "action"):
		return {"ok": true, "cost": "action"}
	return _fail("행동이 없다")
