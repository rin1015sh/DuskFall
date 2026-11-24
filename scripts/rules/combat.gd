extends RefCounted
## 전투 행동(상태 없음). 룰북 3단계 '턴 자원', '행동 목록', 기회 공격·근접 위협, 6단계 무기 마스터리.
## 행동 비용을 확인·소모하고 Resolver·Physics·GridWorld를 불러 결과를 낸다.
## 모든 함수는 첫 인자로 world를 받는다: {"grid", "surfaces", "reactions"(ReactionQueue, 없으면 null)}

const Resolver := preload("res://scripts/rules/resolver.gd")
const DiceExpr := preload("res://scripts/rules/dice_expr.gd")
const Physics := preload("res://scripts/rules/physics.gd")
const Area := preload("res://scripts/rules/area.gd")

## 비무장 공격(SRD Unarmed Strike: 1 + 근력 수정치 타격).
const UNARMED := {"id": "unarmed", "damage": "1", "damage_type": "bludgeoning", "properties": [],
	"category": "simple_melee"}


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

## 무기 데이터. 마법 무기(items.json "base" + "bonus")면 바탕 무기에 magic_bonus·item_id·이름을 얹는다.
static func weapon_data(id: String) -> Dictionary:
	if id == "" or id == "unarmed":
		return UNARMED
	if RulesDB.has_entry("weapon", id):
		return RulesDB.get_entry("weapon", id)
	var item := RulesDB.get_entry("item", id)
	if item.has("base") and RulesDB.has_entry("weapon", str(item["base"])):
		var w: Dictionary = RulesDB.get_entry("weapon", str(item["base"])).duplicate(true)
		w["magic_bonus"] = int(item.get("bonus", 0))
		w["item_id"] = id
		w["name"] = item["name"]
		return w
	return {}


## 몽크 무기: 비무장, 단순 근접, 가벼운 군용 근접.
static func is_monk_weapon(w: Dictionary) -> bool:
	var cat := str(w.get("category", ""))
	return str(w.get("id", "")) == "unarmed" or cat == "simple_melee" or (cat == "martial_melee" and "light" in w.get("properties", []))


## 능력 태그 martial_arts(몽크 무술): 갑옷·방패 없이 몽크 무기를 쓸 때.
static func martial_arts_applies(c: Node, w: Dictionary) -> bool:
	return c.has_cap("martial_arts") and is_monk_weapon(w) and str(c.get_meta("armor", "")) == "" and not bool(c.get_meta("shield", false))


## 무술 주사위(기능 martial_arts의 dice_by_level).
static func martial_arts_die(c: Node) -> String:
	var table: Dictionary = c.feature_data.get("martial_arts", {}).get("dice_by_level", {"1": "1d6"})
	var best := "1d6"
	var best_lv := 0
	for k: String in table:
		if c.feature_level("martial_arts") >= int(k) and int(k) >= best_lv:
			best_lv = int(k)
			best = str(table[k])
	return best


static func is_ranged_weapon(w: Dictionary) -> bool:
	return str(w.get("category", "")).ends_with("ranged")


## 무기의 도달(칸): 기본 1, 리치 무기 2(3단계 기회 공격). 몬스터는 근접 행동의 도달.
static func reach_of(c: Node) -> int:
	if c.has_meta("monster"):
		return maxi(preload("res://scripts/rules/monster_factory.gd").melee_reach(c), 1)
	var w := weapon_data(c.weapon_sets.get("melee", {}).get("main", ""))
	return 2 if "reach" in w.get("properties", []) else 1


## 장병기 달인(재주)이 쓰는 무기(BG3: 글레이브·핼버드·파이크·쿼터스태프·창)
const POLEARMS := ["glaive", "halberd", "pike", "quarterstaff", "spear"]


