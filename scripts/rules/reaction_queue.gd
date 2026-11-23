extends Node
## 반응 창. 룰북 3단계 '반응 주문·기능', 8단계 우선순위 규칙 4.
## 반응마다 설정(매번 묻기 ask / 자동 auto / 끄기 off)을 따른다.
## 묻기는 ask_callback(생물, 반응 ID, 정보) -> bool 로 답을 받는다(화면은 4단계). 콜백이 없으면 자동과 같다.
## 자동은 결과가 바뀔 때만 쓴다(예: Shield는 명중이 빗나감으로 바뀔 때만).

const Resolver := preload("res://scripts/rules/resolver.gd")

var world: Dictionary = {}
var ask_callback: Callable
## 기록: {"creature", "reaction", "used", "mode"}
var history: Array[Dictionary] = []


func setup(w: Dictionary) -> Node:
	world = w
	world["reactions"] = self
	EventBus.reaction_queue = self
	if not EventBus.on_after_attack_roll.is_connected(_on_after_attack_roll):
		EventBus.on_after_attack_roll.connect(_on_after_attack_roll)
	if not EventBus.on_before_attack_roll.is_connected(_on_before_attack_roll):
		EventBus.on_before_attack_roll.connect(_on_before_attack_roll)
	if not EventBus.on_miss.is_connected(_on_miss):
		EventBus.on_miss.connect(_on_miss)
	if not EventBus.on_spell_cast.is_connected(_on_spell_cast):
		EventBus.on_spell_cast.connect(_on_spell_cast)
	if not EventBus.on_fall.is_connected(_on_fall):
		EventBus.on_fall.connect(_on_fall)
	if not EventBus.on_damage_taken.is_connected(_on_damage_taken):
		EventBus.on_damage_taken.connect(_on_damage_taken)
	return self


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if EventBus.on_after_attack_roll.is_connected(_on_after_attack_roll):
			EventBus.on_after_attack_roll.disconnect(_on_after_attack_roll)
		if EventBus.on_before_attack_roll.is_connected(_on_before_attack_roll):
			EventBus.on_before_attack_roll.disconnect(_on_before_attack_roll)
		if EventBus.on_miss.is_connected(_on_miss):
			EventBus.on_miss.disconnect(_on_miss)
		if EventBus.reaction_queue == self:
			EventBus.reaction_queue = null
		if EventBus.on_spell_cast.is_connected(_on_spell_cast):
			EventBus.on_spell_cast.disconnect(_on_spell_cast)
		if EventBus.on_fall.is_connected(_on_fall):
			EventBus.on_fall.disconnect(_on_fall)
		if EventBus.on_damage_taken.is_connected(_on_damage_taken):
			EventBus.on_damage_taken.disconnect(_on_damage_taken)


## 반응 창 하나. 쓰기로 하면 action을 실행한다. 쓴 경우 true.
func offer(c: Node, reaction_id: String, info: Dictionary, action: Callable, auto_yes: bool = true) -> bool:
	if not c.known_reactions.has(reaction_id) or not c.can_react():
		return false
	if EventBus.realtime and str(RulesDB.get_entry("spell", reaction_id).get("cast", {}).get("trigger", "")) != "on_fall":
		return false  # 실시간에서는 반응이 발동하지 않는다(5단계 실시간 규칙). 낙하 반응(Feather Fall)만 예외(changes.md)
	var setting: String = c.reaction_setting(reaction_id)
	var use := false
	match setting:
		"off":
			use = false
		"auto":
			use = auto_yes
		"ask":
			use = ask_callback.call(c, reaction_id, info) if ask_callback.is_valid() else auto_yes
	history.append({"creature": c, "reaction": reaction_id, "used": use, "mode": setting})
	if use:
		action.call()
	return use


# ---------- 반응 주문(주문 데이터 cast.trigger로 고른다 — 주문 이름을 모른다) ----------
# on_after_attack_roll: 내가 맞았을 때, 즉시 효과 apply의 modify ac add(+until)로 명중을 되돌릴 수 있으면(방패)
# on_spell_cast: 사거리 안 보이는 적이 시전할 때, 그 주문을 시전해 cast_ctx를 넘긴다(주문 방해 스크립트가 처리)
# on_fall: 사거리 안 아군이 떨어질 때, 효과에 modify fall_damage가 있으면 낙하 피해를 막는다(깃털 낙하)
# on_damage_taken: 사거리 안 보이는 적에게 피해를 받았을 때, 그 적을 대상으로 시전(지옥의 질책)

