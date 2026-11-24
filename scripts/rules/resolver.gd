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
const Auras := preload("res://scripts/rules/auras.gd")

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
	res["crit_threshold"] = crit_threshold_for(attacker, target, atk)
	var bonus_dice := roll_bonus_dice(attacker, "attack_roll")
	res["bonus_dice"] = bonus_dice
	res["total"] = res["natural"] + res["attack_bonus"] + bonus_dice
	_decide_hit(res)
	if not res["hit"] and res["natural"] != 1:
		res["total"] += inspire(attacker)  # 바드의 영감: 실패한 d20 시험에 주사위를 더한다
		_decide_hit(res)
	if not res["hit"] and heroic(attacker):
		var d2 := luck(attacker, Dice.d20(res["mode"], "%s 공격(영웅적 영감)" % attacker.label()))
		res["rolls"] = d2["rolls"]
		res["natural"] = d2["natural"]
		res["total"] = res["natural"] + res["attack_bonus"] + bonus_dice
		_decide_hit(res)
	if not res["hit"] and res["natural"] != 1:
		Features.hook("on_attack_missed", attacker, {"res": res})  # 비할 데 없는 기술(지식 학파 14레벨) — 스크립트가 total을 고친다
		_decide_hit(res)
	if not res["hit"] and res["natural"] != 1 and attacker.has_cap("precision_attack") and atk.get("weapon", false) \
			and str(attacker.options.get("wa_m_precision_attack", "on")) == "on" and attacker.resource("superiority_dice") > 0:
		var pdie: String = load("res://scripts/rules/actions.gd").special_die(attacker, "superiority_dice")
		if res["total"] + int(pdie.get_slice("d", 1)) >= res["ac"] + res["ac_bonus"]:
			attacker.spend_resource("superiority_dice")  # 정밀 공격(기법): 빗나가면 우월 주사위를 명중 굴림에
			var pr: int = Dice.roll(pdie, "정밀 공격")["total"]
			res["total"] += pr
			_decide_hit(res)
	if not res["hit"] and res["natural"] != 1 and attacker.has_cap("guided_strike") and str(attacker.options.get("guided_strike", "on")) == "on" \
			and attacker.resource("channel_divinity") > 0 and res["total"] + 10 >= res["ac"] + res["ac_bonus"]:
		attacker.spend_resource("channel_divinity")  # 인도된 일격(전쟁 영역): 신성 변환으로 빗나간 공격 +10
		res["total"] += 10
		Dice.log_text("%s 인도된 일격: +10" % attacker.label())
		_decide_hit(res)
	if not res["hit"]:
		var rq0: Node = EventBus.reaction_queue
		if rq0 != null and is_instance_valid(rq0):
			rq0.miss_bonus(res)  # 전쟁 신의 축복(반응)
			_decide_hit(res)
	if not res["hit"] and lucky(attacker, "공격"):
		var nat := Dice.die(20)
		if nat > int(res["natural"]):  # 행운의 별: 다시 굴려 좋은 쪽(유리)
			res["natural"] = nat
			res["total"] = nat + res["attack_bonus"] + bonus_dice
			_decide_hit(res)
	if res["hit"] and attacker.is_hostile_to(target) and lucky(target, "적 공격 다시"):
		var nat2 := Dice.die(20)  # 행운의 별: 나를 맞힌 적의 공격을 다시 굴리게 한다(새 값)
		res["natural"] = nat2
		res["total"] = nat2 + res["attack_bonus"] + bonus_dice
		_decide_hit(res)
	# 받는 쪽의 '다음 공격을 받으면 사라지는' 수정치(Guiding Bolt)
	for m in target.extra_modifiers.duplicate():
		if m.get("consume_on_attacked", false):
			target.extra_modifiers.erase(m)
	for a in target.active_conditions():
		if a["def"].get("ends_on_attacked", false):
			target.remove_condition(str(a["id"]))  # 주의 산만: 공격 한 번이면 풀린다
	# 공격하면 끝나는 상태(Invisibility·Sanctuary — params.ends_on_attack)
	for cond in attacker.conditions.duplicate():
		if cond.get("params", {}).get("ends_on_attack", false) or RulesDB.get_entry("condition", str(cond["id"])).get("ends_on_attack", false):
			attacker.remove_condition(cond["id"])
	# 다음 공격 한 번에만 붙는 수정치(Sap·Vex 등)는 굴림에 쓰이면 사라진다.
	for m in attacker.extra_modifiers.duplicate():
		if m.get("consume_on_attack", false) and (m.get("target_only") == null or m.get("target_only") == target):
			attacker.extra_modifiers.erase(m)
	# 숨기로 얻은 투명은 공격 굴림을 하면 풀린다(원문 Hide, 5단계 은신 공격).
	# 최상급 은신(능력 태그 stealth_attack, 설정 켬): 급소 공격 주사위 1개를 쓰면 숨기가 풀리지 않는다 — 명중 처리 뒤에 정한다.
	var hide: Dictionary = attacker.condition_instance("invisible")
	var hidden: bool = not hide.is_empty() and hide["source"] is String and hide["source"] == "hide"
	var keep_hide: bool = hidden and attacker.has_cap("stealth_attack") and str(attacker.options.get("supreme_sneak", "on")) == "on"
	if hidden and not keep_hide:
		attacker.remove_condition("invisible")
	_portent_attack(res)
	# 5. 명중 직후 반응(Shield 등)
	EventBus.on_after_attack_roll.emit(res)
	_decide_hit(res)
	_mirror_image(attacker, target, res)
	# 6. 명중 결과
	if res["hit"] and not res["crit"] and target.auto_crit_against_within(res["distance"]):
		res["crit"] = true
		res["auto_crit"] = true
	if res["hit"] and not res["crit"] and attacker.has_cap("assassinate") and target.has_condition("surprised"):
		res["crit"] = true  # 암살: 기습당한 생물에게 명중하면 치명타
	if res["hit"]:
		EventBus.on_hit.emit(res)
		_retaliate(attacker, target, atk, res)
		Features.hook("on_hit", attacker, {"res": res})
		Features.hook("on_hit", target, {"res": res})
		if attacker.has_cap("eldritch_strike") and atk.get("weapon", false):
			target.set_meta("eldritch_strike", attacker)
		_hit_riders(attacker, target, atk, res)
		if res["crit"]:
			EventBus.on_crit.emit(res)
			if attacker.has_cap("crit_free_move"):
				attacker.turn["free_move_no_oa"] = maxi(int(attacker.turn.get("free_move_no_oa", 0)), attacker.speed() / 2)
	else:
		EventBus.on_miss.emit(res)
	if keep_hide and not res.get("stealth_attack", false):
		attacker.remove_condition("invisible")
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
		if atk.get("weapon", false) and str(atk.get("ability", "")) == "str":
			for m in attacker.modifier_entries():
				if m["effect"]["type"] == "modify" and m["effect"]["stat"] == "str_weapon_damage":
					mult *= float(m["effect"].get("multiply", 1.0))  # 무력함(비전 사격): 근력 무기 피해 절반
		if mult != 1.0:
			for r: Dictionary in rolled:
				r["multiplier"] = mult
		if target.has_cap("heavy_armor_damage_reduction") and _wearing_heavy(target) and _nonmagical_attack(atk):
			var ham := 3  # 중갑 숙달: 마법이 아닌 공격의 타격·관통·참격 −3
			for r: Dictionary in rolled:
				if ham > 0 and str(r["damage_type"]) in ["bludgeoning", "piercing", "slashing"]:
					var k0 := mini(ham, int(r["amount"]))
					r["amount"] = int(r["amount"]) - k0
					ham -= k0
		var cut := int(res.get("damage_reduction", 0))  # 공격 피해 줄이기(몽크 공격 쳐내기)
		for r: Dictionary in rolled:
			if cut <= 0:
				break
			var k := mini(cut, int(r["amount"]))
			r["amount"] = int(r["amount"]) - k
			cut -= k
		res["damage"] = apply_damage(target, rolled, {"crit": res["crit"], "attacker": attacker,
			"in_combat": ctx.get("in_combat", true)})
		if attacker.has_cap("bonus_attack_on_crit_kill") and atk.get("weapon", false) and str(atk.get("kind", "")) == "melee" \
				and (res["crit"] or target.hp == 0) and not attacker.turn.get("bonus_attack_used", false):
			attacker.turn["bonus_attack_ready"] = true  # 대형 무기 강타: 치명타·처치 → 보너스 행동 공격
	return res