## 무기 공격 정의(Resolver.attack용)를 만든다. opts: {"hand": "main"|"off", "thrown": bool}
## 능력: 원거리 무기는 민첩, 교묘(finesse)는 근력·민첩 중 큰 쪽, 나머지는 근력.
## 보조 공격(off)은 피해에 능력 수정치를 더하지 않는다(음수면 더함, Two-Weapon Fighting이면 더함).
static func build_weapon_attack(c: Node, weapon_id: String, opts: Dictionary = {}) -> Dictionary:
	var w := weapon_data(weapon_id)
	var props: Array = w.get("properties", [])
	var ranged: bool = is_ranged_weapon(w) or opts.get("thrown", false)
	var ability := "dex" if is_ranged_weapon(w) else "str"
	var martial := martial_arts_applies(c, w)
	if ("finesse" in props or martial) and c.ability_mod("dex") > c.ability_mod("str"):
		ability = "dex"  # 교묘 무기, 몽크 무술(민첩 공격)
	if c.has_cap("pact_blade") and not is_ranged_weapon(w) and w["id"] != "unarmed" and c.ability_mod("cha") > c.ability_mod(ability):
		ability = "cha"  # 계약의 칼날(워락): 근접 무기에 매력
	var hexed: bool = c.has_meta("hexed_weapon") and str(c.get_meta("hexed_weapon")) == str(w["id"])
	if hexed and c.ability_mod("cha") > c.ability_mod(ability):
		ability = "cha"  # 저주 무기 결속(주술검사, BG3): 결속한 무기에 매력
	var shil: Dictionary = c.get_meta("shillelagh", {}) if c.has_meta("shillelagh") else {}
	var shillelagh: bool = not shil.is_empty() and str(shil.get("weapon", "")) == str(w["id"])
	if shillelagh:
		ability = str(shil.get("ability", "wis"))  # 마법 곤봉(BG3): 시전 능력으로 명중·피해, 1d8, 마법
	var mod: int = c.ability_mod(ability)
	var proficient: bool = w["id"] == "unarmed" or hexed or c.weapon_proficiencies.has(w["id"]) \
		or c.weapon_proficiencies.has(str(w.get("category", "")).get_slice("_", 0))
	var dice: String = "1d8" if shillelagh else w["damage"]
	if w.get("conjured", false) and c.has_meta("conjured_weapon_dice"):
		dice = str(c.get_meta("conjured_weapon_dice"))  # 불러낸 무기(불꽃·그늘 칼날): 슬롯에 따른 주사위
	var free_off: bool = c.weapon("off") == "" and not bool(c.get_meta("shield", false))
	if "versatile" in props and not ranged and not shillelagh and (opts.get("two_handed", false) or free_off):
		dice = w["versatile_damage"]  # 다용도 무기: 보조 손이 비면 두 손으로(BG3식 자동, SRD Versatile)
	var martial_die := ""
	if martial:
		martial_die = martial_arts_die(c)
		if w["id"] != "unarmed" and DiceExpr.stats(martial_die).get("avg", 0.0) > DiceExpr.stats(dice).get("avg", 0.0):
			dice = martial_die  # 무술 주사위가 크면 바꿔 굴린다
	var dmg_mod := mod
	if opts.get("hand", "main") == "off" and mod > 0 and not c.has_cap("two_weapon_fighting"):
		dmg_mod = 0
	if opts.get("no_ability_damage", false) and mod > 0:
		dmg_mod = 0
	var dmg_bonus := int(w.get("magic_bonus", 0))  # 마법 무기 +N(명중·피해)
	for m in c.modifier_entries():
		var me: Dictionary = m["effect"]
		if me["type"] == "modify" and me["stat"] == "weapon_attack_and_damage":
			dmg_bonus += int(me.get("add", 0))  # Magic Weapon +1(명중·피해)
	var str_bonus := 0
	if not ranged or opts.get("thrown", false):
		str_bonus = Resolver.rage_bonus(c)  # 분노(BG3): 근접 무기·비무장·던지기 피해 +2(민첩 무기도)
	if c.has_cap("dueling") and not ranged and w["id"] != "unarmed" and not "two_handed" in props and opts.get("hand", "main") == "main" \
			and c.weapon("off") == "" and not opts.get("two_handed", false) and dice != str(w.get("versatile_damage", "")):
		str_bonus += 2  # 결투(전투 방식): 한 손 근접 무기만 쥐면 피해 +2(피해만 — str_bonus는 피해에만 더한다)
	var brawl := 0
	if c.has_cap("brawler") and (w["id"] == "unarmed" or opts.get("thrown", false)):
		brawl = c.ability_mod("str")  # 주먹다짐: 맨손·투척에 근력 수정치를 한 번 더(명중·피해)
		dmg_bonus += brawl
	var expr := dice if dmg_mod + dmg_bonus + str_bonus == 0 else "%s%+d" % [dice, dmg_mod + dmg_bonus + str_bonus]
	if w["id"] == "unarmed":
		expr = str(maxi(1 + mod + str_bonus + dmg_bonus, 0))  # 비무장 1 + 근력(+분노 — BG3)
		if martial_die != "":
			expr = martial_die if mod + str_bonus == 0 else "%s%+d" % [martial_die, mod + str_bonus]  # 무술: 비무장 공격 = 무술 주사위 + 수정치
	var hit_bonus := dmg_bonus
	if w["id"] == "unarmed" and brawl != 0:
		expr = str(maxi(1 + mod + str_bonus + dmg_bonus, 0)) if martial_die == "" else "%s%+d" % [martial_die, mod + str_bonus + brawl]
	for m in c.modifier_entries():
		if m["effect"]["type"] == "modify" and m["effect"]["stat"] == "weapon_attack":
			hit_bonus += int(m["effect"].get("add", 0))  # 신성한 무기: 명중만
	if ranged and is_ranged_weapon(w) and c.has_cap("ranged_weapon_attack_bonus"):
		hit_bonus += 2  # 궁술: 원거리 무기 명중 +2
	# 대형 무기 강타·저격수(BG3 재주, 설정 켬): 숙련 무기 명중 −5, 피해 +10(따로 더하는 고정 피해 — 휩쓸기 절반에도 그대로)
	var flat := 0
	var two_hand_grip: bool = "two_handed" in props or ("versatile" in props and dice == str(w.get("versatile_damage", "")))
	if proficient and w["id"] != "unarmed" and not ranged and two_hand_grip and c.has_cap("gwm_all_in") and str(c.options.get("great_weapon_master", "off")) == "on":
		hit_bonus -= 5
		flat = 10
	if proficient and ranged and is_ranged_weapon(w) and c.has_cap("ss_all_in") and str(c.options.get("sharpshooter", "off")) == "on":
		hit_bonus -= 5
		flat = 10
	var dis: Array = []
	if "heavy" in props and ((not ranged and c.abilities["str"] < 13) or (ranged and c.abilities["dex"] < 13)):
		dis.append("무거운 무기")
	var extra_adv: Array = []
	for r: Dictionary in c.attack_riders:
		if r.get("when", "") == "always" and r.has("expr_add"):
			expr += r["expr_add"]  # Enlarge(+1d4)·Reduce(−1d4)
		if r.get("when", "") == "advantage":
			extra_adv.append({"dice": r["dice"], "damage_type": r.get("damage_type", w["damage_type"])})
	return {"martial": martial, "name": w.get("name", {}).get("en", w["id"]) if w.has("name") else w["id"], "weapon_id": w["id"],
		"extra_if_advantage": extra_adv,
		"bonus": mod + (c.proficiency_bonus if proficient else 0) + hit_bonus, "ability": ability, "ability_mod": mod,
		"two_handed": opts.get("two_handed", false) or "two_handed" in props,
		"kind": "ranged" if ranged else "melee", "weapon": true, "properties": props,
		"damage": [{"dice": expr, "damage_type": w["damage_type"]}],
		"extra_disadvantage": dis, "flat_damage": flat,
		"magical": shillelagh or bool(w.get("conjured", false)) or (ranged and c.has_cap("magic_ranged")) or (w["id"] == "unarmed" and c.has_cap("empowered_strikes")),  # 기 강화 타격(BG3): 비무장이 마법 공격
		"range_tiles": w.get("range_tiles", [reach_of(c), reach_of(c)]) if ranged else [1, 1]}