## 이 생물이 아는 반응 주문 중 trigger가 맞는 것(주문 ID 목록).
static func reaction_spells(c: Node, trigger: String) -> Array:
	var out: Array = []
	for rid: String in c.known_reactions:
		var sp := RulesDB.get_entry("spell", rid)
		if not sp.is_empty() and str(sp.get("cast", {}).get("trigger", "")) == trigger:
			out.append(rid)
	return out


## 반응 주문 값을 낼 수 있으면 쓸 자원 ID(타고난 무료 횟수 먼저, 아니면 가장 낮은 슬롯). 소마법은 "-".
static func payment(c: Node, spell_id: String) -> String:
	var lv := int(RulesDB.get_entry("spell", spell_id).get("level", 0))
	if lv == 0:
		return "-"
	var innate := "innate_" + spell_id
	if c.resource(innate) > 0:
		return innate
	return lowest_slot(c, lv)


static func _spend_reaction(c: Node, spell_id: String) -> void:
	var pay := payment(c, spell_id)
	if pay != "-" and pay != "":
		c.spend_resource(pay)
	c.turn["reaction"] = int(c.turn.get("reaction", 1)) - 1


static func _spell_name(spell_id: String) -> String:
	return str(RulesDB.get_entry("spell", spell_id).get("name", {}).get("en", spell_id))


## 반응 재주(기능 데이터 kind reaction + trigger)를 가진 생물의 그 기능 id. 없으면 "".
static func _trigger_feature(c: Node, trigger: String) -> String:
	for fid: String in c.feature_data:
		var f: Dictionary = c.feature_data[fid]
		if str(f.get("kind", "")) == "reaction" and str(f.get("trigger", "")) == trigger:
			return fid
	return ""


## 보호(전투 방식, trigger enemy_attacks_ally_before): 방패를 든 내 곁(1칸)의 아군을 노린 보이는 적의 공격에 반응으로 불리.
func _on_before_attack_roll(res: Dictionary) -> void:
	if res.get("preview", false) or not world.has("grid") or not res.get("valid", true):
		return
	var grid: Node = world["grid"]
	var attacker: Node = res["attacker"]
	var target: Node = res["target"]
	if not grid.creatures().has(attacker) or not grid.creatures().has(target):
		return
	# 경고의 섬광(빛 영역, trigger attack_before_disadvantage): 나(include_self) 또는 ally_range_tiles 안 아군을 노린 보이는 적의 공격에 반응 + 자원으로 불리
	for o: Node in grid.creatures():
		if o.dead or o == attacker or not o.is_hostile_to(attacker) or o.is_hostile_to(target) or not o.can_react():
			continue
		for fid0: String in o.feature_data:
			var f0: Dictionary = o.feature_data[fid0]
			if str(f0.get("kind", "")) != "reaction" or str(f0.get("trigger", "")) != "attack_before_disadvantage":
				continue
			var ok0: bool = (o == target and f0.get("include_self", false)) \
				or (o != target and int(f0.get("ally_range_tiles", 0)) > 0 and grid.distance_between(o, target) <= int(f0["ally_range_tiles"]))
			var rid := str(f0.get("resource", ""))
			if not ok0 or not grid.can_see(o, attacker) or (rid != "" and o.resource(rid) <= 0) or "섬광" in res["disadvantage"]:
				continue
			if offer(o, fid0, {"attack": res}, func() -> void:
				o.turn["reaction"] = int(o.turn.get("reaction", 1)) - 1
				if rid != "":
					o.spend_resource(rid)
				res["disadvantage"].append("섬광")
				Dice.log_text("%s 경고의 섬광: %s의 공격이 불리" % [o.label(), attacker.label()])):
				break
	for o: Node in grid.creatures():
		if o == target or o.dead or not o.is_hostile_to(attacker) or o.is_hostile_to(target) or not o.can_react():
			continue
		var fid := _trigger_feature(o, "enemy_attacks_ally_before")
		if fid == "" or not bool(o.get_meta("shield", false)) or grid.distance_between(o, target) > 1 or not grid.can_see(o, attacker):
			continue
		if "보호" in res["disadvantage"]:
			return
		if offer(o, fid, {"attack": res}, func() -> void:
			o.turn["reaction"] = int(o.turn.get("reaction", 1)) - 1
			res["disadvantage"].append("보호")
			Dice.log_text("%s 보호: %s의 공격이 불리" % [o.label(), attacker.label()])):
			return


