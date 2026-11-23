extends RefCounted
## 판정기(상태 없음). 룰북 8단계 '판정 순서' 12단계를 그대로 따른다.
## 생물의 값은 Creature가, 굴림은 Dice가, 훅은 EventBus가 맡는다.
##
## 공격 정의(attack):
##   {"name": 표시 이름, "bonus": 공격 보너스 합계, "kind": "melee"|"ranged",
##    "weapon": 무기 공격인가, "damage": [{"dice": "1d6+2", "damage_type": "piercing"}],
##    "extra_if_advantage": [...] (고블린처럼 유리일 때 추가 피해)}
## 상황(ctx): {"distance_tiles": 칸(기본 1), "height_diff": 공격자 높이 − 대상 높이(단계),
##    "advantage": [이유], "disadvantage": [이유], "in_combat": bool(기본 true),
##    "source_in_sight": bool(기본 true, 시야 판정은 2단계)}
## 훅 리스너는 넘겨받은 결과 Dictionary를 고쳐 판정에 끼어든다
## (예: on_after_attack_roll에서 res["ac_bonus"] += 5 = Shield).

const DiceExpr := preload("res://scripts/rules/dice_expr.gd")
const Features := preload("res://scripts/rules/features.gd")

## 고지: 높이 2단계 이상 차이면 명중 ±2(룰북 4단계).
const HIGH_GROUND_STEPS := 2
const HIGH_GROUND_BONUS := 2
const CONCENTRATION_DC_MIN := 10
const CONCENTRATION_DC_MAX := 30
const DEATH_SAVE_DC := 10


# ======================================================================
# 공격
# ======================================================================

## 1. 선언: 공격할 수 없으면 이유를 돌려준다. 할 수 있으면 "".
static func can_attack(attacker: Node, target: Node) -> String:
	if attacker.dead or attacker.is_down():
		return "공격자가 쓰러졌다"
	if attacker.is_incapacitated():
		return "공격자가 무력화 상태다"
	if target.dead:
		return "대상이 이미 죽었다"
	if target.has_flag("ethereal") or attacker.has_flag("ethereal"):
		return "다른 차원에 있다"  # Blink
	for a in attacker.active_conditions():
		if a["def"].get("flags", {}).get("cannot_attack_source", false) and a["instance"]["source"] == target:
			return "매혹한 상대는 공격할 수 없다"
	return ""