## 공격 상황: 격자 ctx + 사거리(먼 사거리 불리) + 근접 위협(원거리 공격 불리) + 무거운 무기.
## 사거리 밖이면 {"invalid": 이유}.
static func attack_context(world: Dictionary, attacker: Node, target: Node, atk: Dictionary) -> Dictionary:
	var grid: Node = world["grid"]
	var ctx: Dictionary = grid.attack_context(attacker, target)
	ctx["disadvantage"].append_array(atk.get("extra_disadvantage", []))
	ctx["advantage"].append_array(atk.get("advantage_add", []))
	var dist: int = ctx["distance_tiles"]
	# 무리 전술: 대상 1칸 안에 무력화되지 않은 공격자의 아군이 있으면 유리(SRD)
	if attacker.has_cap("pack_tactics"):
		for o: Node in grid.creatures():
			if o != attacker and o != target and not o.dead and o.team == attacker.team and not o.is_incapacitated() \
					and grid.distance_between(o, target) <= 1:
				ctx["advantage"].append("무리 전술")
				break
	# 햇빛 민감: 햇빛(맵 sunlight 표시가 있는 밝은 칸)에서 공격 불리
	if attacker.has_cap("sunlight_sensitivity") and grid.has_meta("sunlight") \
			and grid.light_at(grid.cell_of(attacker)) == grid.Light.BRIGHT:
		ctx["disadvantage"].append("햇빛 민감")
	load("res://scripts/rules/primal.gd").attack_context(world, attacker, target, atk, ctx)
	if atk["kind"] == "melee":
		var reach := int(atk.get("reach_tiles", 2 if "reach" in atk.get("properties", []) else 1))
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
		if is_threatened(world, attacker) and not (attacker.has_cap("crossbow_point_blank") and "crossbow" in str(atk.get("weapon_id", ""))):
			ctx["disadvantage"].append("근접 위협")  # 석궁 명수: 석궁은 근접 위협 불리 없음
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
		var apa: int = attacker.attacks_per_action
		if attacker.has_meta("beast_form"):
			apa = maxi(apa, 3 if attacker.has_cap("improved_wild_strike") else (2 if attacker.has_cap("wild_strike") else 1))  # 야생의 일격(BG3 드루이드 5·10)
		attacker.turn["attacks_left"] = apa + (1 if attacker.turn.get("dread_ambush", false) else 0)
	if attacker.has_meta("beast_form") and not opts.has("weapon"):
		return _beast_attack(world, attacker, target)
	var wid: String = opts.get("weapon", attacker.weapon("main"))
	if attacker.has_flag("disarmed"):
		wid = "unarmed"  # 무기 놓침(무기 액션 무기 쳐내기): 맨손으로만
	var atk := build_weapon_attack(attacker, wid, opts)
	var res := _do_attack(world, attacker, target, atk)
	if not res.get("ok", true):
		return res
	attacker.turn["attacks_left"] -= 1
	attacker.turn["attacks_made"] = int(attacker.turn.get("attacks_made", 0)) + 1  # 무모한 공격: 첫 공격 전에만
	if not attacker.turn.get("war_priest_used", false):
		attacker.turn["weapon_attacked"] = true  # 전쟁 사제: 공격 행동으로 무기 공격한 턴
	if atk["kind"] == "melee" and attacker.has_cap("polearm_haft") and str(atk.get("weapon_id", "")) in POLEARMS and not attacker.turn.get("haft_used", false):
		attacker.turn["haft_ready"] = true  # 장병기 달인: 이번 턴 자루 공격(보너스 행동)
	if atk["kind"] == "melee":
		var mt: Array = attacker.turn.get("melee_targets", [])
		mt.append(target)
		attacker.turn["melee_targets"] = mt  # 날랜 발(기회 공격 회피)
	if "light" in atk["properties"] or (attacker.has_cap("dual_wield_any") and atk["kind"] == "melee" and not "two_handed" in atk["properties"]):
		attacker.turn["light_attack_done"] = true
	_after_attack_features(world, attacker, target, res)
	if not opts.get("horde_breaker", false):
		_horde_breaker(world, attacker, target, wid, opts)
	if world.get("turns") != null:
		world["turns"].notify_hostile_action(attacker)
	return res


## 모험 장비 던지기(SRD 산·연금술사의 불·성수·기름): 공격 행동의 공격 하나를 쓴다(첫 번째면 행동).
## 사거리는 BG3 던지기 거리(근력·무게, 최대 12칸) 안 보이는 칸.
## 생물이면 민첩 내성(DC 8 + 민첩 + 숙련) 실패 시 fail 효과(creature_types가 있으면 그 종류만), surface가 있으면 그 칸에 표면.
## 아이템(투척 소모품·물약) 던지기 사거리: BG3 던지기 거리(아이템 무게, 없으면 0.5kg).
static func gear_throw_range(c: Node, item: Dictionary) -> int:
	return Physics.throw_range_tiles(c, float(item.get("weight_kg", 0.5)))


static func throw_gear(world: Dictionary, c: Node, item_id: String, cell: Vector2i) -> Dictionary:
	var item := RulesDB.get_entry("item", item_id)
	var th: Dictionary = item.get("use", {}).get("throw", {})
	if th.is_empty() or int(c.inventory.get(item_id, 0)) <= 0:
		return _fail("던질 것이 없다")
	var grid: Node = world["grid"]
	if grid.distance(grid.cell_of(c), cell) > gear_throw_range(c, item) or not grid.has_line_of_sight(grid.cell_of(c), cell):
		return _fail("던질 수 있는 거리 안 보이는 곳만")
	if int(c.turn.get("attacks_left", 0)) <= 0:
		if not spend(c, "action"):
			return _fail("행동이 없다")
		c.turn["attacks_left"] = c.attacks_per_action
	c.turn["attacks_left"] -= 1
	c.inventory[item_id] = int(c.inventory[item_id]) - 1
	if int(c.inventory[item_id]) <= 0:
		c.inventory.erase(item_id)
	var t: Node = grid.creature_at(cell)
	var out := {"ok": true}
	if t != null and th.has("fail") and (not th.has("creature_types") or str(t.creature_type) in th["creature_types"]):
		var dc: int = 8 + c.ability_mod("dex") + c.proficiency_bonus
		out["result"] = Resolver.save_effect([t], {"ability": str(th.get("save", "dex")), "dc": dc}, th["fail"], [], {"source": c, "attacker": c})
	if th.has("surface") and world.has("surfaces"):
		world["surfaces"].place_surface([cell], str(th["surface"]), {"source": c})
	Dice.log_text("%s: %s 던지기" % [c.label(), item["name"]["ko"]])
	if world.get("turns") != null and t != null and c.is_hostile_to(t):
		world["turns"].notify_hostile_action(c)
	return out


## 모험 장비 뿌리기(SRD 마름쇠·쇠구슬): 행동. range_tiles 안 칸을 모서리로 size×size 칸에 표면(내성 DC = dc).
static func spread_gear(world: Dictionary, c: Node, item_id: String, cell: Vector2i) -> Dictionary:
	var item := RulesDB.get_entry("item", item_id)
	var sp: Dictionary = item.get("use", {}).get("spread", {})
	if sp.is_empty() or int(c.inventory.get(item_id, 0)) <= 0:
		return _fail("뿌릴 것이 없다")
	var grid: Node = world["grid"]
	if grid.distance(grid.cell_of(c), cell) > int(sp.get("range_tiles", 1)):
		return _fail("너무 멀다")
	if not spend(c, "action"):
		return _fail("행동이 없다")
	c.inventory[item_id] = int(c.inventory[item_id]) - 1
	if int(c.inventory[item_id]) <= 0:
		c.inventory.erase(item_id)
	var cells: Array = []
	var n := int(sp.get("size", 1))
	for dy in n:
		for dx in n:
			var cc := cell + Vector2i(dx, dy)
			if grid.in_bounds(cc) and not grid.blocks_movement(cc):
				cells.append(cc)
	world["surfaces"].place_surface(cells, str(sp["surface"]), {"source": c, "dc": int(sp.get("dc", 10))})
	Dice.log_text("%s: %s 뿌리기" % [c.label(), item["name"]["ko"]])
	return {"ok": true, "cells": cells}