## 반격(기법, 능력 태그 riposte, 상시 설정 켬): 적의 근접 공격이 나를 빗나가면 반응 + 우월 주사위로 그 적에게 무기 공격(우월 주사위 피해 추가).
func _on_miss(res: Dictionary) -> void:
	if res.get("preview", false) or not world.has("grid") or EventBus.realtime:
		return
	var t: Node = res.get("target")
	var attacker: Node = res.get("attacker")
	if t == null or attacker == null or t.dead or attacker.dead or not t.has_cap("riposte") or not t.can_react():
		return
	if str(res.get("attack", {}).get("kind", "")) != "melee" or t.resource("superiority_dice") <= 0 or not t.is_hostile_to(attacker):
		return
	if str(t.options.get("wa_m_riposte", "on")) != "on" or world["grid"].distance_between(t, attacker) > 1:
		return
	var Combat: Variant = load("res://scripts/rules/combat.gd")
	t.turn["reaction"] = int(t.turn.get("reaction", 1)) - 1
	t.spend_resource("superiority_dice")
	var wid: String = t.weapon_sets.get("melee", {}).get("main", "")
	var atk: Dictionary = Combat.build_weapon_attack(t, wid if wid != "" else "unarmed")
	var die: String = load("res://scripts/rules/actions.gd").special_die(t, "superiority_dice")
	atk["damage"] = atk["damage"] + [{"dice": die, "damage_type": atk["damage"][0]["damage_type"]}]
	atk["name"] = "반격"
	atk["opportunity"] = true
	Combat._do_attack(world, t, attacker, atk, true)


## 막아내기 검술(trigger self_hit_melee): 숙련 교묘 무기를 주 무기로 쥐고 근접 공격에 맞으면 반응으로 그 공격에 AC + 숙련 보너스.
## 빗나가게 할 수 있을 때만(BG3). 명중 굴림에서 숙련 보너스를 빼는 것과 같다.
func _self_hit_reactions(res: Dictionary) -> void:
	var t: Node = res["target"]
	var fid := _trigger_feature(t, "self_hit_melee")
	if fid == "" or not t.can_react() or str(res.get("attack", {}).get("kind", "")) != "melee":
		return
	var prop := str(t.feature_data[fid].get("requires_weapon_property", ""))
	var wid: String = t.weapon_sets.get("melee", {}).get("main", "")
	var Combat: Variant = load("res://scripts/rules/combat.gd")
	if prop != "" and (wid == "" or t.active_set != "melee" or not prop in Combat.weapon_data(wid).get("properties", [])):
		return
	var pb: int = t.proficiency_bonus
	if res["total"] - pb >= res["ac"] + res["ac_bonus"]:
		return
	offer(t, fid, {"attack": res, "would_miss": true}, func() -> void:
		t.turn["reaction"] = int(t.turn.get("reaction", 1)) - 1
		res["ac_bonus"] += pb
		Dice.log_text("%s 막아내기 검술: AC +%d" % [t.label(), pb]))


## 파수(trigger enemy_attacks_ally): 내 도달 안의 적이 다른 아군(파수가 없는)을 공격하면 반응으로 그 적에게 무기 공격.
## Combat._do_attack이 공격을 끝낸 뒤 부른다.
func after_attack(res: Dictionary) -> void:
	if res.get("preview", false) or not world.has("grid") or EventBus.realtime:
		return
	var grid: Node = world["grid"]
	var attacker: Node = res.get("attacker")
	var target: Node = res.get("target")
	if attacker == null or target == null or not grid.creatures().has(attacker) or attacker.dead:
		return
	_storm_retaliate(res, grid)
	if attacker.dead:
		return
	if _trigger_feature(target, "enemy_attacks_ally") != "":
		return  # 대상이 파수를 가졌으면 다른 파수는 반응하지 않는다(BG3)
	var Combat: Variant = load("res://scripts/rules/combat.gd")
	for o: Node in grid.creatures():
		if o == target or o == attacker or o.dead or not o.is_hostile_to(attacker) or o.is_hostile_to(target) or not o.can_react():
			continue
		var fid := _trigger_feature(o, "enemy_attacks_ally")
		if fid == "" or o.active_set != "melee" or grid.distance_between(o, attacker) > Combat.reach_of(o):
			continue
		offer(o, fid, {"target": attacker}, func() -> void:
			o.turn["reaction"] = int(o.turn.get("reaction", 1)) - 1
			var atk: Dictionary = Combat.build_weapon_attack(o, o.weapon("main"))
			atk["name"] = "파수(%s)" % atk["name"]
			Combat._do_attack(world, o, attacker, atk, true))
		if attacker.dead:
			return


