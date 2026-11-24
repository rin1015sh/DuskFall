extends "res://tests/test_case.gd"
## 팔라딘 BG3 맹세(4단계, 3레벨): 헌신 BG3판·고대인·복수·왕관·맹세 파기자.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Features := preload("res://scripts/rules/features.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func _pl(lv: int, sub: String) -> Node:
	var spec := Builder.default_spec("paladin", lv)
	spec["subclass"] = sub
	spec["species"] = "human"
	var r := Builder.build(spec)
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func _foe(v: Dictionary = {}) -> Node:
	var d := {"team": "enemy", "ac_base": 5, "hp_max": 100, "abilities": {"str": 1, "dex": 1, "con": 1, "wis": 1, "cha": 1}}
	d.merge(v, true)
	return make_creature(d)


func _world(p: Node, e: Node) -> Dictionary:
	var w := make_world(["........", "........"])
	w["grid"].place(p, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(1, 0))
	p.reset_turn()
	p.resources["channel_divinity"]["current"] = 1  # 맹세 변환 1회(BG3) — 테스트마다 채운다
	return w


func test_devotion() -> void:
	var p := _pl(7, "devotion")
	assert_true(p.spells.has("sanctuary") and p.spells.has("silence"), "맹세 주문")
	var e := _foe({"creature_type": "undead"})
	var w := _world(p, e)
	assert_true(Features.use(w, p, "turn_the_unholy")["ok"])
	assert_true(e.has_condition("frightened") and e.has_condition("incapacitated"), "부정한 것 퇴치")
	p.reset_turn()
	p.resources["channel_divinity"]["current"] = 1  # 맹세 변환 1회(BG3) — 테스트마다 채운다
	assert_true(Features.use(w, p, "holy_rebuke", p)["ok"])
	var hp: int = e.hp
	e.remove_condition("incapacitated")
	e.remove_condition("frightened")
	Dice.force([15, 3])
	Combat._do_attack(w, e, p, {"name": "주먹", "bonus": 5, "kind": "melee", "weapon": false, "damage": [{"dice": "1", "damage_type": "bludgeoning"}]})
	assert_eq(e.hp, hp - 3, "신성한 질책 1d4 광휘")


func test_ancients() -> void:
	var p := _pl(7, "ancients")
	var e := _foe()
	var w := _world(p, e)
	assert_true(p.spells.has("moonbeam"), "BG3 고대인 5레벨 달빛")
	Dice.force([1])
	assert_true(Features.use(w, p, "natures_wrath", e)["applied"])
	assert_true(e.has_condition("restrained"), "자연의 분노: 속박")
	p.hp = 10
	p.reset_turn()
	p.resources["channel_divinity"]["current"] = 1  # 맹세 변환 1회(BG3) — 테스트마다 채운다
	assert_true(Features.use(w, p, "healing_radiance")["ok"])
	var n: int = p.proficiency_bonus + 7 + p.ability_mod("cha")
	assert_eq(p.hp, 10 + n)
	Resolver.start_turn(p, {})
	assert_eq(p.hp, 10 + 2 * n, "다음 턴 한 번 더")
	assert_false(p.has_condition("healing_radiance"))
	# 수호의 오라: 주문 피해 절반
	p.set_meta("casting_spell", "fire_bolt")
	var ally := make_creature({"team": "party", "hp_max": 50})
	w["grid"].place(ally, Vector2i(0, 1))
	Resolver.apply_damage(ally, [{"amount": 10, "damage_type": "fire"}], {"attacker": p})
	p.remove_meta("casting_spell")
	assert_eq(ally.hp, 45, "주문 피해 절반")


func test_vengeance() -> void:
	var p := _pl(7, "vengeance")
	var e := _foe()
	var w := _world(p, e)
	assert_true(Features.use(w, p, "vow_of_enmity", e)["ok"])
	Dice.force([5, 15, 3])
	var r: Dictionary = Combat.attack(w, p, e, {"weapon": p.weapon("main")})
	assert_eq(int(r["mode"]), 1, "적대의 맹세 유리")
	p.reset_turn()
	p.resources["channel_divinity"]["current"] = 1  # 맹세 변환 1회(BG3) — 테스트마다 채운다
	assert_true(Features.use(w, p, "inquisitors_might", p)["ok"])
	Dice.force([15, 3, 3])
	var r2: Dictionary = Combat.attack(w, p, e, {"weapon": p.weapon("main")})
	assert_true(r2["hit"] and e.has_condition("dazed"), "심문관의 힘: 멍함")


func test_crown() -> void:
	var p := _pl(7, "crown")
	var ally := make_creature({"team": "party", "hp_max": 50})
	var e := _foe()
	var w := _world(p, e)
	w["grid"].place(ally, Vector2i(0, 1))
	assert_true(Features.use(w, p, "champion_challenge")["ok"])
	assert_true(e.has_condition("champion_challenged"))
	p.refresh_reaction()
	ally.hp = 50
	Resolver.apply_damage(ally, [{"amount": 10, "damage_type": "slashing"}])
	assert_eq(ally.hp, 50, "신성한 충성: 대신 받음")
	assert_eq(p.hp, p.hp_max - 10)


func test_oathbreaker() -> void:
	var p := _pl(7, "oathbreaker")
	var u := _foe({"creature_type": "undead"})
	var w := _world(p, u)
	Dice.force([1])
	assert_true(Features.use(w, p, "control_undead", u)["controlled"])
	assert_false(u.is_hostile_to(p), "내 편")
	var e := _foe()
	w["grid"].place(e, Vector2i(0, 1))
	p.reset_turn()
	p.resources["channel_divinity"]["current"] = 1  # 맹세 변환 1회(BG3) — 테스트마다 채운다
	Dice.force([1])
	assert_true(Features.use(w, p, "spiteful_suffering", e)["applied"])
	var hp: int = e.hp
	Dice.force([3])
	Resolver.start_turn(e, {})
	assert_eq(e.hp, hp - maxi(0, 3 + p.ability_mod("cha")), "매 턴 사령")
	p.reset_turn()
	p.resources["channel_divinity"]["current"] = 1  # 맹세 변환 1회(BG3) — 테스트마다 채운다
	Dice.force([15, 3])
	var r: Dictionary = Combat.attack(w, p, e, {"weapon": p.weapon("main")})
	assert_true(r["extra_damage"].any(func(x: Dictionary) -> bool: return x["dice"] == str(p.ability_mod("cha"))), "증오의 오라")