## 야생 변신 중 공격: 짐승의 첫 근접 공격(명중 보너스·피해·맞으면 효과는 몬스터 데이터 그대로).
static func _beast_attack(world: Dictionary, attacker: Node, target: Node) -> Dictionary:
	var m := RulesDB.get_entry("monster", str(attacker.get_meta("beast_form")))
	var a: Dictionary = {}
	for x: Dictionary in m.get("actions", []):
		if x.get("type", "") == "attack":
			a = x
			break
	if a.is_empty():
		return _fail("짐승 공격이 없다")
	var batk: Dictionary = preload("res://scripts/rules/monster_factory.gd").to_attack(a, "melee")
	var wsf: Dictionary = attacker.feature_data.get("wild_shape", {})
	var bonus_die := ""
	for k: String in wsf.get("form_bonus_dice", {}):
		if attacker.feature_level("wild_shape") >= int(k):
			bonus_die = str(wsf["form_bonus_dice"][k]) if bonus_die == "" or int(k) >= 8 else bonus_die
	if bonus_die != "":
		batk["damage"] = batk["damage"] + [{"dice": bonus_die, "damage_type": batk["damage"][0]["damage_type"]}]  # 형태 피해 증가(BG3 — 4레벨 1d6, 8레벨 1d8)
	if attacker.has_cap("primal_strike"):
		batk["magical"] = true  # 원초의 일격(달 회합): 짐승 공격은 마법 공격
	var res := _do_attack(world, attacker, target, batk)
	if not res.get("ok", true):
		return res
	attacker.turn["attacks_left"] -= 1
	attacker.turn["attacks_made"] = int(attacker.turn.get("attacks_made", 0)) + 1
	_monster_on_hit(world, attacker, target, a, res)
	if world.get("turns") != null:
		world["turns"].notify_hostile_action(attacker)
	return res


## 무리 파괴자(능력 태그 horde_breaker): 턴당 1회 무기 공격 뒤, 원래 대상 1칸 안의 다른 적(이번 턴에 공격하지 않은)에게
## 같은 무기로 공격 하나 더 — 자동(사용자 결정: 단순화). 공격 횟수·행동을 쓰지 않는다.
static func _horde_breaker(world: Dictionary, attacker: Node, target: Node, wid: String, opts: Dictionary) -> void:
	if not attacker.has_cap("horde_breaker") or attacker.turn.get("horde_used", false) or attacker.dead:
		return
	var grid: Node = world["grid"]
	var attacked: Array = attacker.turn.get("attacked", [])
	attacked.append(target)
	attacker.turn["attacked"] = attacked
	var reach := reach_of(attacker) if not is_ranged_weapon(weapon_data(wid)) else 99
	for o: Node in grid.creatures():
		if o == target or o.dead or not attacker.is_hostile_to(o) or o in attacked:
			continue
		if grid.distance_between(o, target) <= 1 and grid.distance_between(attacker, o) <= reach and grid.can_see(attacker, o):
			attacker.turn["horde_used"] = true
			var o2 := opts.duplicate()
			o2["horde_breaker"] = true
			o2["weapon"] = wid
			attacker.turn["attacks_left"] = int(attacker.turn.get("attacks_left", 0)) + 1  # 추가 공격은 남은 공격을 쓰지 않는다
			Dice.log_text("%s 무리 파괴자" % attacker.label())
			attack(world, attacker, o, o2)
			return


## 공격 뒤 기능: 교활한 일격(급소 공격이 정해 둔 효과).
static func _after_attack_features(world: Dictionary, attacker: Node, target: Node, res: Dictionary) -> void:
	var Features := preload("res://scripts/rules/features.gd")
	for k: String in ["cunning_strike", "cunning_strike_2"]:  # 향상된 교활한 일격(로그 11레벨): 효과 둘
		if str(res.get(k, "")) != "":
			Features.run("cunning_strike", {"world": world, "self": attacker, "target": target, "res": res,
				"opts": {"option": res[k]}})


## 물체 공격(4단계 물체 AC·HP): 쥔 무기 세트로 칸의 물체를 친다. 맞으면 무기 피해를 칸 피해로(재질 반응·파괴·내용물).
static func attack_object(world: Dictionary, attacker: Node, cell: Vector2i, opts: Dictionary = {}) -> Dictionary:
	var grid: Node = world["grid"]
	var obj: Dictionary = grid.object_at(cell)
	if obj.is_empty():
		return _fail("물체가 없다")
	var wid: String = opts.get("weapon", attacker.weapon("main"))
	var atk := build_weapon_attack(attacker, wid, opts)
	var reach: int = atk["range_tiles"][1] if atk["kind"] == "ranged" else reach_of(attacker)
	if grid.distance(grid.cell_of(attacker), cell) > reach:
		return _fail("닿지 않는다")
	if int(attacker.turn.get("attacks_left", 0)) <= 0:
		if not spend(attacker, "action"):
			return _fail("행동이 없다")
		attacker.turn["attacks_left"] = attacker.attacks_per_action
	attacker.turn["attacks_left"] -= 1
	var d := Dice.d20(0, "%s → 물체" % attacker.label())
	var total: int = d["natural"] + int(atk["bonus"])
	var hit: bool = d["natural"] == 20 or (d["natural"] != 1 and total >= int(obj.get("ac", 10)))
	Dice.log_text("%s → %s: %d vs AC %d → %s" % [attacker.label(), obj.get("id", "물체"), total, int(obj.get("ac", 10)), "명중" if hit else "빗나감"])
	if hit and world.get("surfaces") != null:
		var dmg: int = Dice.roll(atk["damage"][0]["dice"], "물체 피해")["total"]
		world["surfaces"].tile_damage([cell], atk["damage"][0]["damage_type"], maxi(dmg, 1), attacker)
	if world.get("turns") != null:
		world["turns"].notify_hostile_action(attacker)
	return {"ok": true, "hit": hit}


## 가벼운 무기 보조 공격(보너스 행동). 같은 턴 공격 행동에서 가벼운 무기로 공격했어야 한다.
## 다른 가벼운 무기로, 피해에 능력 수정치 없음.
static func offhand_attack(world: Dictionary, attacker: Node, target: Node) -> Dictionary:
	var off: String = attacker.weapon("off")
	var w := weapon_data(off)
	var heavy_ok: bool = attacker.has_cap("dual_wield_any") and not "two_handed" in w.get("properties", []) \
		and not "two_handed" in weapon_data(attacker.weapon("main")).get("properties", [])  # 양손 무기술: 가볍지 않은 한 손 무기도
	if off == "" or not heavy_ok and (not "light" in w.get("properties", []) or not "light" in weapon_data(attacker.weapon("main")).get("properties", [])):
		return _fail("양손에 가벼운 무기가 필요하다")
	if not attacker.turn.get("light_attack_done", false):
		return _fail("이번 턴 공격 행동에서 가벼운 무기로 공격해야 한다")
	if not spend(attacker, "bonus"):
		return _fail("보너스 행동이 없다")
	var atk := build_weapon_attack(attacker, off, {"hand": "off"})
	var res := _do_attack(world, attacker, target, atk)
	attacker.turn["light_attack_done"] = false
	return res