## 폭풍의 분노(폭풍 영역, trigger hit_by_melee_retaliate): 1칸 안 적의 근접 공격에 맞으면 반응 + 자원으로 그 적에게
## 2d8 번개 또는 천둥(상시 설정), 민첩 내성 성공 시 절반(주문 내성 DC).
func _storm_retaliate(res: Dictionary, grid: Node) -> void:
	var t: Node = res["target"]
	var attacker: Node = res["attacker"]
	if not res.get("hit", false) or t.dead or str(res.get("attack", {}).get("kind", "")) != "melee" or not t.is_hostile_to(attacker):
		return
	var fid := _trigger_feature(t, "hit_by_melee_retaliate")
	if fid == "" or not t.can_react() or grid.distance_between(t, attacker) > 1:
		return
	var rid := str(t.feature_data[fid].get("resource", ""))
	if rid != "" and t.resource(rid) <= 0:
		return
	offer(t, fid, {"target": attacker}, func() -> void:
		t.turn["reaction"] = int(t.turn.get("reaction", 1)) - 1
		if rid != "":
			t.spend_resource(rid)
		var dt := str(t.options.get(fid, "lightning"))
		var Spellcasting: Variant = load("res://scripts/rules/spellcasting.gd")
		load("res://scripts/rules/resolver.gd").save_effect([attacker], {"ability": "dex", "dc": Spellcasting.spell_dc(t)},
			[{"type": "damage", "dice": "2d8", "damage_type": dt}], [{"type": "damage", "dice": "2d8", "damage_type": dt, "scale": 0.5}],
			{"source": t, "magic": true})
		Dice.log_text("%s 폭풍의 분노(%s)" % [t.label(), dt]))


## 빗나간 공격 보정(Resolver.attack이 빗나감 직후 부른다): 전쟁 신의 축복(trigger ally_attack_missed_bonus — 반응 + 자원으로 아군 공격 +N).
## 10 이내로 빗나갔을 때만(그래야 맞힐 수 있다).
func miss_bonus(res: Dictionary) -> void:
	if res.get("preview", false) or not world.has("grid") or res.get("hit", false) or int(res.get("natural", 0)) == 1:
		return
	var grid: Node = world["grid"]
	var attacker: Node = res["attacker"]
	if not grid.creatures().has(attacker):
		return
	for o: Node in grid.creatures():
		if o.dead or o.is_hostile_to(attacker) or not o.can_react():
			continue
		var fid := _trigger_feature(o, "ally_attack_missed_bonus")
		if fid == "":
			continue
		var f: Dictionary = o.feature_data[fid]
		var add := int(f.get("attack_bonus", 10))
		var rid := str(f.get("resource", ""))
		if (rid != "" and o.resource(rid) <= 0) or grid.distance_between(o, attacker) > int(f.get("range_tiles", 6)) \
				or res["total"] + add < res["ac"] + res["ac_bonus"]:
			continue
		if offer(o, fid, {"attack": res, "would_hit": true}, func() -> void:
			o.turn["reaction"] = int(o.turn.get("reaction", 1)) - 1
			if rid != "":
				o.spend_resource(rid)
			res["total"] += add
			res["hit"] = true
			Dice.log_text("%s %s: %s의 공격 +%d" % [o.label(), str(f.get("name", {}).get("ko", fid)), attacker.label(), add])):
			return


func _on_after_attack_roll(res: Dictionary) -> void:
	if res.get("preview", false) or not res.get("hit", false) or res.get("crit", false):
		return
	_enemy_hit_reactions(res)
	if res.get("hit", false) and res["total"] >= res["ac"] + res["ac_bonus"]:
		_self_hit_reactions(res)
	if not res.get("hit", false) or res["total"] < res["ac"] + res["ac_bonus"]:
		return  # 이미 빗나감으로 바뀌었다
	var t: Node = res["target"]
	for sid: String in reaction_spells(t, "on_after_attack_roll"):
		var add := 0
		for e: Dictionary in RulesDB.get_entry("spell", sid).get("effects", {}).get("apply", []):
			if e.get("type") == "modify" and e.get("stat") == "ac":
				add += int(e.get("add", 0))
		if add <= 0 or payment(t, sid) == "":
			continue
		var would_miss: bool = res["total"] < res["ac"] + res["ac_bonus"] + add
		if offer(t, sid, {"attack": res, "would_miss": would_miss}, func() -> void:
			_spend_reaction(t, sid)
			res["ac_bonus"] += add
			t.extra_modifiers.append({"effect": {"type": "modify", "stat": "ac", "add": add}, "source": sid,
				"until_turn_start_of": t})
			Dice.log_text("%s %s: AC +%d" % [t.label(), _spell_name(sid), add]), would_miss):
			return