## 공격 한 번을 끝까지 처리한다(8단계 판정 순서 1, 3~12).
static func attack(attacker: Node, target: Node, atk: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var res := _attack_setup(attacker, target, atk, ctx, false)
	if not res["valid"]:
		Dice.log_text("%s → %s 공격 불가: %s" % [attacker.label(), target.label(), res["reason"]])
		return res
	# 4. 굴림
	var d := luck(attacker, Dice.d20(res["mode"], "%s 공격" % attacker.label()))
	res["rolls"] = d["rolls"]
	res["natural"] = d["natural"]
	res["crit_threshold"] = attacker.crit_threshold if atk.get("weapon", false) else 20
	var bonus_dice := roll_bonus_dice(attacker, "attack_roll")
	res["bonus_dice"] = bonus_dice
	res["total"] = res["natural"] + res["attack_bonus"] + bonus_dice
	_decide_hit(res)
	if not res["hit"] and res["natural"] != 1:
		res["total"] += inspire(attacker)  # 바드의 영감: 실패한 d20 시험에 주사위를 더한다
		_decide_hit(res)
	# 받는 쪽의 '다음 공격을 받으면 사라지는' 수정치(Guiding Bolt)
	for m in target.extra_modifiers.duplicate():
		if m.get("consume_on_attacked", false):
			target.extra_modifiers.erase(m)
	# 공격하면 끝나는 상태(Invisibility·Sanctuary — params.ends_on_attack)
	for cond in attacker.conditions.duplicate():
		if cond.get("params", {}).get("ends_on_attack", false) or RulesDB.get_entry("condition", str(cond["id"])).get("ends_on_attack", false):
			attacker.remove_condition(cond["id"])
	# 다음 공격 한 번에만 붙는 수정치(Sap·Vex 등)는 굴림에 쓰이면 사라진다.
	for m in attacker.extra_modifiers.duplicate():
		if m.get("consume_on_attack", false) and (m.get("target_only") == null or m.get("target_only") == target):
			attacker.extra_modifiers.erase(m)
	# 숨기로 얻은 투명은 공격 굴림을 하면 풀린다(원문 Hide, 5단계 은신 공격).
	var hide: Dictionary = attacker.condition_instance("invisible")
	if not hide.is_empty() and hide["source"] is String and hide["source"] == "hide":
		attacker.remove_condition("invisible")
	# 5. 명중 직후 반응(Shield 등)
	EventBus.on_after_attack_roll.emit(res)
	_decide_hit(res)
	_mirror_image(attacker, target, res)
	# 6. 명중 결과
	if res["hit"] and not res["crit"] and target.auto_crit_against_within(res["distance"]):
		res["crit"] = true
		res["auto_crit"] = true
	if res["hit"]:
		EventBus.on_hit.emit(res)
		Features.hook("on_hit", attacker, {"res": res})
		Features.hook("on_hit", target, {"res": res})
		_hit_riders(attacker, target, atk, res)
		if res["crit"]:
			EventBus.on_crit.emit(res)
			if attacker.has_cap("crit_free_move"):
				attacker.turn["free_move_no_oa"] = maxi(int(attacker.turn.get("free_move_no_oa", 0)), attacker.speed() / 2)
	else:
		EventBus.on_miss.emit(res)
	# 12. 로그(굴림 줄)
	Dice.log_text("%s → %s %s%s: %d + %d = %d vs AC %d → %s" % [
		attacker.label(), target.label(), atk.get("name", "공격"), _mode_note(res["mode"], res["rolls"]),
		res["natural"], res["attack_bonus"], res["total"], res["ac"] + res["ac_bonus"],
		"치명타" if res["crit"] else ("명중" if res["hit"] else "빗나감")])
	# 7~11. 피해
	if res["hit"]:
		var parts := _attack_damage_parts(attacker, atk, res)
		parts.append_array(res.get("extra_damage", []))
		var rolled := _roll_damage(attacker, atk, parts, res)
		var mult: float = float(res.get("damage_multiplier", 1.0))
		if mult != 1.0:
			for r: Dictionary in rolled:
				r["multiplier"] = mult
		var cut := int(res.get("damage_reduction", 0))  # 공격 피해 줄이기(몽크 공격 쳐내기)
		for r: Dictionary in rolled:
			if cut <= 0:
				break
			var k := mini(cut, int(r["amount"]))
			r["amount"] = int(r["amount"]) - k
			cut -= k
		res["damage"] = apply_damage(target, rolled, {"crit": res["crit"], "attacker": attacker,
			"in_combat": ctx.get("in_combat", true)})
	return res


## 굴림 없는 미리보기(8단계 판정 순서 2, 2단계 공통 처리 규칙 2).
## 결과: {"valid", "reason", "hit_chance", "crit_chance", "mode", "attack_bonus", "ac",
##        "damage": {"min", "max", "avg"}(명중 시, 저항·취약 반영)}
static func preview_attack(attacker: Node, target: Node, atk: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var res := _attack_setup(attacker, target, atk, ctx, true)
	if not res["valid"]:
		return res
	var p := hit_probability(target.ac() + res["ac_bonus"], res["attack_bonus"] + avg_bonus_dice(attacker, "attack_roll"))
	res["hit_chance"] = apply_mode(p, res["mode"])
	res["crit_chance"] = apply_mode(0.05, res["mode"])
	var lo := 0.0
	var hi := 0.0
	var avg := 0.0
	for part: Dictionary in _attack_damage_parts(attacker, atk, res):
		var s := DiceExpr.stats(part["dice"])
		var t: String = part["damage_type"]
		lo += modify_amount(target, maxf(s["min"], 0.0), t, 1.0, true)
		hi += modify_amount(target, maxf(s["max"], 0.0), t, 1.0, true)
		avg += modify_amount(target, maxf(s["avg"], 0.0), t, 1.0, false)
	res["damage"] = {"min": lo, "max": hi, "avg": avg}
	return res


## 명중 확률 p = (21 − (AC − 공격 보너스)) / 20, 5~95%로 자른다(자연 1·20).
static func hit_probability(ac: int, attack_bonus: float) -> float:
	return clampf((21.0 - (ac - attack_bonus)) / 20.0, 0.05, 0.95)


## 굴림에 더하는 주사위 수정치(Bless +1d4, Bane −1d4 — modify stat attack_roll/saving_throw, add가 주사위 식).
static func roll_bonus_dice(c: Node, stat: String) -> int:
	var total := 0
	for m in c.modifier_entries():
		var e: Dictionary = m["effect"]
		if e["type"] == "modify" and e["stat"] == stat and typeof(e.get("add")) == TYPE_STRING:
			total += Dice.roll(e["add"], stat)["total"]
	return total


static func avg_bonus_dice(c: Node, stat: String) -> float:
	var total := 0.0
	for m in c.modifier_entries():
		var e: Dictionary = m["effect"]
		if e["type"] == "modify" and e["stat"] == stat and typeof(e.get("add")) == TYPE_STRING:
			total += float(DiceExpr.stats(e["add"]).get("avg", 0.0))
	return total


## 유리면 1 − (1 − p)², 불리면 p².
static func apply_mode(p: float, mode: int) -> float:
	if mode > 0:
		return 1.0 - (1.0 - p) * (1.0 - p)
	if mode < 0:
		return p * p
	return p


static func _attack_setup(attacker: Node, target: Node, atk: Dictionary, ctx: Dictionary, preview: bool) -> Dictionary:
	var res := {"attacker": attacker, "target": target, "attack": atk, "ctx": ctx, "preview": preview,
		"valid": true, "reason": "", "distance": int(ctx.get("distance_tiles", 1)),
		"advantage": [], "disadvantage": [], "attack_bonus": int(atk.get("bonus", 0)),
		"ac": target.ac(), "ac_bonus": 0, "hit": false, "crit": false, "auto_crit": false,
		"natural": 0, "total": 0, "rolls": []}
	var why := can_attack(attacker, target)
	if why == "" and not preview:
		why = _sanctuary(attacker, target)
	if why != "":
		res["valid"] = false
		res["reason"] = why
		return res
	# 3. 유리·불리 수집
	_collect_attack_mods(attacker, target, res)
	EventBus.on_before_attack_roll.emit(res)
	res["mode"] = mode_of(res["advantage"], res["disadvantage"])
	return res


static func _collect_attack_mods(attacker: Node, target: Node, res: Dictionary) -> void:
	var ctx: Dictionary = res["ctx"]
	for m in attacker.modifier_entries():
		_add_adv(m, "attack", "self", attacker, target, res, str(res.get("attack", {}).get("ability", "")))  # 능력 한정(무모한 공격: 근력)
	for m in target.modifier_entries():
		_add_adv(m, "attack", "against", target, attacker, res)
	res["advantage"].append_array(ctx.get("advantage", []))
	res["disadvantage"].append_array(ctx.get("disadvantage", []))
	var hd := int(ctx.get("height_diff", 0))
	if hd >= HIGH_GROUND_STEPS:
		res["attack_bonus"] += HIGH_GROUND_BONUS
		res["high_ground"] = HIGH_GROUND_BONUS
	elif hd <= -HIGH_GROUND_STEPS:
		res["attack_bonus"] -= HIGH_GROUND_BONUS
		res["high_ground"] = -HIGH_GROUND_BONUS


## 수정치 하나가 이 굴림에 적용되면 res의 advantage/disadvantage에 이유를 더한다.
## owner = 수정치를 가진 생물, other = 상대.
static func _add_adv(m: Dictionary, roll: String, side: String, owner: Node, other: Node, res: Dictionary,
		ability: String = "") -> void:
	var e: Dictionary = m["effect"]
	if e["type"] != "advantage" or e["roll"] != roll or e["side"] != side:
		return
	if e.has("ability") and not ability in e["ability"]:
		return
	if e.has("skill") and not str(res.get("skill", "")) in e["skill"]:
		return  # 기능 한정 유리(엘프 장화: 은신)
	if e.get("spell_attack", false) and not res.get("attack", {}).has("spell"):
		return  # 주문 공격 한정(타고난 마법)
	if e.has("attacker_types") and (other == null or not other.creature_type in e["attacker_types"]):
		return  # Protection from Evil and Good
	var dist := int(res.get("distance", 1))
	match e.get("range", ""):
		"adjacent":
			if dist > 1:
				return
		"far":
			if dist <= 1:
				return
	var only: Variant = m["instance"].get("target_only")
	if only != null and only != other:
		return
	var ctx: Dictionary = res.get("ctx", {})
	match e.get("requires", ""):
		"source_in_sight":
			if not ctx.get("source_in_sight", true):
				return
		"other_is_source":
			if m["instance"].get("source") != other:
				return
	match e.get("unless", ""):
		"other_sees_invisible":
			if other != null and (other.senses.has("see_invisible") or other.senses.has("truesight")):
				return
		"attacker_cannot_see":
			if other != null and other.has_condition("blinded"):
				return
	var why: String = m["condition"] if m["condition"] != "" else str(m["instance"].get("source", "효과"))
	res[e["value"]].append("%s(%s)" % [why, owner.label()])


## 유리와 불리가 둘 다 있으면 개수와 상관없이 상쇄한다(원문, 4단계 중첩 규칙 3).
static func mode_of(advantage: Array, disadvantage: Array) -> int:
	var a := not advantage.is_empty()
	var d := not disadvantage.is_empty()
	if a and not d:
		return 1
	if d and not a:
		return -1
	return 0


static func _decide_hit(res: Dictionary) -> void:
	var n: int = res["natural"]
	if n >= int(res.get("crit_threshold", 20)):
		res["hit"] = true
		res["crit"] = true
	elif n == 1:
		res["hit"] = false
		res["crit"] = false
	else:
		res["hit"] = res["total"] >= res["ac"] + res["ac_bonus"]
		res["crit"] = false


static func _attack_damage_parts(attacker: Node, atk: Dictionary, res: Dictionary) -> Array:
	var parts: Array = []
	parts.append_array(atk.get("damage", []))
	if res.get("mode", 0) > 0:
		parts.append_array(atk.get("extra_if_advantage", []))
	# 공격자 상태의 on_hit 피해(무기 담금 등)
	for a in attacker.active_conditions():
		for e: Dictionary in a["def"].get("hooks", {}).get("on_hit", []):
			if e["type"] != "damage":
				continue
			if e.get("requires", "") == "weapon_attack" and not atk.get("weapon", false):
				continue
			var t: String = e["damage_type"]
			if t == "chosen":
				t = a["instance"].get("params", {}).get("damage_type", "fire")
			parts.append({"dice": e["dice"], "damage_type": t})
	return parts


## 명중에 붙는 데이터 장치(주문·기능 이름을 모른다):
## - 대상의 상태 hooks.on_hit_by_source: 그 상태를 건 생물이 맞히면 피해를 더한다(사냥꾼의 표식).
## - 공격자의 상태 hooks.on_weapon_hit: 무기로 맞히면 대상 내성 → 실패 효과(얽어매는 일격). consume_on_trigger면 상태를 지운다.
## - 능력 태그 extra_damage_wounded: 턴당 1회 HP가 줄어든 대상에게 무기 명중 +1d8(거상 학살자).
static func _hit_riders(attacker: Node, target: Node, atk: Dictionary, res: Dictionary) -> void:
	if not res.has("extra_damage"):
		res["extra_damage"] = []
	for a in target.active_conditions():
		var src: Variant = a["instance"].get("source")
		if not (src is Node) or src != attacker:  # 출처가 글자(함정 등)이거나 다른 생물
			continue
		for e: Dictionary in a["def"].get("hooks", {}).get("on_hit_by_source", []):
			if e["type"] == "damage":
				res["extra_damage"].append({"dice": e["dice"], "damage_type": e["damage_type"]})
		EventBus.on_hit_by_source.emit(res)
	if atk.get("weapon", false):
		for a in attacker.active_conditions():
			var effs: Array = a["def"].get("hooks", {}).get("on_weapon_hit", [])
			if effs.is_empty():
				continue
			var inst: Dictionary = a["instance"]
			var caster: Variant = inst.get("source")
			var dc: int = load("res://scripts/rules/spellcasting.gd").spell_dc(caster) if caster is Node else 13
			var params := {"instance": inst.get("params", {}).get("instance"), "escape_dc": dc}
			if a["def"].get("melee_only", false) and atk.get("kind", "") != "melee":
				continue  # 강타: 근접 무기·비무장 공격만(원거리 명중에는 남겨 둔다)
			for e: Dictionary in effs:
				if e["type"] == "damage":
					_weapon_hit_damage(attacker, target, inst, e, params, res)
					continue
				if e["type"] != "save":
					continue
				var sopts := {}
				if e["save"].get("large_advantage", false) and str(target.size) in ["large", "huge", "gargantuan"]:
					sopts["advantage"] = ["큰 생물"]
				var sv := saving_throw(target, str(e["save"]["ability"]), dc, sopts)
				if not sv.get("success", false):
					for f: Dictionary in e.get("on_fail", []):
						if f["type"] == "apply_condition":
							target.apply_condition(f["id"], -1, caster, params)
			EventBus.on_weapon_hit.emit(res)
			if a["def"].get("consume_on_trigger", false):
				attacker.remove_condition(str(a["id"]))
		_stunning_strike(attacker, target, atk)
		# 능력 태그 frenzy(광전사 광란): 분노 중 무모한 공격이면 턴의 첫 근력 명중에 (분노 피해)d6
		if attacker.has_cap("frenzy") and attacker.has_condition("raging") and attacker.turn.get("reckless", false) \
				and str(atk.get("ability", "")) == "str" and not attacker.turn.get("frenzy_used", false):
			attacker.turn["frenzy_used"] = true
			res["extra_damage"].append({"dice": "%dd6" % rage_bonus(attacker), "damage_type": atk["damage"][0]["damage_type"]})
		if attacker.has_cap("extra_damage_wounded") and target.hp < target.hp_max and not attacker.turn.get("wounded_bonus_used", false):
			attacker.turn["wounded_bonus_used"] = true
			res["extra_damage"].append({"dice": "1d8", "damage_type": atk["damage"][0]["damage_type"]})


## 능력 태그 stunning_strike(몽크 충격의 일격): 턴당 1회, 무술 공격 명중 + 설정 on + 기 1 → 건강 내성(DC 8 + 지혜 + 숙련).
## 실패: 기절(대상의 다음 턴 동안). 성공: 다음 자기 턴 시작까지 속도 절반, 다음 공격받을 때 유리.
static func _stunning_strike(attacker: Node, target: Node, atk: Dictionary) -> void:
	if not attacker.has_cap("stunning_strike") or not atk.get("martial", false) or attacker.turn.get("stun_used", false):
		return
	if str(attacker.options.get("stunning_strike", "on")) != "on" or attacker.resource("focus") <= 0 or target.dead:
		return
	attacker.turn["stun_used"] = true
	attacker.spend_resource("focus")
	var dc: int = 8 + attacker.ability_mod("wis") + attacker.proficiency_bonus
	var s := saving_throw(target, "con", dc)
	if not s["success"]:
		target.apply_condition("stunned", 1, attacker)
		Dice.log_text("%s 충격의 일격: %s 기절" % [attacker.label(), target.label()])
	else:
		target.extra_modifiers.append({"effect": {"type": "modify", "stat": "speed_tiles", "multiply": 0.5}, "source": "stunning_strike", "until_turn_start_of": attacker})
		target.extra_modifiers.append({"effect": {"type": "advantage", "roll": "attack", "side": "against", "value": "advantage"},
			"source": "stunning_strike", "consume_on_attacked": true, "until_turn_start_of": attacker})


## 능력 태그 hunters_lore(사냥꾼의 지식): 내가 건 표식(상태 데이터 reveals_defenses)이 있는 대상의 면역·저항·취약을 안다.
static func lore_lines(c: Node, t: Node) -> Array:
	if not c.has_cap("hunters_lore") or t == c:
		return []
	var marked := false
	for a in t.active_conditions():
		if a["instance"].get("source") == c and a["def"].get("reveals_defenses", false):
			marked = true
	if not marked:
		return []
	var parts: Array = []
	if not t.damage_immunities.is_empty():
		parts.append("면역 " + ", ".join(t.damage_immunities))
	if not t.damage_resistances.is_empty():
		parts.append("저항 " + ", ".join(t.damage_resistances))
	if not t.damage_vulnerabilities.is_empty():
		parts.append("취약 " + ", ".join(t.damage_vulnerabilities))
	return ["사냥꾼의 지식: " + ("; ".join(parts) if not parts.is_empty() else "면역·저항·취약 없음")]


## 기능 판정 보너스: 숙련이면 그 값, 아니면 능력 태그 jack_of_all_trades(바드 만물박사)로 숙련 보너스 절반(내림).
static func _skill_bonus(c: Node, skill: String) -> int:
	if skill == "":
		return 0
	if c.skill_bonuses.has(skill):
		return int(c.skill_bonuses[skill])
	return c.proficiency_bonus / 2 if c.has_cap("jack_of_all_trades") else 0


## 바드의 영감(상태 bardic_inspiration, params.die): 실패한 d20 시험에 자동으로 굴려 더하고 사라진다(BG3식 자동). 더한 값.
static func inspire(c: Node) -> int:
	var inst: Dictionary = c.condition_instance("bardic_inspiration")
	if inst.is_empty():
		return 0
	var n: int = Dice.roll(str(inst.get("params", {}).get("die", "1d6")), "바드의 영감")["total"]
	c.remove_condition("bardic_inspiration")
	Dice.log_text("%s: 바드의 영감 +%d" % [c.label(), n])
	return n


## 분노 피해 보너스(수정치 stat rage_damage의 합 — 분노 상태 데이터).
static func rage_bonus(c: Node) -> int:
	var n := 0
	for m in c.modifier_entries():
		if m["effect"]["type"] == "modify" and m["effect"]["stat"] == "rage_damage":
			n += int(m["effect"].get("add", 0))
	return n


## 무기 명중 피해 장치(on_weapon_hit damage — 강타·신의 은총): dice + 상위 슬롯마다 per_slot, 대상 종류가 bonus_vs.types면 + bonus_vs.dice.
## apply: 맞힌 대상에게 상태(repeat_save {ability}면 턴 끝 내성 — 시전자 DC, 지속 피해 주사위는 올린 슬롯만큼 함께 커진다).
static func _weapon_hit_damage(attacker: Node, target: Node, inst: Dictionary, e: Dictionary, params: Dictionary, res: Dictionary) -> void:
	var Sp: Variant = load("res://scripts/rules/spellcasting.gd")
	var extra := 0
	var spell_inst: Dictionary = Sp.instances.get(params.get("instance", -1), {})
	if not spell_inst.is_empty():
		extra = maxi(0, int(spell_inst.get("slot", 0)) - int(RulesDB.get_entry("spell", str(spell_inst["spell"])).get("level", 0)))
	var dice := str(e["dice"])
	for i in extra:
		dice += "+" + str(e.get("per_slot", ""))
	dice = dice.trim_suffix("+")
	var bonus: Dictionary = e.get("bonus_vs", {})
	if not bonus.is_empty() and str(target.creature_type) in bonus.get("types", []):
		dice += "+" + str(bonus["dice"])
	res["extra_damage"].append({"dice": dice, "damage_type": e["damage_type"]})
	var caster: Variant = inst.get("source")
	for f: Dictionary in e.get("apply", []):
		var p := params.duplicate()
		if f.has("repeat_save") and caster is Node:
			p["repeat_save"] = {"ability": f["repeat_save"]["ability"], "dc": Sp.spell_dc(caster)}
		if f.has("dot_dice"):
			var dot := str(f["dot_dice"])
			for i in extra:
				dot += "+" + str(f["dot_dice"])
			p["dice"] = dot
		target.apply_condition(f["id"], int(f.get("turns", -1)), caster, p)


## 능력 태그 dark_ones_blessing(악마 후원자): 적을 0 HP로 만들면(또는 2칸 안에서 누가 만들면) 임시 HP = 매력 + 워락 레벨(최소 1).
static func _dark_ones_blessing(target: Node, opts: Dictionary) -> void:
	var cands: Array = []
	var atk: Variant = opts.get("attacker")
	if atk is Node and atk.has_cap("dark_ones_blessing"):
		cands.append(atk)
	var rq: Node = EventBus.reaction_queue
	if rq != null and is_instance_valid(rq) and rq.world.has("grid"):
		var grid: Node = rq.world["grid"]
		if grid.creatures().has(target):
			for o: Node in grid.creatures():
				if o != target and not o.dead and o.has_cap("dark_ones_blessing") and not o in cands and grid.distance_between(o, target) <= 2:
					cands.append(o)
	for o: Node in cands:
		if o.is_hostile_to(target):
			grant_temp_hp(o, maxi(1, o.ability_mod("cha") + o.level))
			Dice.log_text("%s 어둠의 축복: 임시 HP" % o.label())


## 0 HP가 된 생물의 상태 중 transfer_on_drop이 있는 것은 건 시전자가 볼 수 있는 가장 가까운 적(range 칸 안)에게 옮긴다(사냥꾼의 표식).
static func _transfer_on_drop(target: Node) -> void:
	for a in target.active_conditions():
		var tr: Dictionary = a["def"].get("transfer_on_drop", {})
		var caster: Variant = a["instance"].get("source")
		if tr.is_empty() or not (caster is Node) or caster.dead:
			continue
		var inst_id: Variant = a["instance"].get("params", {}).get("instance")
		var Sp: Variant = load("res://scripts/rules/spellcasting.gd")
		if inst_id == null or not Sp.instances.has(inst_id):
			continue
		var world: Dictionary = Sp.instances[inst_id]["world"]
		if not world.has("grid"):
			continue
		var grid: Node = world["grid"]
		var best: Node = null
		var best_d := 1 << 20
		for o: Node in grid.creatures():
			if o == target or o.dead or o.hp <= 0 or not caster.is_hostile_to(o) or not grid.can_see(caster, o):
				continue
			var dd: int = grid.distance_between(caster, o)
			if dd <= int(tr["range"]) and dd < best_d:
				best_d = dd
				best = o
		target.remove_condition(str(a["id"]))
		if best != null:
			best.apply_condition(str(a["id"]), int(a["instance"].get("turns_left", -1)), caster, a["instance"].get("params", {}).duplicate())
			Dice.log_text("%s → %s로 옮김" % [a["def"]["name"]["ko"], best.label()])


## 피해 굴림(판정 순서 7). 야만적 공격(턴당 1회 무기 피해 두 번 굴려 큰 쪽), 대형 무기 전투(1·2 → 3).
static func _roll_damage(attacker: Node, atk: Dictionary, parts: Array, res: Dictionary) -> Array:
	var gwf: bool = attacker.has_cap("reroll_low_damage_two_handed") and atk.get("weapon", false) \
		and atk.get("kind", "") == "melee" and (atk.get("two_handed", false) or "two_handed" in atk.get("properties", []))
	var times := 1
	if attacker.has_cap("weapon_damage_twice") and atk.get("weapon", false) and not attacker.turn.get("savage_used", false):
		attacker.turn["savage_used"] = true
		times = 2
	var best: Array = []
	var best_total := -1
	for t in times:
		var rolled: Array = []
		var total := 0
		for p: Dictionary in parts:
			var r := Dice.roll(p["dice"], "%s 피해" % atk.get("name", "공격"), res["crit"], 3 if gwf else 0)
			rolled.append({"amount": r["total"], "damage_type": p["damage_type"]})
			total += r["total"]
		if total > best_total:
			best_total = total
			best = rolled
	return best


## 행운(하플링): d20 테스트의 자연 1은 다시 굴려 새 값을 쓴다.
static func luck(c: Node, d: Dictionary) -> Dictionary:
	if d["natural"] == 1 and c != null and c.has_cap("reroll_natural_1"):
		var again := Dice.die(20)
		Dice.log_text("%s 행운: 1 → %d" % [c.label(), again])
		d["natural"] = again
	return d


## 성역(Sanctuary): 보호받는 대상을 공격하려면 지혜 내성, 실패하면 그 공격을 잃는다.
static func _sanctuary(attacker: Node, target: Node) -> String:
	for m in target.modifier_entries():
		var e: Dictionary = m["effect"]
		if e["type"] == "modify" and e["stat"] == "sanctuary":
			var s := saving_throw(attacker, "wis", int(e["dc"]), {"source": target})
			if not s["success"]:
				return "성역: 공격을 잃었다"
	return ""


## 거울 분신(Mirror Image): 명중하면 남은 분신마다 d6, 하나라도 3 이상이면 분신이 대신 맞는다.
## 공격자가 실명·진시야면 소용없다.
static func _mirror_image(attacker: Node, target: Node, res: Dictionary) -> void:
	var n: int = int(target.get_meta("mirror_images", 0))
	if n <= 0 or not res["hit"] or attacker.has_condition("blinded") or attacker.senses.has("truesight"):
		return
	for i in n:
		if Dice.die(6) >= 3:
			target.set_meta("mirror_images", n - 1)
			res["hit"] = false
			res["crit"] = false
			res["mirror_image"] = true
			Dice.log_text("%s의 분신이 대신 맞았다(남은 %d)" % [target.label(), n - 1])
			return


static func _mode_note(mode: int, rolls: Array) -> String:
	if mode > 0:
		return "(유리 %s)" % str(rolls)
	if mode < 0:
		return "(불리 %s)" % str(rolls)
	return ""


# ======================================================================
# 피해·회복 (판정 순서 8~10)
# ======================================================================

## 피해 수정 한 번: 보너스·배율 → 저항 → 취약(원문 순서). 저항과 취약이 함께 있으면 상쇄(4단계).
## 면역이면 0. floor_each=true면 정수 피해(절반은 내림), false면 미리보기 평균용 실수.
static func modify_amount(target: Node, amount: float, damage_type: String, multiplier: float = 1.0,
		floor_each: bool = true) -> float:
	if target.immune_to(damage_type):
		return 0.0
	var v := maxf(amount * multiplier, 0.0)
	if floor_each:
		v = floorf(v)
	var r: bool = target.resists(damage_type)
	var w: bool = target.vulnerable_to(damage_type)
	if r and not w:
		v = floorf(v / 2.0) if floor_each else v / 2.0
	elif w and not r:
		v *= 2.0
	return v


## 피해를 적용한다. parts: [{"amount": int, "damage_type": String, "multiplier": float(선택)}]
## opts: {"crit": bool, "attacker": Node, "in_combat": bool}
## 결과: {"total", "by_type", "temp_absorbed", "hp_lost", "dropped", "died", "concentration"}
static func apply_damage(target: Node, parts: Array, opts: Dictionary = {}) -> Dictionary:
	var out := {"total": 0, "by_type": {}, "temp_absorbed": 0, "hp_lost": 0, "dropped": false,
		"died": false, "concentration": {}}
	if target.dead:
		return out
	# 8. 피해 수정(유형별로 모아서 한 번에 — 저항은 한 피해에 한 번만 적용된다)
	# 배율(내성 성공 절반 등)은 부분마다 먼저 적용하고 내림, 그다음 유형별로 합쳐 저항·취약.
	var raw := {}
	for p: Dictionary in parts:
		var t: String = p["damage_type"]
		var amount := maxi(floori(int(p["amount"]) * float(p.get("multiplier", 1.0))), 0)
		raw[t] = raw.get(t, 0) + amount
	var total := 0
	for t: String in raw.keys():
		var v := int(modify_amount(target, raw[t], t, 1.0, true))
		out["by_type"][t] = v
		total += v
	out["total"] = total
	target.set_meta("last_damage_total", total)
	target.set_meta("last_damage_types", out["by_type"].keys())
	for t: String in out["by_type"].keys():
		if t in ["acid", "fire"] and out["by_type"][t] > 0:
			target.set_meta("regen_blocked", true)  # 트롤 재생 막힘(다음 턴)
	if total <= 0:
		return out
	# 9. 적용: 임시 HP 먼저
	var was_down: bool = target.hp == 0
	var absorbed := mini(target.temp_hp, total)
	target.temp_hp -= absorbed
	var rest := total - absorbed
	out["temp_absorbed"] = absorbed
	var info := {"target": target, "amount": total, "opts": opts, "result": out}
	if was_down and target.has_meta("regen_down"):
		pass  # 재생으로 쓰러져 있는 트롤: 턴 시작에 재생 여부로 결정
	elif was_down:
		_damage_while_down(target, total, opts, out)
	else:
		var before: int = target.hp
		target.hp = maxi(before - rest, 0)
		out["hp_lost"] = before - target.hp
	var parts_text: PackedStringArray = []
	for t: String in out["by_type"].keys():
		parts_text.append("%s %d" % [t, out["by_type"][t]])
	Dice.log_text("%s 피해 %d (%s) → HP %d/%d%s" % [target.label(), total, ", ".join(parts_text), target.hp,
		target.hp_max, " (임시 HP %d 흡수)" % absorbed if absorbed > 0 else ""])
	EventBus.on_damage_taken.emit(info)
	# 피해를 받으면 끝나는 상태(Sleep·Hypnotic Pattern — params.ends_on_damage)
	for cond in target.conditions.duplicate():
		if cond.get("params", {}).get("ends_on_damage", false):
			target.remove_condition(cond["id"])
	# 피해를 받으면 유리로 다시 내성(Hideous Laughter — params.save_on_damage)
	for cond in target.conditions.duplicate():
		var sod: Dictionary = cond.get("params", {}).get("save_on_damage", {})
		if not sod.is_empty() and target.conditions.has(cond) and not target.dead:
			var s := saving_throw(target, sod["ability"], int(sod["dc"]), {"advantage": ["피해"]})
			if s["success"]:
				var id: Variant = cond["params"].get("instance")
				for other in target.conditions.duplicate():
					if other.get("params", {}).get("instance") == id:
						target.remove_condition(other["id"])
	# 집중 유지 내성(피해를 받으면 — 임시 HP가 막아도 받은 것이다)
	if not target.concentration.is_empty() and target.hp > 0:
		out["concentration"] = concentration_check(target, total)
	# 10. 0 HP
	if not was_down and target.hp == 0:
		_hp_zero(target, rest - out["hp_lost"], opts, out)
	return out


## 0 HP가 되었을 때(on_hp_zero). 리스너가 info["prevented"] = true로 막을 수 있다(끈질긴 인내 등).
static func _hp_zero(target: Node, remainder: int, opts: Dictionary, out: Dictionary) -> void:
	var info := {"creature": target, "remainder": remainder, "opts": opts, "prevented": false}
	EventBus.on_hp_zero.emit(info)
	if not info["prevented"]:
		Features.hook("on_hp_zero", target, {"res": info})
	if info["prevented"] or target.hp > 0:
		return
	_transfer_on_drop(target)
	_dark_ones_blessing(target, opts)
	if target.has_meta("beast_form"):
		load("res://scripts/rules/effects/wild_shape.gd").revert(target)  # 0 HP(무력화)면 야생 변신이 풀린다
	if not target.is_player_character:
		_die(target, "몬스터는 0 HP에서 즉사")
	elif remainder >= target.hp_max:
		_die(target, "즉사(남은 피해 %d ≥ 최대 HP %d)" % [remainder, target.hp_max])
	else:
		target.death_saves = {"successes": 0, "failures": 0}
		target.stable = not opts.get("in_combat", true)  # 전투 밖 쓰러짐은 안정 상태(7단계 결정 2)
		target.apply_condition("unconscious", -1, "hp_zero")
		out["dropped"] = true
		Dice.log_text("%s 쓰러짐%s" % [target.label(), "(안정)" if target.stable else ""])
	out["died"] = target.dead


## 0 HP에서 피해: 사망 내성 실패 1회, 치명타면 2회. 최대 HP 이상이면 사망. 안정 상태는 풀린다.
static func _damage_while_down(target: Node, total: int, opts: Dictionary, out: Dictionary) -> void:
	target.stable = false
	if total >= target.hp_max:
		_die(target, "쓰러진 상태에서 최대 HP 이상 피해")
	else:
		_add_death_failures(target, 2 if opts.get("crit", false) else 1)
	out["died"] = target.dead


static func _add_death_failures(target: Node, n: int) -> void:
	target.death_saves["failures"] += n
	if target.death_saves["failures"] >= 3:
		_die(target, "사망 내성 실패 3회")


static func _die(target: Node, reason: String) -> void:
	target.hp = 0
	target.dead = true
	target.stable = false
	target.break_concentration("사망")
	Dice.log_text("%s 사망: %s" % [target.label(), reason])


## 회복. 0 HP였다면 일어난다(무의식 해제, 사망 내성 초기화). 넘어짐은 남는다(원문 무의식).
## 결과: 실제 회복량.
static func heal(target: Node, amount: int, source: Variant = null) -> int:
	if target.dead or amount <= 0:
		return 0
	var before: int = target.hp
	target.hp = mini(target.hp + amount, target.hp_max)
	var gained: int = target.hp - before
	if before == 0 and target.hp > 0:
		target.remove_condition("unconscious")
		target.death_saves = {"successes": 0, "failures": 0}
		target.stable = false
	Dice.log_text("%s 회복 %d → HP %d/%d" % [target.label(), gained, target.hp, target.hp_max])
	EventBus.on_heal.emit({"target": target, "amount": gained, "source": source})
	return gained


## 임시 HP는 더하지 않고 큰 쪽을 남긴다(원문, 7단계).
static func grant_temp_hp(target: Node, amount: int) -> void:
	target.temp_hp = maxi(target.temp_hp, amount)


# ======================================================================
# 내성·능력 판정
# ======================================================================

## 내성 굴림. opts: {"bonus": int, "advantage": [], "disadvantage": [],
##   "natural_rules": bool(대화 중 내성·집중 유지 내성만 true — 2단계 결정 1), "source": Node}
## 결과: {"success", "natural", "total", "dc", "mode", "auto"}
static func saving_throw(creature: Node, ability: String, dc: int, opts: Dictionary = {}) -> Dictionary:
	var src: Variant = opts.get("source")
	if src is Node and src.has_condition("raging") and src.is_hostile_to(creature):
		src.turn["rage_kept"] = true  # 분노 연장: 적에게 내성을 강요했다
	var res := _save_setup(creature, ability, dc, opts)
	if res["auto"]:
		Dice.log_text("%s %s 내성 자동 실패 vs DC %d" % [creature.label(), ability, dc])
		return res
	EventBus.on_save.emit(res)
	res["mode"] = mode_of(res["advantage"], res["disadvantage"])
	var d := luck(creature, Dice.d20(res["mode"], "%s %s 내성" % [creature.label(), ability]))
	res["natural"] = d["natural"]
	res["total"] = d["natural"] + res["bonus"] + roll_bonus_dice(creature, "saving_throw")
	res["success"] = res["total"] >= dc
	if not res["success"]:
		res["total"] += inspire(creature)
		res["success"] = res["total"] >= dc
	if opts.get("natural_rules", false):
		if d["natural"] == 20:
			res["success"] = true
		elif d["natural"] == 1:
			res["success"] = false
	res["phase"] = "after"
	EventBus.on_save.emit(res)
	Dice.log_text("%s %s 내성%s: %d + %d = %d vs DC %d → %s" % [creature.label(), ability,
		_mode_note(res["mode"], d["rolls"]), res["natural"], res["bonus"], res["total"], dc,
		"성공" if res["success"] else "실패"])
	return res


## 내성 실패 확률(굴림 없음). 일반 내성은 자연 20·1이 없어 0~100%(2단계 결정 1).
static func preview_save_fail(creature: Node, ability: String, dc: int, opts: Dictionary = {}) -> float:
	var res := _save_setup(creature, ability, dc, opts)
	if res["auto"]:
		return 1.0
	var lo := 0.05 if opts.get("natural_rules", false) else 0.0
	var p_success := clampf((21.0 - (dc - res["bonus"] - avg_bonus_dice(creature, "saving_throw"))) / 20.0, lo, 1.0 - lo)
	return 1.0 - apply_mode(p_success, mode_of(res["advantage"], res["disadvantage"]))


static func _save_setup(creature: Node, ability: String, dc: int, opts: Dictionary) -> Dictionary:
	var res := {"creature": creature, "ability": ability, "dc": dc, "phase": "before",
		"bonus": creature.save_bonus(ability) + int(opts.get("bonus", 0)),
		"advantage": opts.get("advantage", []).duplicate(), "disadvantage": opts.get("disadvantage", []).duplicate(),
		"auto": false, "success": false, "natural": 0, "total": 0, "mode": 0}
	if creature.auto_fails_save(ability):
		res["auto"] = true
		return res
	for m in creature.modifier_entries():
		_add_adv(m, "save", "self", creature, opts.get("source"), res, ability)
	for cid: String in opts.get("against_conditions", []):
		if cid in creature.save_advantage_vs:
			res["advantage"].append("%s 내성 유리" % cid)
	if ability in creature.save_advantage_abilities:
		res["advantage"].append("%s 내성 유리" % ability)
	return res


## 집중 유지 내성: 건강, DC = max(10, 피해 절반 내림), 최대 30. 자연 20·1 적용(2단계 결정 1).
static func concentration_check(creature: Node, damage: int) -> Dictionary:
	var dc := clampi(maxi(CONCENTRATION_DC_MIN, damage / 2), CONCENTRATION_DC_MIN, CONCENTRATION_DC_MAX)
	var copts := {"natural_rules": true}
	if creature.has_cap("eldritch_mind") or bool(creature.concentration.get("advantage", false)):
		copts["advantage"] = ["집중 유리"]  # 섬뜩한 정신(워락 영창)·연장된 주문
	var res := saving_throw(creature, "con", dc, copts)
	if not res["success"]:
		creature.break_concentration("집중 유지 내성 실패")
	return res


## 능력 판정. opts: {"skill": String, "bonus": int, "advantage": [], "disadvantage": [],
##   "requires_sight": bool, "social": bool, "other": Node}
## 자연 20 자동 성공, 자연 1 자동 실패(2단계 공통 처리 규칙 1).
static func ability_check(creature: Node, ability: String, dc: int, opts: Dictionary = {}) -> Dictionary:
	var res := {"creature": creature, "ability": ability, "dc": dc, "auto": false,
		"bonus": creature.ability_mod(ability) + _skill_bonus(creature, str(opts.get("skill", ""))) + int(opts.get("bonus", 0)),
		"advantage": opts.get("advantage", []).duplicate(), "disadvantage": opts.get("disadvantage", []).duplicate(),
		"success": false, "natural": 0, "total": 0, "mode": 0, "ctx": {}, "skill": str(opts.get("skill", ""))}
	if str(opts.get("skill", "")) == "stealth":
		var armor := str(creature.get_meta("armor", ""))
		if armor != "" and bool(RulesDB.get_entry("armor", armor).get("stealth_disadvantage", false)):
			res["disadvantage"].append("갑옷(은신 불리)")  # SRD 갑옷 표 Stealth Disadvantage
	if opts.get("requires_sight", false) and creature.has_flag("fails_sight_checks"):
		res["auto"] = true
	else:
		for m in creature.modifier_entries():
			_add_adv(m, "ability_check", "self", creature, opts.get("other"), res, ability)  # 능력 한정(분노: 근력 판정)
		var other: Node = opts.get("other")
		if other != null and opts.get("social", false):
			for m in other.modifier_entries():
				if m["effect"].get("check", "") == "social":
					_add_adv(m, "ability_check", "against", other, creature, res)
		res["mode"] = mode_of(res["advantage"], res["disadvantage"])
		var d := luck(creature, Dice.d20(res["mode"], "%s %s 판정" % [creature.label(), ability]))
		res["natural"] = d["natural"]
		res["total"] = d["natural"] + res["bonus"]
		res["success"] = d["natural"] == 20 or (d["natural"] != 1 and res["total"] >= dc)
		if not res["success"] and d["natural"] != 1:
			res["total"] += inspire(creature)
			res["success"] = res["total"] >= dc
	Dice.log_text("%s %s 판정: %s vs DC %d → %s" % [creature.label(), ability,
		"자동 실패" if res["auto"] else "%d + %d = %d" % [res["natural"], res["bonus"], res["total"]],
		dc, "성공" if res["success"] else "실패"])
	if not res["success"]:
		EventBus.on_check_failed.emit(res)
		if not opts.get("visible", false):
			Features.hook("on_check_failed", creature, {"res": res})  # 숨은 판정은 자동(전술적 판단 등)
	return res


## 내성을 강요하는 효과(주문 등). 모든 대상의 내성을 먼저 굴리고, 피해 주사위는 모든 대상에
## 한 번만 굴린다(원문 Damage against Multiple Targets).
## check: {"ability", "dc"}; fail/success: 효과 목록(damage는 "scale"로 배율, apply_condition).
## 결과: 대상마다 {"target", "save", "damage"}.
static func save_effect(targets: Array, check: Dictionary, fail: Array, success: Array = [],
		opts: Dictionary = {}) -> Array:
	var rolled: Dictionary = opts.get("rolled", {})  # 바깥에서 굴린 값을 함께 쓰려면 넘긴다(칸 반응 등)
	var out: Array = []
	var saves: Array = []
	var so := opts.duplicate()
	so["against_conditions"] = fail.filter(func(e: Dictionary) -> bool: return e["type"] == "apply_condition").map(
		func(e: Dictionary) -> String: return e["id"])
	var careful: Array = opts.get("careful", [])  # 신중한 주문(소서러): 고른 아군은 자동 성공, 절반 피해도 받지 않는다
	for t: Node in targets:
		if t in careful:
			saves.append({"success": true, "auto": true, "careful": true})
			continue
		# 내성 없는 효과(함정 등): check가 비면 굴리지 않고 실패로 친다
		saves.append({"success": false, "auto": true} if check.is_empty() else saving_throw(t, check["ability"], int(check["dc"]), so))
	for i in targets.size():
		var t: Node = targets[i]
		var s: Dictionary = saves[i]
		var effects: Array = success if s["success"] else fail
		if s.get("careful", false):
			effects = effects.filter(func(e: Dictionary) -> bool: return e["type"] != "damage")
		var parts: Array = []
		for e: Dictionary in effects:
			match e["type"]:
				"damage":
					var key: String = e["dice"] + "|" + e["damage_type"]
					if not rolled.has(key):
						rolled[key] = Dice.roll(e["dice"], "효과 피해")["total"]
					parts.append({"amount": rolled[key], "damage_type": e["damage_type"],
						"multiplier": float(e.get("scale", 1.0))})
				"apply_condition":
					var cp: Dictionary = opts.get("condition_params", {}).duplicate()
					if e.get("escape", false):
						cp["escape_dc"] = int(check.get("dc", 10))  # 행동으로 판정해 풀 수 있다(Entangle 등)
					t.apply_condition(e["id"], int(e.get("turns", opts.get("duration", 0))), opts.get("source"), cp)
		var dmg := apply_damage(t, parts, opts) if not parts.is_empty() else {}
		out.append({"target": t, "save": s, "damage": dmg})
	return out


# ======================================================================
# 턴 시작·사망 내성
# ======================================================================

## 턴 시작 처리(3단계 턴 순서 2): 턴 시작 효과(연소 등) → 사망 내성.
## 반응 회복과 재충전은 3단계 TurnManager가 맡는다.
static func start_turn(creature: Node, ctx: Dictionary = {}) -> void:
	EventBus.on_turn_start.emit(creature)
	var regen: Dictionary = creature.feature_data.get("regeneration", {})
	if not regen.is_empty() and not creature.dead:
		if creature.get_meta("regen_blocked", false):
			creature.set_meta("regen_blocked", false)
			if creature.get_meta("regen_down", false):
				_die(creature, "재생하지 못하고 0 HP로 턴 시작")
				return
		elif creature.hp < creature.hp_max:
			heal(creature, int(regen.get("amount", 15)), "regeneration")
			if creature.get_meta("regen_down", false):
				creature.set_meta("regen_down", false)
	for a in creature.active_conditions():
		var parts: Array = []
		for e: Dictionary in a["def"].get("hooks", {}).get("on_turn_start", []):
			if e["type"] == "damage":
				var r := Dice.roll(str(a["instance"].get("params", {}).get("dice", e["dice"])), "%s(%s)" % [a["id"], creature.label()])
				parts.append({"amount": r["total"], "damage_type": e["damage_type"]})
			elif e["type"] == "temp_hp" and e.get("amount", "") == "source_spell_mod":
				var src: Variant = a["instance"].get("source")
				if src is Node:  # 영웅심: 턴 시작마다 시전자 주문 능력 수정치만큼 임시 HP
					grant_temp_hp(creature, maxi(1, load("res://scripts/rules/spellcasting.gd").spell_mod(src)))
		if not parts.is_empty():
			apply_damage(creature, parts, ctx)
	if creature.is_player_character and creature.is_down() and not creature.stable:
		death_save(creature, int(ctx.get("death_save_bonus", 0)))


## 사망 내성: d20 ≥ 10 성공. 성공 3회 안정, 실패 3회 사망, 자연 20 HP 1, 자연 1 실패 2회(원문, 7단계).
static func death_save(creature: Node, bonus: int = 0) -> Dictionary:
	var dres := {"advantage": [], "disadvantage": [], "distance": 1}
	for m in creature.modifier_entries():
		_add_adv(m, "death_save", "self", creature, null, dres)
	var d := luck(creature, Dice.d20(mode_of(dres["advantage"], dres["disadvantage"]), "%s 사망 내성" % creature.label()))
	var n: int = d["natural"]
	var res := {"natural": n, "total": n + bonus, "result": ""}
	if n == 20:
		heal(creature, 1, "death_save")
		res["result"] = "회복"
	elif n == 1:
		_add_death_failures(creature, 2)
		res["result"] = "실패 2"
	elif n + bonus >= DEATH_SAVE_DC:
		creature.death_saves["successes"] += 1
		res["result"] = "성공"
		if creature.death_saves["successes"] >= 3:
			creature.stable = true
			creature.death_saves = {"successes": 0, "failures": 0}
			res["result"] = "안정"
	else:
		_add_death_failures(creature, 1)
		res["result"] = "실패"
	if creature.dead:
		res["result"] = "사망"
	Dice.log_text("%s 사망 내성: %d + %d = %d vs DC %d → %s" % [creature.label(), n, bonus, n + bonus,
		DEATH_SAVE_DC, res["result"]])
	return res