## 기회 공격(반응): 쥔 근접 무기로 근접 공격 1회.
static func opportunity_attack(world: Dictionary, attacker: Node, target: Node) -> Dictionary:
	if not spend(attacker, "reaction"):
		return _fail("반응이 없다")
	if attacker.has_meta("monster"):
		var MF := preload("res://scripts/rules/monster_factory.gd")
		for a: Dictionary in MF.actions(attacker):
			if a["type"] == "attack" and a.get("kind", "melee") in ["melee", "both"]:
				var matk := MF.to_attack(a, "melee")
				matk["name"] = "기회 공격(%s)" % matk["name"]
				matk["opportunity"] = true
				var mres := _do_attack(world, attacker, target, matk, true)
				_monster_on_hit(world, attacker, target, a, mres)
				return mres
	if attacker.has_cap("war_caster_oa") and str(attacker.options.get("war_caster", "off")) == "on":
		# 전투 시전자: 기회 공격 대신 전격 손길(내 시전 능력, 모르는 주문이어도)
		return load("res://scripts/rules/spellcasting.gd").cast(world, attacker, "shocking_grasp", world["grid"].cell_of(target), {"free": true, "granted": true})
	var atk := build_weapon_attack(attacker, attacker.weapon_sets.get("melee", {}).get("main", ""))
	atk["name"] = "기회 공격(%s)" % atk["name"]
	atk["opportunity"] = true
	if attacker.has_cap("sentinel_oa"):
		atk["advantage_add"] = ["파수"]  # 파수: 기회 공격 유리
	var r := _do_attack(world, attacker, target, atk, true)
	if r.get("hit", false) and attacker.has_cap("relentless_avenger"):
		attacker.apply_condition("relentless_avenger", 1, attacker)  # 끈질긴 복수자(복수의 맹세 7레벨, BG3): 다음 턴 이동 +3칸
	if r.get("hit", false) and attacker.has_cap("sentinel_oa") and not target.dead:
		target.turn["movement"] = 0
		target.turn["free_move_no_oa"] = 0
		target.set_meta("sentinel_stopped", true)  # 파수: 이번 턴 더 움직이지 못한다(move가 멈춘다)
	return r


static func _do_attack(world: Dictionary, attacker: Node, target: Node, atk: Dictionary, skip_range: bool = false) -> Dictionary:
	if attacker.has_condition("raging") and attacker.is_hostile_to(target):
		attacker.turn["rage_kept"] = true  # 분노 연장: 적을 공격했다
	if attacker.is_hostile_to(target):
		for m in attacker.extra_modifiers.duplicate():
			if str(m.get("source", "")) == "tranquillity":
				attacker.extra_modifiers.erase(m)
	var ctx := attack_context(world, attacker, target, atk)
	if ctx.has("invalid") and not skip_range:
		return _fail(ctx["invalid"])
	var res := Resolver.attack(attacker, target, atk, ctx)
	res["ok"] = res["valid"]
	if not res["valid"]:
		res["reason"] = res.get("reason", "")
	else:
		if not attacker.has_meta("monster"):
			load("res://scripts/rules/actions.gd").follow_through(attacker, target, atk, res)  # 끈기(무기 액션 반응)
		var rq: Variant = world.get("reactions")
		if rq != null and not atk.get("opportunity", false) and not str(atk.get("name", "")).begins_with("파수"):
			rq.after_attack(res)  # 파수(반응 재주)
		_curving_shot(world, attacker, target, atk, res)
		load("res://scripts/rules/hunt.gd").after_attack(world, attacker, target, atk, res)
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

## 밀어내기: 공격자에게서 곧장 멀어지는 쪽으로 최대 N칸(가능한 만큼). 강제 이동이라 기회 공격 없음.
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
## opts: {"free": true} = 기회 공격 없는 이동력(free_move_no_oa — 전술적 이동, 물러나기, 챔피언)을 쓴다.
static func move(world: Dictionary, c: Node, to: Vector2i, opts: Dictionary = {}) -> Dictionary:
	var grid: Node = world["grid"]
	var free: bool = opts.get("free", false)
	var budget_key := "free_move_no_oa" if free else "movement"
	var other: Node = grid.creature_at(to)
	if other != null and other != c:
		return _fail("다른 생물이 있는 칸에는 멈출 수 없다")
	var allies: Array = grid.creatures().filter(func(o: Node) -> bool: return o != c and not o.is_hostile_to(c))
	var p: Dictionary = grid.find_path(c, to, int(c.turn.get(budget_key, 0)), allies)
	if p.is_empty():
		return _fail("갈 수 없다(이동력 %d)" % int(c.turn.get(budget_key, 0)))
	var out := {"ok": true, "moved": 0, "cost": 0, "stopped": ""}
	var cur: Vector2i = grid.cell_of(c)
	if not free and not p["path"].is_empty():
		for a in c.active_conditions():
			var md: Dictionary = a["def"].get("move_damage", {})
			if not md.is_empty():
				var mdice := str(a["instance"].get("params", {}).get("move_dice", md["dice"]))  # 우레 칼날: 건 쪽 레벨의 주사위
				Resolver.apply_damage(c, [{"amount": Dice.roll(mdice, str(a["def"]["name"]["ko"]))["total"], "damage_type": str(md["damage_type"])}],
					{"attacker": a["instance"].get("source")})  # 휘감김: 움직이면 피해
				if md.get("once", false):
					c.remove_condition(str(a["id"]))
		if c.dead or c.is_down():
			return out
	for nxt: Vector2i in p["path"]:
		if not c.turn.get("disengaged", false) and not free:
			_opportunity_attacks(world, c, cur, nxt)
		if c.dead or c.is_down() or c.speed() == 0 or c.has_meta("sentinel_stopped"):
			out["stopped"] = "이동 중 쓰러지거나 멈춤"
			break
		var step: int = 0
		for fc in grid.footprint(nxt, grid.size_of(c)):
			step = maxi(step, grid.step_cost(fc - (nxt - cur), fc, c))
		c.turn[budget_key] = int(c.turn[budget_key]) - step
		if not free:
			c.turn["moved"] = true
		out["cost"] += step
		var prev := cur
		grid.move_creature(c, nxt)
		out["moved"] += 1
		cur = nxt
		if not c.turn.get("disengaged", false) and not free:
			_polearm_enter_oa(world, c, prev, cur)  # 이탈·기회 공격 없는 이동이면 장병기 진입 공격도 없다
		if c.dead or c.is_down() or c.has_meta("sentinel_stopped"):
			out["stopped"] = "이동 중 쓰러지거나 멈춤"
			break
		load("res://scripts/rules/spellcasting.gd").on_moved(world, c)
		if grid.cell_of(c) != cur:
			out["stopped"] = "옮겨짐"  # 관문 등으로 다른 칸에 옮겨지면 남은 경로를 버린다
			break
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
		if e.has_meta("no_opportunity_until"):
			continue
		if mover.has_cap("no_oa_from_melee_target") and e in mover.turn.get("melee_targets", []):
			continue  # 날랜 발: 이번 턴 근접 공격한 대상은 기회 공격 못 함
		if e.has_meta("monster"):
			if preload("res://scripts/rules/monster_factory.gd").melee_reach(e) <= 0:
				continue
		elif e.active_set != "melee" or is_ranged_weapon(weapon_data(e.weapon("main"))):
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