## 제3자 반응 기능(기능 데이터 kind reaction + trigger "enemy_attack_hit" — 바드 비꼬는 말):
## 사거리 안 보이는 적이 명중하면, 반응과 자원(feature.resource)을 써서 기능 주사위(dice_by_level)를 명중 굴림에서 뺀다.
## 자동 설정이면 평균값으로 빗나감이 될 때만 쓴다.
func _enemy_hit_reactions(res: Dictionary) -> void:
	if not world.has("grid"):
		return
	var grid: Node = world["grid"]
	var attacker: Node = res["attacker"]
	if not grid.creatures().has(attacker):
		return
	for o: Node in grid.creatures():
		if o.dead or not o.is_hostile_to(attacker) or not o.can_react():
			continue
		for fid: String in o.feature_data:
			var f: Dictionary = o.feature_data[fid]
			if str(f.get("kind", "")) != "reaction" or str(f.get("trigger", "")) != "enemy_attack_hit":
				continue
			var res_id := str(f.get("resource", ""))
			if res_id != "" and o.resource(res_id) <= 0:
				continue
			if grid.distance_between(o, attacker) > int(f.get("range_tiles", 12)) or not grid.can_see(o, attacker):
				continue
			var die := _feature_die(o, f)
			var avg := (int(die.get_slice("d", 1)) + 1) / 2.0
			var would_miss: bool = res["total"] - avg < res["ac"] + res["ac_bonus"]
			if offer(o, fid, {"attack": res, "would_miss": would_miss}, func() -> void:
				if res_id != "":
					o.spend_resource(res_id)
				o.turn["reaction"] = int(o.turn.get("reaction", 1)) - 1
				var n: int = Dice.roll(die, str(f.get("name", {}).get("en", fid)))["total"]
				res["total"] -= n
				res["hit"] = res["total"] >= res["ac"] + res["ac_bonus"]
				Dice.log_text("%s %s: 명중 굴림 −%d" % [o.label(), str(f.get("name", {}).get("ko", fid)), n]), would_miss):
				return


## 기능 주사위(dice_by_level, 없으면 같은 자원을 쓰는 기능의 표 — 바드의 영감 주사위).
static func _feature_die(c: Node, f: Dictionary) -> String:
	var table: Dictionary = f.get("dice_by_level", {})
	if table.is_empty():
		for g: Dictionary in c.feature_data.values():
			if g.get("resource", "") == f.get("resource", "-") and g.has("dice_by_level"):
				table = g["dice_by_level"]
	var best := "1d6"
	var best_lv := 0
	for k: String in table:
		if c.feature_level(str(f.get("id", ""))) >= int(k) and int(k) >= best_lv:
			best_lv = int(k)
			best = str(table[k])
	return best


