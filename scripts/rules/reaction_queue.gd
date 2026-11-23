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


func _on_after_attack_roll(res: Dictionary) -> void:
	if res.get("preview", false) or not res.get("hit", false) or res.get("crit", false):
		return
	_enemy_hit_reactions(res)
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
		if c.level >= int(k) and int(k) >= best_lv:
			best_lv = int(k)
			best = str(table[k])
	return best


func _on_spell_cast(ctx: Dictionary) -> void:
	var caster: Node = ctx["caster"]
	if ctx.get("countered", false) or not world.has("grid"):
		return
	if str(RulesDB.get_entry("spell", str(ctx.get("spell", ""))).get("cast", {}).get("trigger", "")) == "on_spell_cast":
		return  # 방해 주문은 다시 방해하지 않는다
	var grid: Node = world["grid"]
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
		var id := "spell_slot_%d" % lv
		if c.resource(id) > 0:
			return id
	return ""