## 휘는 화살(능력 태그 curving_shot, 설정 켬): 원거리 무기 공격이 빗나가면 보너스 행동으로 원래 대상에 가장 가까운 다른 적을 같은 공격으로.
static func _curving_shot(world: Dictionary, attacker: Node, target: Node, atk: Dictionary, res: Dictionary) -> void:
	if res.get("hit", true) or not res.get("valid", false) or atk.get("curved", false) or str(atk.get("kind", "")) != "ranged" or not atk.get("weapon", false):
		return
	if not attacker.has_cap("curving_shot") or str(attacker.options.get("curving_shot", "on")) != "on" or not can_spend(attacker, "bonus"):
		return
	var grid: Node = world["grid"]
	var best: Node = null
	for o: Node in grid.creatures():
		if o != target and o != attacker and not o.dead and attacker.is_hostile_to(o) \
				and (best == null or grid.distance_between(o, target) < grid.distance_between(best, target)):
			best = o
	if best == null:
		return
	spend(attacker, "bonus")
	var atk2 := atk.duplicate(true)
	atk2["curved"] = true
	atk2["name"] = "휘는 화살(%s)" % atk.get("name", "")
	res["curving"] = _do_attack(world, attacker, best, atk2)


## 장병기 달인(능력 태그 polearm_enter_oa): 장병기를 쥔 적의 도달 밖에서 안으로 들어오면 그 적이 반응으로 기회 공격(반응 id = 재주 기능).
static func _polearm_enter_oa(world: Dictionary, mover: Node, prev: Vector2i, now: Vector2i) -> void:
	var grid: Node = world["grid"]
	var sz: int = grid.size_of(mover)
	for e: Node in grid.creatures():
		if e == mover or e.dead or not e.is_hostile_to(mover) or not e.can_react() or not e.has_cap("polearm_enter_oa"):
			continue
		if e.active_set != "melee" or not str(e.weapon("main")) in POLEARMS:
			continue
		var reach := reach_of(e)
		var before := _dist_cells(grid, grid.occupied_cells(e), grid.footprint(prev, sz))
		var after := _dist_cells(grid, grid.occupied_cells(e), grid.footprint(now, sz))
		if before > reach and after <= reach and grid.can_see(e, mover):
			load("res://scripts/rules/features.gd").offer_reaction(e, "polearm_master", {"target": mover},
				func() -> void: opportunity_attack(world, e, mover))
		if mover.dead or mover.is_down():
			return


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
	var cost: int = mini(1, c.speed() / 2) if c.has_cap("stand_up_one_tile") else c.speed() / 2  # 단련된 몸: 1칸
	if c.speed() == 0 or int(c.turn.get("movement", 0)) < cost:
		return _fail("이동력이 모자란다")
	c.turn["movement"] = int(c.turn["movement"]) - cost
	c.remove_condition("prone")
	return {"ok": true, "cost": cost}


## 교활한 행동(로그 2레벨): 질주·이탈·숨기를 보너스 행동으로.
static func cunning_action(world: Dictionary, c: Node, which: String) -> Dictionary:
	if not c.has_cap("bonus_dash_disengage_hide"):
		return _fail("교활한 행동이 없다")
	match which:
		"dash":
			return dash(c, "bonus")
		"disengage":
			return disengage(c, "bonus")
		"hide":
			return hide(world, c, "bonus")
	return _fail("모르는 행동")


static func dash(c: Node, cost: String = "action") -> Dictionary:
	if not spend(c, cost):
		return _fail("행동이 없다")
	c.turn["movement"] = int(c.turn.get("movement", 0)) + c.speed()
	c.turn["dashed"] = true
	if c.has_cap("dash_temp_hp"):
		Resolver.grant_temp_hp(c, 2 * c.feature_level("rage"))  # 짐승의 면모: 종마 — 질주하면 임시 HP = 바바리안 레벨 × 2
	return {"ok": true}


static func disengage(c: Node, cost: String = "action") -> Dictionary:
	if not spend(c, cost):
		return _fail("행동이 없다")
	c.turn["disengaged"] = true
	return {"ok": true}


## 돕기: 인접한 아군을 돕는다 — 쓰러졌으면 HP 1로 일으키고(3·7단계), 넘어짐·돕기로 풀리는 상태(helpable — BG3)를 푼다.
static func help(world: Dictionary, c: Node, ally: Node, range_tiles: int = 1) -> Dictionary:
	var helpable: Array = []
	for a in ally.active_conditions():
		if a["def"].get("helpable", false) or str(a["id"]) == "prone":
			helpable.append(str(a["id"]))
	for cond in ally.conditions:
		if str(cond["id"]) == "restrained" and cond.get("params", {}).has("escape_dc") and not "restrained" in helpable:
			helpable.append("restrained")  # BG3 돕기: 거미줄·덩굴에 걸린 아군을 풀어 준다
	if not ally.is_down() and helpable.is_empty():
		return _fail("쓰러졌거나 돕기로 풀 상태가 있는 아군에게만")
	if world["grid"].distance_between(c, ally) > range_tiles:
		return _fail("너무 멀다")
	if not spend(c, "action"):
		return _fail("행동이 없다")
	if ally.is_down():
		Resolver.heal(ally, 1, c)
	for cid: String in helpable:
		ally.remove_condition(cid)  # BG3 돕기: 넘어짐·잠듦·연소·휘감김·거미줄 속박·비틀거림·균형 잃음 등을 풀어 준다
	return {"ok": true, "removed": helpable}


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
	var r := Physics.shove(grid, c, target, c.team == target.team)  # 같은 편만 판정 없이(중립은 판정 — BG3)
	r["ok"] = true
	return r