## 굴림 없는 미리보기(8단계 판정 순서 2, 2단계 공통 처리 규칙 2).
## 결과: {"valid", "reason", "hit_chance", "crit_chance", "mode", "attack_bonus", "ac",
##        "damage": {"min", "max", "avg"}(명중 시, 저항·취약 반영)}
static func preview_attack(attacker: Node, target: Node, atk: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var res := _attack_setup(attacker, target, atk, ctx, true)
	if not res["valid"]:
		return res
	var thr := crit_threshold_for(attacker, target, atk)
	var pc := clampf((21.0 - thr) / 20.0, 0.05, 1.0)  # 치명타 눈(챔피언 19 등)은 늘 명중
	var p := maxf(hit_probability(target.ac() + res["ac_bonus"], res["attack_bonus"] + avg_bonus_dice(attacker, "attack_roll")), pc)
	res["hit_chance"] = apply_mode(p, res["mode"])
	res["crit_chance"] = apply_mode(pc, res["mode"])
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


## 치명타 눈: 무기 공격은 생물의 crit_threshold(챔피언 등), 주문 공격은 20 − 주문 저격, 주술검사의 저주 −1.
static func crit_threshold_for(attacker: Node, target: Node, atk: Dictionary) -> int:
	var thr: int = attacker.crit_threshold if atk.get("weapon", false) else 20
	if atk.has("spell"):
		thr = 20 - attacker.cap_count("spell_crit_minus_1")  # 주문 저격: 주문 공격 치명타 눈 −1(겹친다)
	if target.condition_instance("hexblades_curse").get("source") == attacker:
		thr -= 1  # 주술검사의 저주: 치명타 범위 −1
	return thr


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
		"advantage": [], "disadvantage": [], "attack_bonus": int(atk.get("bonus", 0)) + int(ctx.get("attack_add", 0)),
		"ac": target.ac(), "ac_bonus": int(ctx.get("ac_add", 0)), "hit": false, "crit": false, "auto_crit": false,
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
	# 근접 위협(BG3 Threatened): 원거리 공격 굴림은 모두 — 무기·주문·스크립트 주문을 한곳에서(이미 넣었으면 그대로)
	if str(atk.get("kind", "")) == "ranged" and not "근접 위협" in res["disadvantage"] and not ctx.get("ignore_threat", false):
		var rq: Node = EventBus.reaction_queue
		if rq != null and is_instance_valid(rq) and rq.world.has("grid") and rq.world["grid"].creatures().has(attacker) \
				and load("res://scripts/rules/combat.gd").is_threatened(rq.world, attacker):
			res["disadvantage"].append("근접 위협")
	EventBus.on_before_attack_roll.emit(res)
	_brutal_strike_setup(attacker, atk, res, preview)
	if not preview:
		drunkards_luck(attacker, res)
		_tides(attacker, res)
	res["mode"] = mode_of(res["advantage"], res["disadvantage"])
	return res


## 상태 retaliate {dice, damage_type}(화염 방패): 1칸 안 생물이 근접 공격으로 나를 맞히면 그 생물이 피해를 받는다.
static func _retaliate(attacker: Node, target: Node, atk: Dictionary, res: Dictionary) -> void:
	if attacker == target:
		return
	var melee := str(atk.get("kind", "")) == "melee" and int(res.get("distance", 1)) <= 1
	for a in target.active_conditions():
		var r: Dictionary = a["def"].get("retaliate", {})
		if r.is_empty() or not (melee or r.get("any_range", false)):
			continue  # any_range: 원거리로 맞혀도(야생 마법 — 마법 응징)
		if r.has("condition"):
			attacker.apply_condition(str(r["condition"]), int(r.get("turns", 1)), a["instance"].get("source"))  # 영감의 망토: 근접 공격자 매혹
			continue
		if r.get("while_temp_hp", false) and target.temp_hp <= 0:
			target.remove_condition(str(a["id"]))  # 서리 갑주: 임시 HP가 다 떨어지면 끝
			continue
		var n: int = Dice.roll(str(a["instance"].get("params", {}).get("retaliate_dice", r["dice"])), a["id"])["total"]
		apply_damage(attacker, [{"amount": n, "damage_type": str(r["damage_type"])}], {"attacker": target})


## 잔혹한 일격(능력 태그 brutal_strike — 바바리안 9레벨): 무모한 공격 중 턴의 근력 공격 하나에서 유리를 버리면(불리가 없을 때)
## 명중 시 +1d10과 효과 하나(설정: forceful 강타 — 3칸 밀고 속도 절반 기회 공격 없이 / hamstring 오금 — 속도 −3칸).
static func _brutal_strike_setup(attacker: Node, atk: Dictionary, res: Dictionary, preview: bool) -> void:
	var opt := str(attacker.options.get("brutal_strike", ""))
	if opt == "" or not attacker.has_cap("brutal_strike") or not attacker.turn.get("reckless", false) \
			or attacker.turn.get("brutal_used", false) or str(atk.get("ability", "")) != "str":
		return
	if res["advantage"].is_empty() or not res["disadvantage"].is_empty():
		return
	res["advantage"].clear()
	res["brutal_strike"] = opt
	if not preview:
		attacker.turn["brutal_used"] = true


static func _collect_attack_mods(attacker: Node, target: Node, res: Dictionary) -> void:
	var ctx: Dictionary = res["ctx"]
	for m in attacker.modifier_entries():
		_add_adv(m, "attack", "self", attacker, target, res, str(res.get("attack", {}).get("ability", "")))  # 능력 한정(무모한 공격: 근력)
	for m in target.modifier_entries():
		_add_adv(m, "attack", "against", target, attacker, res)
	res["advantage"].append_array(ctx.get("advantage", []))
	res["disadvantage"].append_array(ctx.get("disadvantage", []))
	if attacker.has_cap("assassinate") and target.has_meta("not_acted_yet"):
		res["advantage"].append("암살: 아직 행동하지 않은 대상")  # 암살자형: 전투에서 아직 턴을 갖지 않은 생물에게 유리
	if res.get("attack", {}).get("opportunity", false) and target.has_cap("escape_the_horde"):
		res["disadvantage"].append("무리 탈출")  # 사냥꾼 방어 전술(7레벨)
	var hd := int(ctx.get("height_diff", 0))
	if hd >= HIGH_GROUND_STEPS:
		res["attack_bonus"] += HIGH_GROUND_BONUS
		res["high_ground"] = HIGH_GROUND_BONUS
	elif hd <= -HIGH_GROUND_STEPS and not (attacker.has_cap("ss_low_ground") and res.get("attack", {}).get("weapon", false) \
			and str(res.get("attack", {}).get("kind", "")) == "ranged"):
		res["attack_bonus"] -= HIGH_GROUND_BONUS  # 저격수: 원거리 무기는 낮은 곳 −2 없음
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
		"other_not_source":
			if m["instance"].get("source") == other:
				return  # 허세: 나(건 생물) 아닌 생물을 노린 공격만 불리
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
	if res.get("forced_miss", false):
		res["hit"] = false  # 환영 분신·본능적 매혹: 이 공격은 빗나간다
		res["crit"] = false
		return
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
	if int(atk.get("flat_damage", 0)) != 0:
		parts.append({"dice": str(int(atk["flat_damage"])), "damage_type": atk["damage"][0]["damage_type"]})  # 강타·저격수 +10
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
	# 대상 상태 hit_against_damage(벌어진 상처 — 무기 액션): 맞힌 공격에 고정 피해
	for a in target.active_conditions():
		var had: Dictionary = a["def"].get("hit_against_damage", {})
		if not had.is_empty():
			res["extra_damage"].append({"dice": str(int(had["amount"])), "damage_type": str(had["damage_type"])})
	# 죽음의 손길(죽음 영역, 능력 태그 touch_of_death, 설정 켬): 근접 명중에 신성 변환 — 사령 5 + 클레릭 레벨 × 2
	if attacker.has_cap("touch_of_death") and str(atk.get("kind", "")) == "melee" and str(attacker.options.get("touch_of_death", "on")) == "on" \
			and attacker.resource("channel_divinity") > 0:
		attacker.spend_resource("channel_divinity")
		res["extra_damage"].append({"dice": str(5 + 2 * attacker.feature_level("touch_of_death")), "damage_type": "necrotic"})
	# 힘 모으기(무기 액션 자세 prepare): 이번 턴 근접 무기 명중마다 근력 수정치(최소 1)
	if attacker.turn.get("stance_prepare", false) and atk.get("weapon", false) and atk.get("kind", "") == "melee":
		res["extra_damage"].append({"dice": str(maxi(1, attacker.ability_mod("str"))), "damage_type": atk["damage"][0]["damage_type"]})
	for a in target.active_conditions():
		var src: Variant = a["instance"].get("source")
		if not (src is Node) or src != attacker:  # 출처가 글자(함정 등)이거나 다른 생물
			continue
		for e: Dictionary in a["def"].get("hooks", {}).get("on_hit_by_source", []):
			if e["type"] == "damage":
				res["extra_damage"].append({"dice": str(e["dice"]), "damage_type": e["damage_type"]})
				if attacker.has_cap("mark_spread") and not attacker.turn.get("mark_spread_used", false):
					_mark_spread(attacker, target, e)
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
				if caster is Node and caster.has_cap("bounty_hunter") and a["id"] == "ensnaring_ready":
					sopts["disadvantage"] = ["현상금 사냥꾼"]  # 선호하는 적: 현상금 사냥꾼(BG3)
				if e["save"].get("large_advantage", false) and str(target.size) in ["large", "huge", "gargantuan"]:
					sopts["advantage"] = ["큰 생물"]
				var sv := saving_throw(target, str(e["save"]["ability"]), dc, sopts)
				if not sv.get("success", false):
					_hit_save_fail(attacker, target, caster, e.get("on_fail", []), params)
			EventBus.on_weapon_hit.emit(res)
			if a["def"].get("consume_on_trigger", false):
				attacker.remove_condition(str(a["id"]))
		_stunning_strike(attacker, target, atk)
		_feature_hit_bonus(attacker, target, atk, res)
		if res["crit"] and attacker.has_cap("brutal_critical") and str(atk.get("kind", "")) == "melee" and str(atk.get("hand", "main")) != "off" and not atk["damage"].is_empty():
			# 잔혹한 치명타(바바리안 9레벨, BG3): 주 손 근접 무기·비무장 치명타에 피해 주사위 하나 더
			res["extra_damage"].append({"dice": str(atk["damage"][0]["dice"]).get_slice("+", 0).get_slice("-", 0).replace("2d", "1d"), "damage_type": atk["damage"][0]["damage_type"]})
		if res["crit"] and attacker.has_cap("savage_attacks") and atk.get("weapon", false) and str(atk.get("kind", "")) == "melee" and not atk["damage"].is_empty():
			# 야만적인 공격(하프오크, BG3): 근접 무기 치명타에 무기 주사위 하나 더(치명타 배로 굴린다)
			var d0 := str(atk["damage"][0]["dice"]).get_slice("+", 0).get_slice("-", 0)
			res["extra_damage"].append({"dice": d0, "damage_type": atk["damage"][0]["damage_type"]})
		var hc: Dictionary = target.condition_instance("hexblades_curse")
		if not hc.is_empty() and hc.get("source") == attacker:
			res["extra_damage"].append({"dice": str(attacker.proficiency_bonus), "damage_type": atk["damage"][0]["damage_type"]})  # 주술검사의 저주: 피해 + 숙련
		if attacker.has_cap("lifedrinker") and attacker.has_cap("pact_blade") and str(atk.get("kind", "")) == "melee" and atk.get("weapon", false) and str(atk.get("weapon_id", "")) != "unarmed":
			res["extra_damage"].append({"dice": str(maxi(1, attacker.ability_mod("cha"))), "damage_type": "necrotic"})  # 생명을 마시는 자(영창 12, BG3)
		if attacker.has_meta("bonus_damage") and int(attacker.get_meta("bonus_damage")) > 0:
			res["extra_damage"].append({"dice": str(attacker.get_meta("bonus_damage")), "damage_type": atk["damage"][0]["damage_type"]})  # 동료의 결속(야수 조련사)
		if atk.get("weapon", false) and str(atk.get("kind", "")) == "melee":
			var hate := Auras.melee_bonus(attacker)
			if hate > 0:
				res["extra_damage"].append({"dice": str(hate), "damage_type": atk["damage"][0]["damage_type"]})
		if attacker.has_cap("manifestation") and str(atk.get("weapon_id", "")) == "unarmed":
			# 발현(열린 손 6레벨, BG3): 비무장 명중 +1d4 + 지혜(설정 manifestation: body 사령·mind 정신·soul 광휘)
			var mt: String = {"body": "necrotic", "mind": "psychic", "soul": "radiant"}.get(str(attacker.options.get("manifestation", "body")), "necrotic")
			var wm: int = attacker.ability_mod("wis")
			res["extra_damage"].append({"dice": "1d4%+d" % wm if wm != 0 else "1d4", "damage_type": mt})
		if res.has("brutal_strike"):
			res["extra_damage"].append({"dice": "1d10", "damage_type": atk["damage"][0]["damage_type"]})
			_brutal_effect(attacker, target, str(res["brutal_strike"]))
		if attacker.has_cap("extra_damage_wounded") and target.hp < target.hp_max and not attacker.turn.get("wounded_bonus_used", false):
			attacker.turn["wounded_bonus_used"] = true
			res["extra_damage"].append({"dice": "1d8", "damage_type": atk["damage"][0]["damage_type"]})


## 무기 명중 훅 save의 실패 효과: apply_condition(turns, repeat_save — 없으면 주문 동안), push(칸, 시전자에게서).
static func _hit_save_fail(attacker: Node, target: Node, caster: Variant, list: Array, params: Dictionary) -> void:
	for f: Dictionary in list:
		match str(f["type"]):
			"apply_condition":
				var p := params.duplicate()
				if f.has("repeat_save") and caster is Node:
					p["repeat_save"] = {"ability": str(f["repeat_save"]["ability"]), "dc": load("res://scripts/rules/spellcasting.gd").spell_dc(caster)}
				target.apply_condition(str(f["id"]), int(f.get("turns", -1)), caster, p)
			"push":
				var rq: Node = EventBus.reaction_queue
				if rq != null and is_instance_valid(rq) and rq.world.has("grid") and not target.dead:
					load("res://scripts/rules/combat.gd")._push_up_to(rq.world, attacker, target, int(f["tiles"]))


static func _brutal_effect(attacker: Node, target: Node, opt: String) -> void:
	match opt:
		"forceful":
			var rq: Node = EventBus.reaction_queue
			if rq != null and is_instance_valid(rq) and rq.world.has("grid"):
				load("res://scripts/rules/combat.gd")._push_up_to(rq.world, attacker, target, 3)
			attacker.turn["free_move_no_oa"] = maxi(int(attacker.turn.get("free_move_no_oa", 0)), attacker.speed() / 2)
		"hamstring":
			for old in target.extra_modifiers.duplicate():
				if old.get("source") == "hamstring":
					target.extra_modifiers.erase(old)
			target.extra_modifiers.append({"effect": {"type": "modify", "stat": "speed_tiles", "add": -3},
				"source": "hamstring", "until_turn_start_of": attacker})


## 뛰어난 사냥꾼의 먹잇감(사냥꾼 11레벨): 턴당 1회 표식 추가 피해를 첫 대상 6칸 안의 보이는 다른 적에게도.
static func _mark_spread(attacker: Node, target: Node, e: Dictionary) -> void:
	var rq: Node = EventBus.reaction_queue
	if rq == null or not is_instance_valid(rq) or not rq.world.has("grid"):
		return
	var grid: Node = rq.world["grid"]
	var best: Node = null
	for o: Node in grid.creatures():
		if o == target or o.dead or not o.is_hostile_to(attacker) or grid.distance_between(o, target) > 6 or not grid.can_see(attacker, o):
			continue
		if best == null or grid.distance_between(o, target) < grid.distance_between(best, target):
			best = o
	if best == null:
		return
	attacker.turn["mark_spread_used"] = true
	apply_damage(best, [{"amount": Dice.roll(str(e["dice"]), "먹잇감 확산")["total"], "damage_type": str(e["damage_type"])}], {"attacker": attacker})


## 기능 부여 weapon_hit_bonus(신성한 일격·원초의 일격): 턴당 1회 무기 명중에 dice_by_level(기능의 클래스 레벨) 추가 피해.
## damage_types 중 대상이 면역·저항이 아닌 첫 종류(BG3식 자동 고르기).
static func _feature_hit_bonus(attacker: Node, target: Node, atk: Dictionary, res: Dictionary) -> void:
	for hb: Dictionary in attacker.get_meta("weapon_hit_bonus", []):
		var key := "hit_bonus_" + str(hb["feature"])
		if attacker.turn.get(key, false) and not hb.get("every_hit", false):
			continue
		if hb.get("melee_only", false) and str(atk.get("kind", "")) != "melee":
			continue  # 빛나는 일격(팔라딘 11레벨): 근접 무기·비무장 명중마다
		var dice := ""
		var best_lv := 0
		var lv: int = attacker.feature_level(str(hb["feature"]))
		for k: String in hb.get("dice_by_level", {}):
			if lv >= int(k) and int(k) >= best_lv:
				best_lv = int(k)
				dice = str(hb["dice_by_level"][k])
		if dice == "":
			continue
		var types: Array = hb.get("damage_types", ["radiant"])
		var dtype := str(types[0])
		for t: String in types:
			if not t in target.damage_immunities and not t in target.damage_resistances:
				dtype = t
				break
		attacker.turn[key] = true
		res["extra_damage"].append({"dice": dice, "damage_type": dtype})


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


## 대항 매혹(능력 태그 countercharm — 바드 7레벨): 자신 또는 6칸 안 생물이 매혹·공포를 거는 효과의 내성에 실패하면
## 반응으로 유리하게 다시 굴린다(반응 설정을 따른다 — 자동 기본).
static func _countercharm(creature: Node, res: Dictionary, opts: Dictionary) -> void:
	var against: Array = opts.get("against_conditions", [])
	if not ("charmed" in against or "frightened" in against):
		return
	var rq: Node = EventBus.reaction_queue
	if rq == null or not is_instance_valid(rq) or not rq.world.has("grid"):
		return
	var grid: Node = rq.world["grid"]
	if not grid.creatures().has(creature):
		return
	for b: Node in grid.creatures():
		if b.dead or not b.has_cap("countercharm") or not b.can_react() or (b != creature and b.is_hostile_to(creature)):
			continue
		if b != creature and grid.distance_between(b, creature) > 6:
			continue
		Features.offer_reaction(b, "countercharm", {"target": creature}, func() -> void:
			b.turn["reaction"] = 0
			var d := luck(creature, Dice.d20(1, "%s 대항 매혹" % creature.label()))
			res["natural"] = d["natural"]
			res["total"] = int(d["natural"]) + int(res["bonus"]) + roll_bonus_dice(creature, "saving_throw")
			res["success"] = res["total"] >= int(res["dc"])
			Dice.log_text("%s 대항 매혹(%s): %d → %s" % [creature.label(), b.label(), res["total"], "성공" if res["success"] else "실패"]))
		return


## 영웅적 영감(상태 플래그 reroll_failed_d20 — 챔피언 영웅 전사): 실패한 d20 시험을 한 번 다시 굴린다(BG3식 자동). 썼으면 true.
static func _adjacent(a: Node, b: Node) -> bool:
	var rq: Node = EventBus.reaction_queue
	if rq == null or not is_instance_valid(rq) or not rq.world.has("grid"):
		return false
	var grid: Node = rq.world["grid"]
	return grid.creatures().has(a) and grid.creatures().has(b) and grid.distance_between(a, b) <= 1


## 행운의 별(능력 태그 lucky, 설정 켬): 행운 점수 1을 쓴다. 쓸 수 있으면 true.
static func lucky(c: Node, what: String) -> bool:
	if c == null or not c.has_cap("lucky") or str(c.options.get("lucky", "on")) != "on" or c.resource("luck_points") <= 0:
		return false
	c.spend_resource("luck_points")
	Dice.log_text("%s 행운의 별(%s)" % [c.label(), what])
	return true


static func heroic(c: Node) -> bool:
	for a in c.active_conditions():
		if a["def"].get("flags", {}).get("reroll_failed_d20", false):
			c.remove_condition(a["id"])
			Dice.log_text("%s: 영웅적 영감 — 다시 굴린다" % c.label())
			return true
	return false


## 믿음직한 재능(능력 태그 reliable_talent): 숙련 기능 판정의 d20 9 이하를 10으로(자연 1·20 판정은 원래 눈으로).
static func _reliable(c: Node, skill: String, natural: int) -> int:
	if skill != "" and c.skill_bonuses.has(skill) and c.has_cap("reliable_talent"):
		return maxi(natural, 10)
	return natural


## 레벨표에서 그 레벨의 값(가장 가까운 아래 레벨).
static func level_value(table: Dictionary, lv: int) -> int:
	var best := 0
	var best_lv := 0
	for k: String in table:
		if lv >= int(k) and int(k) >= best_lv:
			best_lv = int(k)
			best = int(table[k])
	return best


## 분노 피해 보너스(수정치 stat rage_damage의 합 — 분노 상태 데이터).
static func rage_bonus(c: Node) -> int:
	var table: Dictionary = c.feature_data.get("rage", {}).get("bonus_by_level", {})
	if not table.is_empty() and c.has_condition("raging"):
		return level_value(table, c.feature_level("rage"))  # 분노 피해 +2(1)·+3(9)·+4(16) — 바바리안 레벨
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
	var dice := str(inst.get("params", {}).get("hit_dice", e["dice"]))  # params.hit_dice: 건 쪽 수치(심문관의 힘 — 팔라딘 매력)
	for i in extra:
		dice += "+" + str(e.get("per_slot", ""))
	dice = dice.trim_suffix("+")
	var bonus: Dictionary = e.get("bonus_vs", {})
	if not bonus.is_empty() and str(target.creature_type) in bonus.get("types", []):
		dice += "+" + str(bonus["dice"])
	res["extra_damage"].append({"dice": dice, "damage_type": e["damage_type"]})
	var caster: Variant = inst.get("source")
	for f: Dictionary in e.get("apply", []):
		if f.has("if_hp_at_most") and target.hp - _expected_left(res) > int(f["if_hp_at_most"]):
			continue  # 추방 일격: 맞은 뒤 HP가 기준 이하일 때만
		var p := params.duplicate()
		if f.has("repeat_save") and caster is Node:
			p["repeat_save"] = {"ability": f["repeat_save"]["ability"], "dc": Sp.spell_dc(caster)}
		if f.has("dot_dice"):
			var dot := str(f["dot_dice"])
			for i in extra:
				dot += "+" + str(f["dot_dice"])
			p["dice"] = dot
		target.apply_condition(f["id"], int(f.get("turns", -1)), caster, p)


## 이번 명중에서 아직 들어가지 않은 피해의 평균(효과 조건 판정용 — 정확한 값은 굴린 뒤에야 안다).
static func _expected_left(res: Dictionary) -> int:
	var total := 0.0
	for d: Dictionary in res.get("attack", {}).get("damage", []) + res.get("extra_damage", []):
		total += float(DiceExpr.stats(str(d.get("dice", "0"))).get("avg", 0.0))
	return int(total)


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
			grant_temp_hp(o, maxi(1, o.ability_mod("cha") + o.feature_level("dark_ones_blessing")))
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
	if attacker.has_cap("melee_damage_advantage") and atk.get("weapon", false) and atk.get("kind", "") == "melee":
		times = 2  # 야만적 공격(BG3): 근접 무기 피해를 매번 두 번 굴려 큰 쪽
	if atk.get("weapon", false) and attacker.turn.get("stance_brace_" + str(atk.get("kind", "")), false):
		times += 1  # 버티기·조준 자세(무기 액션): 이번 턴 그 종류 무기 피해를 한 번 더 굴려 큰 쪽(야만적 공격과 겹친다 — BG3)
	var best: Array = []
	var best_total := -1
	for t in times:
		var rolled: Array = []
		var total := 0
		for p: Dictionary in parts:
			var r := Dice.roll(p["dice"], "%s 피해" % atk.get("name", "공격"), res["crit"],
				2 if atk.has("spell") and str(p["damage_type"]) in adept_types(attacker) else 0, 2 if gwf else 0)
			rolled.append({"amount": r["total"], "damage_type": p["damage_type"]})
			total += r["total"]
		if total > best_total:
			best_total = total
			best = rolled
	for i in best.size():
		if i < parts.size() and str(parts[i]["damage_type"]) in ["lightning", "thunder"] and destructive_max(attacker, str(parts[i]["damage_type"])):
			best[i]["amount"] = int(DiceExpr.stats(str(parts[i]["dice"]))["max"]) * (2 if res["crit"] else 1)
			break
	if atk.get("half_damage", false):
		for i in mini(atk.get("damage", []).size(), best.size()):
			best[i]["amount"] = int(best[i]["amount"]) / 2  # 휩쓸기(무기 액션): 무기 피해만 절반, 다른 추가 피해는 그대로
	return best


## 예지(예언학파, 능력 태그 portent — 반응 기능 portent, 반응은 쓰지 않음): 긴 휴식에 굴려 둔 d20(meta portent_values)으로
## 12칸 안 생물의 d20을 바꾼다. 자동: 적의 명중을 빗나감으로, 아군의 빗나감을 명중으로 바꿀 수 있는 가장 알맞은 눈을 쓴다.
static func _diviners(a: Node, b: Variant) -> Array:
	var rq: Node = EventBus.reaction_queue
	if rq == null or not is_instance_valid(rq) or not rq.world.has("grid") or EventBus.realtime:
		return []
	var grid: Node = rq.world["grid"]
	return grid.creatures().filter(func(o: Node) -> bool:
		return not o.dead and o.has_cap("portent") and o.resource("portent_dice") > 0 and not (o.get_meta("portent_values", []) as Array).is_empty() \
			and ((grid.creatures().has(a) and grid.distance_between(o, a) <= 12) or (b is Node and grid.creatures().has(b) and grid.distance_between(o, b) <= 12)))


static func _use_portent(o: Node, v: int, what: String) -> void:
	var vals: Array = o.get_meta("portent_values", []).duplicate()
	vals.erase(v)
	o.set_meta("portent_values", vals)
	o.spend_resource("portent_dice")
	Dice.log_text("%s 예지(%d): %s" % [o.label(), v, what])


static func _portent_attack(res: Dictionary) -> void:
	var attacker: Node = res["attacker"]
	var target: Node = res["target"]
	for o: Node in _diviners(attacker, target):
		var vals: Array = (o.get_meta("portent_values", []) as Array).duplicate()
		vals.sort()
		var need: int = int(res["ac"]) + int(res["ac_bonus"]) - (int(res["total"]) - int(res["natural"]))
		var pick := -1
		if o.is_hostile_to(attacker) and res["hit"] and not res["crit"]:
			for v: int in vals:
				if v < need and v != 20:
					pick = v  # 가장 큰 '빗나가는' 눈은 아끼지 않고 가장 작은 것을 쓴다
					break
		elif not o.is_hostile_to(attacker) and not res["hit"]:
			for v: int in vals:
				if v >= need and v != 1:
					pick = v
					break
		if pick < 0:
			continue
		var rq: Node = EventBus.reaction_queue
		if not rq.offer(o, "portent", {"attack": res}, func() -> void: pass):
			continue
		_use_portent(o, pick, "공격 굴림 → %d" % pick)
		res["total"] = int(res["total"]) - int(res["natural"]) + pick
		res["natural"] = pick
		_decide_hit(res)
		return


static func _portent_save(res: Dictionary, creature: Node, dc: int, src: Variant) -> void:
	if res.get("auto", false):
		return
	for o: Node in _diviners(creature, src):
		var vals: Array = (o.get_meta("portent_values", []) as Array).duplicate()
		vals.sort()
		var mod: int = int(res["total"]) - int(res["natural"])
		var pick := -1
		if not o.is_hostile_to(creature) and not res["success"]:
			for v: int in vals:
				if v + mod >= dc:
					pick = v
					break
		elif o.is_hostile_to(creature) and res["success"] and src is Node and not o.is_hostile_to(src):
			for v: int in vals:
				if v + mod < dc:
					pick = v
					break
		if pick < 0:
			continue
		var rq: Node = EventBus.reaction_queue
		if not rq.offer(o, "portent", {"save": res}, func() -> void: pass):
			continue
		_use_portent(o, pick, "내성 → %d" % pick)
		res["natural"] = pick
		res["total"] = pick + mod
		res["success"] = res["total"] >= dc
		return


## 비전 결계(방호학파, 능력 태그 arcane_ward — 자원 arcane_ward = 충전): 받는 피해를 충전만큼(최대 20) 막고 충전 1을 잃는다.
## 투사 결계(반응 trigger projected_ward): 6칸 안 아군이 피해를 받으면 반응으로 내 결계가 대신 막는다.
static func _arcane_ward(target: Node, total: int, out: Dictionary) -> int:
	if target.has_cap("arcane_ward") and target.resource("arcane_ward") > 0:
		var block := mini(total, mini(target.resource("arcane_ward"), 20))
		target.resources["arcane_ward"]["current"] = target.resource("arcane_ward") - 1
		out["ward_blocked"] = block
		Dice.log_text("%s 비전 결계: %d 막음" % [target.label(), block])
		return total - block
	var rq: Node = EventBus.reaction_queue
	if rq == null or not is_instance_valid(rq) or not rq.world.has("grid") or EventBus.realtime:
		return total
	var grid: Node = rq.world["grid"]
	if not grid.creatures().has(target):
		return total
	for o: Node in grid.creatures():
		if o == target or o.dead or o.is_hostile_to(target) or not o.can_react() or o.resource("arcane_ward") <= 0 or grid.distance_between(o, target) > 6:
			continue
		var fid: String = rq._trigger_feature(o, "projected_ward")
		if fid == "":
			continue
		var block2 := mini(total, mini(o.resource("arcane_ward"), 20))
		if rq.offer(o, fid, {"target": target}, func() -> void:
			o.turn["reaction"] = int(o.turn.get("reaction", 1)) - 1
			o.resources["arcane_ward"]["current"] = o.resource("arcane_ward") - 1
			Dice.log_text("%s 투사 결계: %s의 피해 %d 막음" % [o.label(), target.label(), block2])):
			out["ward_blocked"] = block2
			return total - block2
	return total


## 원소 누그러뜨리기(자연 영역, 반응 trigger ally_elemental_damage): 나 또는 6칸 안 아군이 산·냉기·화염·번개·천둥 피해를 받으면
## 반응으로 그 피해를 절반(저항). 자동 설정이면 그 종류 피해가 있을 때 쓴다.
static func _dampen_elements(target: Node, raw: Dictionary, opts: Dictionary) -> void:
	var kinds: Array = raw.keys().filter(func(t: String) -> bool: return t in ["acid", "cold", "fire", "lightning", "thunder"] and int(raw[t]) > 0 \
		and not target.resists(t) and not target.immune_to(t))
	var rq: Node = EventBus.reaction_queue
	if kinds.is_empty() or rq == null or not is_instance_valid(rq) or not rq.world.has("grid") or EventBus.realtime:
		return
	var grid: Node = rq.world["grid"]
	if not grid.creatures().has(target):
		return
	for o: Node in grid.creatures():
		if o.dead or o.is_hostile_to(target) or not o.can_react() or grid.distance_between(o, target) > 6:
			continue
		var fid: String = rq._trigger_feature(o, "ally_elemental_damage")
		if fid == "":
			continue
		if rq.offer(o, fid, {"target": target}, func() -> void:
			o.turn["reaction"] = int(o.turn.get("reaction", 1)) - 1
			for t: String in kinds:
				raw[t] = int(raw[t]) / 2
			Dice.log_text("%s 원소 누그러뜨리기: %s 피해 절반" % [o.label(), target.label()])):
			return


## 파괴의 분노(폭풍 영역, 능력 태그 destructive_wrath, 설정 켬): 번개·천둥 피해를 굴릴 때 신성 변환으로 최대. 쓰면 true.
static func destructive_max(c: Variant, dtype: String) -> bool:
	if not (c is Node) or not dtype in ["lightning", "thunder"] or not c.has_cap("destructive_wrath") \
			or str(c.options.get("destructive_wrath", "on")) != "on" or c.resource("channel_divinity") <= 0:
		return false
	c.spend_resource("channel_divinity")
	Dice.log_text("%s 파괴의 분노: %s 피해 최대" % [c.label(), dtype])
	return true


## 원소 통달(재주): 저항을 무시하고 주문 피해 주사위 1을 2로 치는 피해 종류
static func adept_types(c: Node) -> Array:
	return c.get_meta("elemental_adept", []) if c != null else []


static func _wearing_heavy(c: Node) -> bool:
	var a := str(c.get_meta("armor", ""))
	return a != "" and str(RulesDB.get_entry("armor", a).get("category", "")) == "heavy"


## 마법이 아닌 공격: 주문 공격이 아니고 마법 무기(+N)가 아닌 것(몬스터 자연 공격 포함 — 중갑 숙달)
static func _nonmagical_attack(atk: Dictionary) -> bool:
	if atk.has("spell") or atk.get("magical", false):
		return false
	return not atk.get("weapon", false) or int(load("res://scripts/rules/combat.gd").weapon_data(str(atk.get("weapon_id", ""))).get("magic_bonus", 0)) == 0


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
	_dampen_elements(target, raw, opts)
	var total := 0
	for t: String in raw.keys():
		var v := int(modify_amount(target, raw[t], t, 1.0, true))
		if t == "fire" and target.has_cap("fire_absorption"):
			heal(target, int(raw[t]), "fire_absorption")  # 화염 흡수(강철 골렘): 화염 피해만큼 회복
			v = 0
		var src: Variant = opts.get("attacker")
		if src is Node and (t in adept_types(src) or t in src.get_meta("ignore_resistance", [])) and target.resists(t) and not target.immune_to(t) and not target.vulnerable_to(t):
			v = int(raw[t])  # 원소 통달: 그 원소 저항 무시
		if src is Node and src.has_meta("casting_spell") and src != target and not target.resists(t) and not target.immune_to(t) and Auras.spell_resistance(target):
			v = v / 2  # 수호의 오라(고대인의 맹세 7레벨, BG3): 주문 피해 절반(다른 저항과 겹치지 않는다)
		out["by_type"][t] = v
		total += v
	out["total"] = total
	target.set_meta("last_damage_total", total)
	var psrc: Variant = opts.get("attacker")
	if target.has_cap("thought_shield") and int(out["by_type"].get("psychic", 0)) > 0 and psrc is Node and psrc != target and not opts.get("reflected", false):
		apply_damage(psrc, [{"amount": int(out["by_type"]["psychic"]), "damage_type": "psychic"}], {"attacker": target, "reflected": true})  # 생각의 방패(위대한 옛것 10레벨, BG3)
	var tsrc: Variant = opts.get("attacker")
	if tsrc is Node and tsrc != target and tsrc.has_cap("thunderbolt_strike") and (int(out["by_type"].get("lightning", 0)) > 0 or int(out["by_type"].get("thunder", 0)) > 0) \
			and ["tiny", "small", "medium", "large"].has(str(target.size)):
		var rq1: Node = EventBus.reaction_queue
		if rq1 != null and is_instance_valid(rq1) and rq1.world.has("grid") and rq1.world["grid"].creatures().has(target) and rq1.world["grid"].creatures().has(tsrc):
			load("res://scripts/rules/combat.gd")._push_up_to(rq1.world, tsrc, target, 2)  # 벼락 일격(폭풍 영역): 2칸(3m) 밀기
	target.set_meta("last_damage_types", out["by_type"].keys())
	for t: String in out["by_type"].keys():
		if t in ["acid", "fire"] and out["by_type"][t] > 0:
			target.set_meta("regen_blocked", true)  # 트롤 재생 막힘(다음 턴)
	if total > 0:
		total = _arcane_ward(target, total, out)
		out["total"] = total
	if total <= 0:
		return out
	# 9. 적용: 임시 HP 먼저
	var was_down: bool = target.hp == 0
	var absorbed := mini(target.temp_hp, total)
	target.temp_hp -= absorbed
	if absorbed > 0 and target.temp_hp == 0 and target.has_condition("symbiotic_entity"):
		target.remove_condition("symbiotic_entity")  # 공생체: 임시 HP가 다 하면 끝
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
		var gsrc: Variant = opts.get("attacker")
		if target.hp == 0 and gsrc is Node and gsrc != target and gsrc.has_cap("grim_harvest") and gsrc.has_meta("casting_spell") \
				and not str(target.creature_type) in ["undead", "construct"] and not gsrc.turn.get("grim_harvest_used", false):
			var gsp := RulesDB.get_entry("spell", str(gsrc.get_meta("casting_spell")))
			var gslot := int(gsrc.get_meta("casting_slot", gsp.get("level", 0)))
			if gslot > 0:
				gsrc.turn["grim_harvest_used"] = true
				heal(gsrc, gslot * (3 if str(gsp.get("school", "")) == "necromancy" else 2), "grim_harvest")  # 섬뜩한 수확(사령학파)
	var parts_text: PackedStringArray = []
	for t: String in out["by_type"].keys():
		parts_text.append("%s %d" % [t, out["by_type"][t]])
	Dice.log_text("%s 피해 %d (%s) → HP %d/%d%s" % [target.label(), total, ", ".join(parts_text), target.hp,
		target.hp_max, " (임시 HP %d 흡수)" % absorbed if absorbed > 0 else ""])
	if total > 0 and target.has_condition("raging"):
		target.set_meta("rage_damaged", true)  # 분노(BG3): 지난 턴 뒤 피해를 받았으면 이어진다
	if total > 0 and target.has_meta("end_on_damage"):
		for cid: String in target.get_meta("end_on_damage"):
			target.remove_condition(cid)  # 피해를 받으면 끝나는 상태(언데드 퇴치·적 퇴치)
		target.remove_meta("end_on_damage")
	EventBus.on_damage_taken.emit(info)
	# 피해를 받으면 끝나는 상태(Sleep·Hypnotic Pattern — params.ends_on_damage)
	for cond in target.conditions.duplicate():
		if total > 0 and (cond.get("params", {}).get("ends_on_damage", false) \
				or RulesDB.get_entry("condition", str(cond["id"])).get("ends_on_damage", false)):
			target.remove_condition(cond["id"])
	# 피해를 받으면 유리로 다시 내성(Hideous Laughter — params.save_on_damage)
	for cond in target.conditions.duplicate():
		var sod: Dictionary = cond.get("params", {}).get("save_on_damage", {})
		if not sod.is_empty() and target.conditions.has(cond) and not target.dead:
			var s := saving_throw(target, sod["ability"], int(sod["dc"]), {"advantage": ["피해"]})
			if s["success"]:
				var id: Variant = cond["params"].get("instance")
				if id == null:
					target.remove_condition(cond["id"])
					continue
				for other in target.conditions.duplicate():
					if other.get("params", {}).get("instance") == id:
						target.remove_condition(other["id"])
	# 집중 유지 내성(피해를 받으면 — 임시 HP가 막아도 받은 것이다)
	if not target.concentration.is_empty() and target.hp > 0:
		out["concentration"] = concentration_check(target, total, opts.get("attacker"))
	# 10. 0 HP — 야생 변신 형태 HP가 다하면 원래 모습·원래 HP로(BG3, 쓰러지지 않음)
	if not was_down and target.hp == 0 and target.has_meta("beast_form") and target.has_meta("wild_shape_hp"):
		load("res://scripts/rules/effects/wild_shape.gd").revert(target)
		return out
	if not was_down and target.hp == 0:
		_hp_zero(target, rest - out["hp_lost"], opts, out)
	return out


## 0 HP가 되었을 때(on_hp_zero). 리스너가 info["prevented"] = true로 막을 수 있다(끈질긴 인내 등).
static func _hp_zero(target: Node, remainder: int, opts: Dictionary, out: Dictionary) -> void:
	var info := {"creature": target, "remainder": remainder, "opts": opts, "prevented": false}
	for a in target.active_conditions():
		if a["def"].get("flags", {}).get("death_ward", false):
			target.hp = 1  # 죽음 방비(Death Ward): 처음 0 HP가 될 때 1 HP로 남고 끝난다
			target.remove_condition(a["id"])
			Dice.log_text("%s: 죽음 방비 — HP 1" % target.label())
			return
	EventBus.on_hp_zero.emit(info)
	if not info["prevented"]:
		Features.hook("on_hp_zero", target, {"res": info})
	if info["prevented"] or target.hp > 0:
		return
	_transfer_on_drop(target)
	_dark_ones_blessing(target, opts)
	var hcs: Dictionary = target.condition_instance("hexblades_curse")
	if not hcs.is_empty() and hcs.get("source") is Node and not hcs["source"].dead:
		var hsrc: Node = hcs["source"]
		heal(hsrc, maxi(1, hsrc.feature_level("hexblades_curse") + hsrc.ability_mod("cha")), "hexblades_curse")  # 저주받은 대상이 죽으면 회복
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
	if gained > 0:
		for a in target.active_conditions():
			if a["def"].get("ends_on_heal", false):
				target.remove_condition(str(a["id"]))  # 출혈·불구·다리 부상 등(BG3): 회복하면 풀린다
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
	if src is Node and opts.get("magic", false) and creature.has_cap("mage_slayer") and _adjacent(src, creature):
		res["advantage"].append("마법사 사냥꾼")  # 곁에서 시전한 주문의 내성 유리
	if src is Node and opts.get("magic", false) and src.has_cap("magical_ambush"):
		var hide: Dictionary = src.condition_instance("invisible")
		if not hide.is_empty() and hide["source"] is String and hide["source"] == "hide":
			res["disadvantage"].append("마법 매복")  # 숨은 채 쓴 주문의 내성 불리
	if src is Node and opts.get("magic", false) and creature.has_meta("eldritch_strike") and creature.get_meta("eldritch_strike") == src:
		creature.remove_meta("eldritch_strike")
		res["advantage"].erase("마법사 사냥꾼")
		res["disadvantage"].append("비전 일격")  # 비전 일격: 내 무기에 맞은 생물의 다음 내 주문 내성 불리
	if ability == "dex" and creature.has_cap("shield_dex_save_bonus") and bool(creature.get_meta("shield", false)):
		res["bonus"] += 2  # 방패 달인: 방패를 들면 민첩 내성 +2
	if res["auto"]:
		Dice.log_text("%s %s 내성 자동 실패 vs DC %d" % [creature.label(), ability, dc])
		return res
	if creature.has_cap("steel_will") and str(opts.get("vs_condition", "")) == "frightened":
		res["advantage"].append("강철 의지")  # 사냥꾼 방어 전술(BG3): 공포 내성 유리
	EventBus.on_save.emit(res)
	drunkards_luck(creature, res)
	_tides(creature, res)
	res["mode"] = mode_of(res["advantage"], res["disadvantage"])
	var d := luck(creature, Dice.d20(res["mode"], "%s %s 내성" % [creature.label(), ability]))
	if int(opts.get("min_natural", 0)) > int(d["natural"]):
		d["natural"] = int(opts["min_natural"])
	res["natural"] = d["natural"]
	res["total"] = d["natural"] + res["bonus"] + roll_bonus_dice(creature, "saving_throw")
	res["success"] = res["total"] >= dc
	if not res["success"]:
		res["total"] += inspire(creature)
		res["success"] = res["total"] >= dc
	if not res["success"] and heroic(creature):
		d = luck(creature, Dice.d20(res["mode"], "%s %s 내성(영웅적 영감)" % [creature.label(), ability]))
		res["natural"] = d["natural"]
		res["total"] = d["natural"] + res["bonus"] + roll_bonus_dice(creature, "saving_throw")
		res["success"] = res["total"] >= dc
	_portent_save(res, creature, dc, src)
	if not res["success"] and lucky(creature, "내성"):
		var nat := Dice.die(20)
		if nat > int(res["natural"]):
			res["total"] += nat - int(res["natural"])
			res["natural"] = nat
			res["success"] = res["total"] >= dc
	if not res["success"]:
		res["rolls"] = d["rolls"]
		Features.hook("on_save_failed", creature, {"res": res})  # 불굴(전사 9레벨) 등 — 스크립트가 res를 고친다
		if not res["success"]:
			_countercharm(creature, res, opts)
		d["natural"] = int(res["natural"])
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
		"bonus": creature.save_bonus(ability) + int(opts.get("bonus", 0)) + Auras.save_bonus(creature),
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
	if opts.get("magic", false) and creature.has_cap("magic_resistance"):
		res["advantage"].append("마법 저항")  # 주문 내성 유리(돌 골렘 등)
	return res


## 집중 유지 내성: 건강, DC = max(10, 피해 절반 내림), 최대 30. 자연 20·1 적용(2단계 결정 1).
static func concentration_check(creature: Node, damage: int, attacker: Variant = null) -> Dictionary:
	var held := str(creature.concentration.get("spell", ""))
	if held != "" and creature.has_cap("focused_conjuration") and str(RulesDB.get_entry("spell", held).get("school", "")) == "conjuration":
		return {"success": true, "auto": true}  # 집중된 소환(소환학파 10레벨): 피해로 소환학파 집중이 깨지지 않는다
	for f: Dictionary in creature.feature_data.values():
		if held != "" and held in f.get("protects_concentration", []):
			return {"success": true, "auto": true}  # 끈질긴 사냥꾼(레인저 13레벨): 피해로 사냥꾼의 표식 집중이 깨지지 않는다
	var dc := clampi(maxi(CONCENTRATION_DC_MIN, damage / 2), CONCENTRATION_DC_MIN, CONCENTRATION_DC_MAX)
	var copts := {"natural_rules": true}
	if creature.has_cap("eldritch_mind") or creature.has_cap("concentration_advantage") or bool(creature.concentration.get("advantage", false)):
		copts["advantage"] = ["집중 유리"]  # 섬뜩한 정신(워락 영창)·연장된 주문·전투 시전자
	if attacker is Node and attacker.has_cap("mage_slayer"):
		copts["disadvantage"] = ["마법사 사냥꾼"]  # 내가 맞힌 적의 집중 유지 불리
	if creature.has_flag("concentration_floor_10"):
		copts["min_natural"] = 10  # 별자리 용: 집중 유지 내성 9 이하는 10
	var res := saving_throw(creature, "con", dc, copts)
	if not res["success"]:
		creature.break_concentration("집중 유지 내성 실패")
	return res


## 능력 판정. opts: {"skill": String, "bonus": int, "advantage": [], "disadvantage": [],
##   "requires_sight": bool, "social": bool, "other": Node}
## 자연 20 자동 성공, 자연 1 자동 실패(2단계 공통 처리 규칙 1).
## 혼돈의 물결(야생 마법 소서러, 상태 tides_of_chaos): 다음 공격·판정·내성 하나에 유리, 쓰면 끝.
static func _tides(c: Node, res: Dictionary) -> void:
	if c.has_condition("tides_of_chaos"):
		res["advantage"].append("혼돈의 물결")
		c.remove_condition("tides_of_chaos")


## 술꾼의 행운(술 취한 달인 11레벨, 능력 태그 drunkards_luck): 불리가 있는 굴림(공격·내성·능력 판정)에 기 2로 불리를 없앤다(설정 켜면 자동).
static func drunkards_luck(c: Node, res: Dictionary) -> void:
	if not c.has_cap("drunkards_luck") or (res["disadvantage"] as Array).is_empty() or str(c.options.get("drunkards_luck", "on")) != "on" \
			or c.resource("focus") < 2:
		return
	if not (res["advantage"] as Array).is_empty():
		return  # 유리·불리가 상쇄되면 쓰지 않는다
	c.spend_resource("focus", 2)
	res["disadvantage"] = []
	Dice.log_text("%s 술꾼의 행운: 불리 없앰(기 2)" % c.label())


## 짐승의 면모: 늑대(능력 태그 aspect_wolf): 그 생물과 12칸 안 아군(나 포함)의 은신 판정 + 그 생물 민첩 수정치(가장 큰 하나).
static func _wolf_stealth(creature: Node) -> int:
	var rq: Variant = EventBus.reaction_queue
	if rq == null or not is_instance_valid(rq) or not rq.world.has("grid"):
		return 0
	var grid: Node = rq.world["grid"]
	if not grid.creatures().has(creature):
		return 0
	var best := 0
	for o: Node in grid.creatures():
		if o.has_cap("aspect_wolf") and not o.dead and not o.is_hostile_to(creature) and grid.distance_between(o, creature) <= 12:
			best = maxi(best, o.ability_mod("dex"))
	return best


static func ability_check(creature: Node, ability: String, dc: int, opts: Dictionary = {}) -> Dictionary:
	var res := {"creature": creature, "ability": ability, "dc": dc, "auto": false,
		"bonus": creature.ability_mod(ability) + _skill_bonus(creature, str(opts.get("skill", ""))) + int(opts.get("bonus", 0)) \
			+ (creature.proficiency_bonus / 2 if creature.has_cap("half_proficiency_physical") and ability in ["str", "dex", "con"] \
				and not creature.skill_bonuses.has(str(opts.get("skill", "")))  else 0),
		"advantage": opts.get("advantage", []).duplicate(), "disadvantage": opts.get("disadvantage", []).duplicate(),
		"success": false, "natural": 0, "total": 0, "mode": 0, "ctx": {}, "skill": str(opts.get("skill", ""))}
	if str(opts.get("skill", "")) == "stealth":
		var armor := str(creature.get_meta("armor", ""))
		if armor != "" and bool(RulesDB.get_entry("armor", armor).get("stealth_disadvantage", false)) \
				and not (creature.has_cap("medium_armor_master") and str(RulesDB.get_entry("armor", armor).get("category", "")) == "medium"):
			res["disadvantage"].append("갑옷(은신 불리)")  # SRD 갑옷 표 Stealth Disadvantage
		res["bonus"] += _wolf_stealth(creature)
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
		drunkards_luck(creature, res)
		_tides(creature, res)
		res["mode"] = mode_of(res["advantage"], res["disadvantage"])
		var d := luck(creature, Dice.d20(res["mode"], "%s %s 판정" % [creature.label(), ability]))
		res["natural"] = d["natural"]
		res["total"] = _reliable(creature, res["skill"], d["natural"]) + res["bonus"] + roll_bonus_dice(creature, "ability_check")
		res["success"] = d["natural"] == 20 or (d["natural"] != 1 and res["total"] >= dc)
		if not res["success"] and d["natural"] != 1:  # (뛰어난 운동선수 절반 숙련은 bonus에 이미 들어 있다)
			res["total"] += inspire(creature)
			res["success"] = res["total"] >= dc
		if not res["success"] and heroic(creature):
			d = luck(creature, Dice.d20(res["mode"], "%s %s 판정(영웅적 영감)" % [creature.label(), ability]))
			res["natural"] = d["natural"]
			res["total"] = _reliable(creature, res["skill"], d["natural"]) + res["bonus"] + roll_bonus_dice(creature, "ability_check")
			res["success"] = d["natural"] == 20 or (d["natural"] != 1 and res["total"] >= dc)
		if not res["success"] and lucky(creature, "판정"):
			var nat := Dice.die(20)
			if nat > int(res["natural"]):
				res["natural"] = nat
				res["total"] = _reliable(creature, res["skill"], nat) + res["bonus"] + roll_bonus_dice(creature, "ability_check")  # 인도(BG3) 등 능력 판정 +주사위
				res["success"] = nat == 20 or (nat != 1 and res["total"] >= dc)
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
		var so_t := so
		if opts.get("trap", false) and t.has_cap("trap_sense"):
			so_t = so.duplicate()
			so_t["advantage"] = so.get("advantage", []) + ["함정 감각"]  # 함정 감각: 함정 내성 유리
		saves.append({"success": false, "auto": true} if check.is_empty() else saving_throw(t, check["ability"], int(check["dc"]), so_t))
	for i in targets.size():
		var t: Node = targets[i]
		var s: Dictionary = saves[i]
		var effects: Array = success if s["success"] else fail
		if s.get("careful", false):
			effects = effects.filter(func(e: Dictionary) -> bool: return e["type"] != "damage")
		# 회피(능력 태그 evasion — 로그·몽크 7레벨): 성공 시 절반인 민첩 내성 피해 → 성공 0, 실패 절반. 무력화되면 못 쓴다.
		var evade: bool = str(check.get("ability", "")) == "dex" and t.has_cap("evasion") and not t.is_incapacitated() \
			and success.any(func(e: Dictionary) -> bool: return e["type"] == "damage")
		# 방패 달인(반응 재주 shield_master): 민첩 내성 주문 — 반응으로 실패면 절반, 성공이면 0(회피와 같은 결과)
		if not evade and str(check.get("ability", "")) == "dex" and opts.get("magic", false) and t.feature_data.has("shield_master") \
				and bool(t.get_meta("shield", false)) and (fail + success).any(func(e: Dictionary) -> bool: return e["type"] == "damage"):
			evade = Features.offer_reaction(t, "shield_master", {"save": s}, func() -> void:
				t.turn["reaction"] = int(t.turn.get("reaction", 1)) - 1
				Dice.log_text("%s 방패 달인: 방패로 막는다" % t.label()))
		if evade and s["success"]:
			effects = effects.filter(func(e: Dictionary) -> bool: return e["type"] != "damage")
		elif evade:
			effects = effects.map(func(e: Dictionary) -> Dictionary:
				if e["type"] != "damage":
					return e
				var h := e.duplicate()
				h["scale"] = float(e.get("scale", 1.0)) * 0.5
				return h)
		var parts: Array = []
		for e: Dictionary in effects:
			match e["type"]:
				"damage":
					var key: String = e["dice"] + "|" + e["damage_type"]
					if not rolled.has(key):
						var src_c: Variant = opts.get("source")
						rolled[key] = Dice.roll(e["dice"], "효과 피해", false,
							2 if src_c is Node and str(e["damage_type"]) in adept_types(src_c) else 0)["total"]
						if destructive_max(src_c, str(e["damage_type"])):
							rolled[key] = int(DiceExpr.stats(str(e["dice"]))["max"])
					var trap_half: float = 0.5 if opts.get("trap", false) and t.has_cap("trap_sense") else 1.0  # 함정 감각: 함정 피해 저항
					parts.append({"amount": rolled[key], "damage_type": e["damage_type"],
						"multiplier": float(e.get("scale", 1.0)) * trap_half})
				"apply_condition":
					var cp: Dictionary = opts.get("condition_params", {}).duplicate()
					if e.get("escape", false):
						cp["escape_dc"] = int(check.get("dc", 10))  # 행동으로 판정해 풀 수 있다(Entangle 등)
					t.apply_condition(e["id"], int(e.get("turns", opts.get("duration", 0))), opts.get("source"), cp)
		var dopts := opts
		if not opts.has("attacker") and opts.get("source") is Node:
			dopts = opts.duplicate()
			dopts["attacker"] = opts["source"]  # 주문·효과 피해의 출처(어둠의 자의 축복·피해 반응이 본다)
		var dmg := apply_damage(t, parts, dopts) if not parts.is_empty() else {}
		out.append({"target": t, "save": s, "damage": dmg})
	return out


# ======================================================================
# 턴 시작·사망 내성
# ======================================================================

## 턴 시작 처리(3단계 턴 순서 2): 턴 시작 효과(연소 등) → 사망 내성.
## 반응 회복과 재충전은 3단계 TurnManager가 맡는다.
static func start_turn(creature: Node, ctx: Dictionary = {}) -> void:
	EventBus.on_turn_start.emit(creature)
	var rq: Node = EventBus.reaction_queue
	if rq != null and is_instance_valid(rq) and rq.world.has("grid"):
		for o: Node in rq.world["grid"].creatures():
			if o.has_meta("no_opportunity_until") and o.get_meta("no_opportunity_until") == creature:
				o.remove_meta("no_opportunity_until")
	if ctx.get("in_combat", false) and creature.has_cap("heroic_warrior") and not creature.has_condition("heroic_inspiration"):
		creature.apply_condition("heroic_inspiration", -1, creature)  # 영웅 전사(챔피언 10레벨): 전투 중 턴 시작마다
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
			elif e["type"] == "heal" and not creature.dead and creature.hp > 0:
				var ha: Variant = e.get("amount", 1)
				heal(creature, int(a["instance"].get("params", {}).get("heal", 1)) if str(ha) == "param" else int(ha), a["id"])  # 재생, param = 건 쪽 수치(치유의 광휘)
				if str(ha) == "param":
					creature.remove_condition(a["id"])  # 한 번만(치유의 광휘: 다음 턴)
			elif e["type"] == "resource" and creature.resources.has(str(e["resource"])):
				var rr: Dictionary = creature.resources[str(e["resource"])]  # 몸의 완전함: 턴마다 기 1
				rr["current"] = mini(int(rr["max"]), int(rr["current"]) + int(e.get("amount", 1)))
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