func _on_spell_cast(ctx: Dictionary) -> void:
	var caster: Node = ctx["caster"]
	if ctx.get("countered", false) or ctx.get("subtle", false) or not world.has("grid"):
		return  # 은밀한 주문은 시전을 알아챌 수 없다
	if str(RulesDB.get_entry("spell", str(ctx.get("spell", ""))).get("cast", {}).get("trigger", "")) == "on_spell_cast":
		return  # 방해 주문은 다시 방해하지 않는다
	var grid: Node = world["grid"]
	# 마법사 사냥꾼(trigger enemy_casts_adjacent): 곁(1칸)의 적이 주문을 시전하면 반응으로 그 시전자에게 무기 공격
	if grid.creatures().has(caster) and not EventBus.realtime:
		var Combat: Variant = load("res://scripts/rules/combat.gd")
		for o: Node in grid.creatures():
			if o == caster or o.dead or not o.is_hostile_to(caster) or not o.can_react() or grid.distance_between(o, caster) > 1:
				continue
			var fid := _trigger_feature(o, "enemy_casts_adjacent")
			if fid == "" or o.active_set != "melee":
				continue
			offer(o, fid, {"cast": ctx}, func() -> void:
				o.turn["reaction"] = int(o.turn.get("reaction", 1)) - 1
				var atk: Dictionary = Combat.build_weapon_attack(o, o.weapon("main"))
				atk["name"] = "마법사 사냥꾼(%s)" % atk["name"]
				Combat._do_attack(world, o, caster, atk, true))
	var list: Array = grid.creatures().filter(func(o: Node) -> bool:
		return o != caster and not o.dead and o.is_hostile_to(caster) and not reaction_spells(o, "on_spell_cast").is_empty() \
			and grid.can_see(o, caster))
	list.sort_custom(func(a: Node, b: Node) -> bool: return a.initiative > b.initiative)
	var Spellcasting: Variant = load("res://scripts/rules/spellcasting.gd")
	for o: Node in list:
		for sid: String in reaction_spells(o, "on_spell_cast"):
			if ctx["countered"]:
				return
			if not o.spells.has(sid) or payment(o, sid) == "" \
					or grid.distance_between(o, caster) > Spellcasting.range_tiles(RulesDB.get_entry("spell", sid)):
				continue
			offer(o, sid, {"cast": ctx}, func() -> void:
				Spellcasting.cast(world, o, sid, grid.cell_of(caster), {"cast_ctx": ctx}))


func _on_fall(ctx: Dictionary) -> void:
	if ctx.get("prevented", false) or not world.has("grid"):
		return
	var faller: Node = ctx["creature"]
	var grid: Node = world["grid"]
	var Spellcasting: Variant = load("res://scripts/rules/spellcasting.gd")
	for o: Node in grid.creatures():
		if o.dead or o.is_hostile_to(faller):
			continue
		for sid: String in reaction_spells(o, "on_fall"):
			var sp := RulesDB.get_entry("spell", sid)
			var stops: bool = sp.get("effects", {}).get("apply", []).any(func(e: Dictionary) -> bool:
				return e.get("type") == "modify" and e.get("stat") == "fall_damage")
			if not stops or not o.spells.has(sid) or payment(o, sid) == "" \
					or grid.distance_between(o, faller) > Spellcasting.range_tiles(sp):
				continue
			if offer(o, sid, {"fall": ctx}, func() -> void:
				_spend_reaction(o, sid)
				ctx["prevented"] = true
				Dice.log_text("%s %s: %s 낙하 피해 없음" % [o.label(), _spell_name(sid), faller.label()])):
				return


func _on_damage_taken(info: Dictionary) -> void:
	if not world.has("grid"):
		return
	var t: Node = info.get("target")
	var attacker: Variant = info.get("opts", {}).get("attacker")
	if t == null or t.dead or t.hp <= 0 or not (attacker is Node) or attacker == t or attacker.dead \
			or not attacker.is_hostile_to(t) or int(info.get("amount", 0)) <= 0:
		return
	var grid: Node = world["grid"]
	if not grid.creatures().has(attacker) or not grid.creatures().has(t) or not grid.can_see(t, attacker):
		return
	# 보복(능력 태그 retaliation — 광전사 10레벨): 1칸 안 생물에게 피해를 받으면 반응으로 근접 공격 1회
	if t.has_cap("retaliation") and grid.distance_between(t, attacker) <= 1 and t.known_reactions.has("retaliation"):
		var Combat: Variant = load("res://scripts/rules/combat.gd")
		if offer(t, "retaliation", {"attacker": attacker}, func() -> void: Combat.opportunity_attack(world, t, attacker)):
			return
	var Spellcasting: Variant = load("res://scripts/rules/spellcasting.gd")
	for sid: String in reaction_spells(t, "on_damage_taken"):
		if not t.spells.has(sid) or payment(t, sid) == "" \
				or grid.distance_between(t, attacker) > Spellcasting.range_tiles(RulesDB.get_entry("spell", sid)):
			continue
		if offer(t, sid, {"damage": info, "attacker": attacker}, func() -> void:
			Spellcasting.cast(world, t, sid, grid.cell_of(attacker))):
			return


## min_level 이상에서 가장 낮은 남은 주문 슬롯 자원 ID. 없으면 "".
static func lowest_slot(c: Node, min_level: int) -> String:
	for lv in range(min_level, 10):
		for key: String in ["spell_slot_%d", "pact_slot_%d"]:
			if c.resource(key % lv) > 0:
				return key % lv  # 멀티클래스 계약 마법 슬롯도
	return ""