## 점프(보너스 행동 + 이동 2칸): 거리 3칸 + 근력 수정치 2당 1칸. 기회 공격 없음.
## 착지가 2단계 이상 낮으면 낙하 피해. 1단계보다 높은 곳으로는 못 뛴다.
static func jump(world: Dictionary, c: Node, to: Vector2i) -> Dictionary:
	var grid: Node = world["grid"]
	var from: Vector2i = grid.cell_of(c)
	if c.has_flag("no_jump"):
		return _fail("짐이 너무 무거워 도약할 수 없다")
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
	var mod: int = c.ability_mod("str")
	if c.has_cap("jump_dex"):
		mod = maxi(mod, c.ability_mod("dex"))  # 2층 작업 등: 민첩으로 도약(원문)
	var base := 3 + maxi(mod, 0) / 2
	base += c.cap_count("jump_plus_1")  # BG3식 도약 보너스(2층 작업·뛰어난 운동선수 — 겹친다)
	for m in c.modifier_entries():
		var e: Dictionary = m["effect"]
		if e["type"] == "modify" and e["stat"] == "jump_tiles" and e.has("set"):
			base = maxi(base, int(e.get("set", 0)))  # Jump 주문: 6칸
		if e["type"] == "modify" and e["stat"] == "jump_tiles" and e.has("add"):
			base += int(e["add"])  # 호랑이의 심장: 도약 +3칸
	if c.has_cap("jump_half_more"):
		base = floori(base * 1.5)  # 단련된 몸: 도약 +50%
	for m in c.modifier_entries():
		var e: Dictionary = m["effect"]
		if e["type"] == "modify" and e["stat"] == "jump_tiles" and e.has("multiply"):
			base = floori(base * float(e["multiply"]))  # 짐 무거움: 도약 절반
	return base


## 던지기(행동): 즉석 무기 공격(근력, 숙련 없음 — SRD Improvised Weapons). 맞으면 무게 피해.
## range_tiles < 0이면 BG3 던지기 거리(Physics.throw_range_tiles — 근력·무게).
static func throw_object(world: Dictionary, c: Node, target: Node, weight_kg: float, range_tiles: int = -1) -> Dictionary:
	if weight_kg > Physics.max_throw_kg(c):
		return _fail("너무 무겁다")
	var grid: Node = world["grid"]
	if range_tiles < 0:
		range_tiles = Physics.throw_range_tiles(c, weight_kg)
	if grid.distance_between(c, target) > grid.effective_range(c, grid.cell_of(target), range_tiles):
		return _fail("사거리 밖")
	if int(c.turn.get("attacks_left", 0)) <= 0:  # 공격 행동의 공격 하나(추가 공격과 이어진다 — BG3)
		if not spend(c, "action"):
			return _fail("행동이 없다")
		c.turn["attacks_left"] = c.attacks_per_action
	c.turn["attacks_left"] -= 1
	var brawl: int = c.ability_mod("str") if c.has_cap("brawler") else 0  # 주먹다짐: 근력 수정치를 한 번 더
	var rb := Resolver.rage_bonus(c) * (2 if c.has_flag("throw_rage_double") else 1)  # 분노 피해는 던지기에도(BG3), 거인의 분노는 두 배
	var extra := rb + brawl
	var dice := Physics.throw_damage_dice(weight_kg)
	# 피해는 공격 한 번으로 굴린다(치명타 두 배·집중·사망 내성 한 번 — 2026-11-24 버그 수정)
	var atk := {"name": "던지기", "bonus": c.ability_mod("str") + brawl, "kind": "ranged", "weapon": false,
		"damage": [{"dice": dice if extra == 0 else "%s%+d" % [dice, extra], "damage_type": "bludgeoning"}]}
	var ctx: Dictionary = grid.attack_context(c, target)
	if is_threatened(world, c):
		ctx["disadvantage"].append("근접 위협")
	var res := Resolver.attack(c, target, atk, ctx)
	if res["hit"]:
		res["throw"] = Physics.throw_hit(grid, c, target, weight_kg, false)
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


# ======================================================================
# 몬스터 행동(데이터의 actions·multiattack — /add-monster 규칙)
# ======================================================================

## 몬스터 행동 하나. 공격 행동은 다중 공격 목록 안이면 같은 행동의 남은 공격을 쓴다.
## use: 근접·투척 겸용 무기를 어떻게 쓸지("melee" | "ranged"). 결과: {"ok", ...}
static func monster_action(world: Dictionary, m: Node, action_id: String, target: Node, use: String = "") -> Dictionary:
	var MF := preload("res://scripts/rules/monster_factory.gd")
	var a := MF.action(m, action_id)
	if a.is_empty():
		return _fail("모르는 행동")
	if int(m.cooldowns.get(action_id, 0)) > 0:
		return _fail("재충전 중(%d턴)" % m.cooldowns[action_id])
	var multi: Dictionary = m.get_meta("monster").get("multiattack", {})
	var in_multi: bool = action_id in multi.get("actions", [])
	if int(m.turn.get("attacks_left", 0)) <= 0 or not in_multi:
		if not spend(m, "action"):
			return _fail("행동이 없다")
		m.turn["attacks_left"] = int(multi.get("count", 1)) if in_multi else 1
	var res: Dictionary
	if a["type"] == "attack":
		var atk := MF.to_attack(a, use)
		res = _do_attack(world, m, target, atk)
		if not res.get("ok", false):
			m.turn["attacks_left"] = int(m.turn["attacks_left"])  # 비용은 이미 씀
			return res
		_monster_on_hit(world, m, target, a, res)
	else:
		res = _monster_save_action(world, m, a, target)
	m.turn["attacks_left"] = int(m.turn["attacks_left"]) - 1
	if a.has("recharge"):
		m.cooldowns[action_id] = MF.RECHARGE_TURNS.get(a["recharge"], 3)
	if world.get("turns") != null:
		world["turns"].notify_hostile_action(m)
	return res


static func _monster_on_hit(world: Dictionary, m: Node, target: Node, a: Dictionary, res: Dictionary) -> void:
	if not res.get("hit", false) or target.dead:
		return
	for e: Dictionary in a.get("on_hit", []):
		_monster_effect(world, m, target, e)


## 몬스터 효과 하나(크기 제한·제외·내성 포함).
static func _monster_effect(world: Dictionary, m: Node, t: Node, e: Dictionary) -> void:
	var order := ["tiny", "small", "medium", "large", "huge", "gargantuan"]
	if e.has("max_size") and order.find(t.size) > order.find(e["max_size"]):
		return
	var ex: Dictionary = e.get("exclude", {})
	if t.creature_type in ex.get("creature_type", []) or t.species_id in ex.get("species", []):
		return
	if e.has("save"):
		var s := Resolver.saving_throw(t, e["save"]["ability"], int(e["save"]["dc"]), {"source": m,
			"against_conditions": [e.get("id", "")]})
		if s["success"]:
			return
	match e["type"]:
		"apply_condition":
			var params := {}
			if e.has("escape_dc"):
				params["escape_dc"] = int(e["escape_dc"])
			t.apply_condition(e["id"], int(e.get("turns", -1)), m, params)
		"advantage":
			var mod := {"effect": {"type": "advantage", "roll": e["roll"], "side": e["side"], "value": e["value"]}, "source": m.name}
			if e.get("consume", "") == "attacked":
				mod["consume_on_attacked"] = true
			if e.get("until", "") == "start_of_attacker_next_turn":
				mod["until_turn_start_of"] = m
			t.extra_modifiers.append(mod)
		"push":
			_push_up_to(world, m, t, int(e.get("tiles", 1)))  # 망치 던지기 등
		"damage":
			var r := Dice.roll(e["dice"], "몬스터 효과")
			var out := Resolver.apply_damage(t, [{"amount": r["total"], "damage_type": e["damage_type"]}], {"attacker": m})
			if e.get("reduce_hp_max", false) and int(out["total"]) > 0 and not t.dead:
				t.hp_max = maxi(t.hp_max - int(out["total"]), 0)  # 생명 흡수: 최대 HP 감소(긴 휴식까지 — 7단계)
				t.hp = mini(t.hp, t.hp_max)
				if t.hp_max == 0:
					Resolver._die(t, "최대 HP 0")


