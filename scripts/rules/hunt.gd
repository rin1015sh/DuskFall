extends RefCounted
## 레인저 하위 클래스(BG3) 공격 뒤 장치 — 능력 태그로만 본다.
## - giant_killer(사냥꾼 — 거인 사냥꾼): 큰 이상 생물이 1칸 안에서 나를 공격하면 반응으로 근접 공격.
## - stalkers_flurry(어둠 추적자 11레벨): 턴당 1회 무기 공격이 빗나가면 한 번 더(무료).
## - dread_ambush(턴 상태 — 공포의 매복자): 첫 턴의 첫 무기 명중 +1d8.
## - gathered_swarm(무리지기 — 모인 무리, 설정 swarm_mode attack·utility): 턴당 1회 무기 명중 뒤 반응으로 무리 효과.

const Resolver := preload("res://scripts/rules/resolver.gd")
const SWARM := {"jellyfish": "lightning", "moths": "psychic", "bees": "piercing"}


static func after_attack(world: Dictionary, attacker: Node, target: Node, atk: Dictionary, res: Dictionary) -> void:
	if not world.has("grid") or EventBus.realtime or res.get("preview", false):
		return
	var grid: Node = world["grid"]
	var Combat: Variant = load("res://scripts/rules/combat.gd")
	# 공포의 매복자: 첫 명중 +1d8
	if res.get("hit", false) and atk.get("weapon", false) and attacker.turn.get("dread_ambush", false) and not target.dead:
		attacker.turn["dread_ambush"] = false
		Resolver.apply_damage(target, [{"amount": Dice.roll("1d8", "공포의 매복자")["total"], "damage_type": str(atk["damage"][0]["damage_type"])}], {"attacker": attacker})
	# 거인 사냥꾼
	if target.has_cap("giant_killer") and not target.dead and target.can_react() and attacker.is_hostile_to(target) \
			and str(attacker.size) in ["large", "huge", "gargantuan"] and grid.distance_between(attacker, target) <= 1 \
			and grid.can_see(target, attacker) and not attacker.dead and target.reaction_setting("giant_killer") != "off":
		Combat.opportunity_attack(world, target, attacker)
	# 추적자의 연타
	if not res.get("hit", false) and atk.get("weapon", false) and attacker.has_cap("stalkers_flurry") and not attacker.turn.get("flurry_used", false) \
			and not target.dead and not atk.get("opportunity", false):
		attacker.turn["flurry_used"] = true
		var again: Dictionary = atk.duplicate(true)
		again["name"] = "추적자의 연타"
		again["opportunity"] = true  # 다시 이 장치를 부르지 않게
		Combat._do_attack(world, attacker, target, again, true)
	# 저주 무기 결속: 맞히면 20%(d20 17+) 주술검사의 저주
	if res.get("hit", false) and attacker.has_meta("hexed_weapon") and str(atk.get("weapon_id", "")) == str(attacker.get_meta("hexed_weapon")) \
			and not target.dead and not target.has_condition("hexblades_curse") and Dice.roll("1d20", "저주 무기")["total"] >= 17:
		target.apply_condition("hexblades_curse", -1, attacker)
	# 필멸의 상기(위대한 옛것 1레벨, BG3): 치명타면 대상과 2칸 안 적 지혜 내성 실패 시 1턴 공포
	if res.get("crit", false) and attacker.has_cap("mortal_reminder"):
		var dc: int = load("res://scripts/rules/spellcasting.gd").spell_dc(attacker)
		for o: Node in grid.creatures():
			if not o.dead and o.is_hostile_to(attacker) and grid.distance_between(o, target) <= 2:
				if not Resolver.saving_throw(o, "wis", dc, {"source": attacker, "magic": true, "vs_condition": "frightened"})["success"]:
					o.apply_condition("frightened", 1, attacker)
	# 폭풍의 분노(폭풍 소서러 11레벨, BG3): 근접 공격에 맞으면 반응으로 소서러 레벨 번개 + 근력 내성 실패 시 4칸 밀기
	if res.get("hit", false) and target.has_cap("storms_fury") and str(atk.get("kind", "")) == "melee" and not target.dead and not attacker.dead \
			and target.can_react() and target.reaction_setting("storms_fury") != "off" and grid.distance_between(attacker, target) <= 1:
		target.turn["reaction"] = int(target.turn.get("reaction", 1)) - 1
		Resolver.apply_damage(attacker, [{"amount": target.feature_level("storms_fury"), "damage_type": "lightning"}], {"attacker": target})
		if not attacker.dead and not Resolver.saving_throw(attacker, "str", load("res://scripts/rules/spellcasting.gd").spell_dc(target), {"source": target, "magic": true})["success"]:
			Combat._push_up_to(world, target, attacker, 4)
	# 모인 무리
	if res.get("hit", false) and atk.get("weapon", false) and swarm_kind(attacker) != "" and not target.dead \
			and not attacker.turn.get("swarm_used", false) and attacker.can_react():
		_swarm(world, attacker, target)


static func swarm_kind(c: Node) -> String:
	for k: String in SWARM:
		if c.has_cap("swarm_" + k):
			return k
	return ""


static func _swarm(world: Dictionary, c: Node, t: Node) -> void:
	var kind := swarm_kind(c)
	var mode := str(c.options.get("swarm_mode", "attack"))
	var mighty: bool = c.has_cap("mighty_swarm")
	c.turn["swarm_used"] = true
	c.turn["reaction"] = int(c.turn.get("reaction", 1)) - 1
	var dc: int = 8 + c.proficiency_bonus + c.ability_mod("wis")
	if mode == "attack":
		var parts := [{"amount": Dice.roll("1d8" if mighty else "1d6", "무리")["total"], "damage_type": SWARM.get(kind, "piercing")}]
		if t.has_condition("hunters_marked"):
			parts.append({"amount": Dice.roll("1d6", "사냥감의 냄새")["total"], "damage_type": SWARM.get(kind, "piercing")})
		Resolver.apply_damage(t, parts, {"attacker": c})
		return
	match kind:
		"jellyfish":
			if not Resolver.saving_throw(t, "con", dc, {"source": c})["success"]:
				t.extra_modifiers.append({"effect": {"type": "modify", "stat": "no_reactions"}, "source": "shocking_sting", "until_turn_start_of": c})
				if mighty:
					t.apply_condition("disarmed", 1, c)
		"moths":
			if not Resolver.saving_throw(t, "con", dc, {"source": c})["success"]:
				t.apply_condition("blinded", 1, c)
				if mighty:
					t.apply_condition("slowed", 1, c)
		"bees":
			if not Resolver.saving_throw(t, "str", dc, {"source": c})["success"]:
				load("res://scripts/rules/combat.gd")._push_up_to(world, c, t, 3)
				if mighty and not t.dead:
					t.apply_condition("prone", -1, c)