static func _monster_save_action(world: Dictionary, m: Node, a: Dictionary, target: Node) -> Dictionary:
	var grid: Node = world["grid"]
	var rng: Variant = a.get("range_tiles", 1)
	var reach: int = int(rng) if typeof(rng) != TYPE_ARRAY else int(rng[0])
	if target == null or grid.distance_between(m, target) > reach or not grid.can_see(m, target):
		return _fail("대상이 사거리 밖")
	if a.has("area"):
		return _monster_area_save(world, m, a, target)
	var s := Resolver.saving_throw(target, a["ability"], int(a["dc"]), {"source": m,
		"against_conditions": a.get("fail", []).filter(func(e: Dictionary) -> bool: return e["type"] == "apply_condition").map(
			func(e: Dictionary) -> String: return e["id"])})
	if not s["success"]:
		for e: Dictionary in a.get("fail", []):
			_monster_effect(world, m, target, e)
	return {"ok": true, "save": s}


## 범위 내성 행동(용의 숨결 등): area {shape cone·line·sphere, length_tiles·radius_tiles}. 큰 몬스터는 차지한 칸 가운데에서 대상 쪽으로.
## 범위 안 모든 생물(자신 제외)이 내성 — 실패 fail, 성공 success(절반 피해). 피해 주사위는 한 번만(원문). 칸 반응(화염·냉기 등)도.
## 몬스터 범위 행동이 맞힐 생물(AI 아군 피격 검사·실행 공용).
static func monster_area_targets(world: Dictionary, m: Node, a: Dictionary, target: Node) -> Array:
	var grid: Node = world["grid"]
	var ar: Dictionary = a["area"]
	var sz: int = grid.size_of(m)
	var origin: Vector2i = grid.cell_of(m) + Vector2i((sz - 1) / 2, (sz - 1) / 2)
	var aim := Vector2(grid.cell_of(target)) + Vector2(0.5, 0.5)
	var cov: Dictionary = {}
	match str(ar["shape"]):
		"cone":
			cov = Area.cov_cone(grid, origin, aim, int(ar["length_tiles"]))
		"line":
			cov = Area.cov_line(grid, origin, aim, int(ar["length_tiles"]), 0.5 * int(ar.get("width_tiles", 1)))
		_:
			cov = Area.cov_circle(grid, grid.cell_of(target), int(ar.get("radius_tiles", 1)))
	var own_cells: Array[Vector2i] = grid.occupied_cells(m)
	var cells: Array[Vector2i] = []
	for c: Vector2i in cov:
		if not c in own_cells:
			cells.append(c)
	return Area.creatures_in(grid, cells).filter(func(o: Node) -> bool: return o != m and not o.dead)


static func _monster_area_save(world: Dictionary, m: Node, a: Dictionary, target: Node) -> Dictionary:
	var grid: Node = world["grid"]
	var ar: Dictionary = a["area"]
	var sz: int = grid.size_of(m)
	var cell: Vector2i = grid.cell_of(m)
	var origin := cell + Vector2i((sz - 1) / 2, (sz - 1) / 2)
	var aim := Vector2(grid.cell_of(target)) + Vector2(0.5, 0.5)
	var cov: Dictionary = {}
	match str(ar["shape"]):
		"cone":
			cov = Area.cov_cone(grid, origin, aim, int(ar["length_tiles"]))
		"line":
			cov = Area.cov_line(grid, origin, aim, int(ar["length_tiles"]), 0.5 * int(ar.get("width_tiles", 1)))
		_:
			cov = Area.cov_circle(grid, grid.cell_of(target), int(ar.get("radius_tiles", 1)))
	var cells: Array[Vector2i] = []
	var own_cells: Array[Vector2i] = grid.occupied_cells(m)
	for c: Vector2i in cov:
		if not c in own_cells:
			cells.append(c)
	var targets: Array = Area.creatures_in(grid, cells).filter(func(o: Node) -> bool: return o != m and not o.dead)
	var rolled := {}
	var results := Resolver.save_effect(targets, {"ability": a["ability"], "dc": int(a["dc"])}, a.get("fail", []), a.get("success", []),
		{"source": m, "attacker": m, "rolled": rolled})
	var dtype := ""
	for e: Dictionary in a.get("fail", []):
		if e["type"] == "damage":
			dtype = str(e["damage_type"])
			break
	if dtype != "" and world.get("surfaces") != null and not cells.is_empty():
		var amount := 0
		for k: String in rolled:
			amount = maxi(amount, int(rolled[k]))
		world["surfaces"].tile_damage(cells, dtype, amount, m)
	Dice.log_text("%s %s: %d명" % [m.label(), a["name"]["ko"], targets.size()])
	return {"ok": true, "results": results, "cells": cells}


## 속박에서 빠져나오기(행동): 근력(운동) 또는 민첩(곡예) 판정 vs 속박의 escape_dc(붙잡기 대체 — 룰북 6단계).
static func escape(world: Dictionary, c: Node) -> Dictionary:
	# 속박 또는 속박을 포함하는 상태(휘감김 등) 중 풀 수 있는 것(escape_dc)
	var inst: Dictionary = {}
	for cond in c.conditions:
		var def := RulesDB.get_entry("condition", str(cond["id"]))
		if (cond["id"] == "restrained" or "restrained" in def.get("includes", [])) and cond.get("params", {}).has("escape_dc"):
			inst = cond
			break
	if inst.is_empty():
		return _fail("빠져나올 속박이 없다")
	if not spend(c, "action"):
		return _fail("행동이 없다")
	var ability := "str" if c.ability_mod("str") + int(c.skill_bonuses.get("athletics", 0)) >= c.ability_mod("dex") + int(c.skill_bonuses.get("acrobatics", 0)) else "dex"
	var r := Resolver.ability_check(c, ability, int(inst["params"]["escape_dc"]), {"skill": "athletics" if ability == "str" else "acrobatics"})
	if r["success"]:
		c.remove_condition(str(inst["id"]))
	return {"ok": true, "success": r["success"]}


## 날렵한 탈출(고블린): 보너스 행동으로 이탈 또는 숨기.
static func nimble_escape(world: Dictionary, c: Node, which: String) -> Dictionary:
	if not c.has_cap("nimble_escape"):
		return _fail("날렵한 탈출이 없다")
	return disengage(c, "bonus") if which == "disengage" else hide(world, c, "bonus")
