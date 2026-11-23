extends "res://tests/test_case.gd"
## 레벨 상한 20 — 2구간(11~15레벨) 기능.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Features := preload("res://scripts/rules/features.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Actions := preload("res://scripts/rules/actions.gd")


func _pc(cid: String, lv: int, extra: Dictionary = {}) -> Node:
	var spec := Builder.default_spec(cid, lv)
	spec.merge(extra, true)
	var r := Builder.build(spec)
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func _arena(a: Node, b: Node) -> Dictionary:
	var w := make_world(["..........", "..........", ".........."])
	w["grid"].place(a, Vector2i(1, 1))
	w["grid"].place(b, Vector2i(2, 1))
	a.reset_turn()
	return w


func test_fighter_11_15() -> void:
	var f := _pc("fighter", 15)
	assert_eq(f.attacks_per_action, 3, "추가 공격 2회")
	assert_eq(f.crit_threshold, 18, "우월한 치명타")
	var foe := make_creature({"team": "enemy", "hp_max": 300, "ac_base": 30})
	var w := _arena(f, foe)
	Dice.force([2])
	Resolver.attack(f, foe, Combat.build_weapon_attack(f, f.weapon("main")), w["grid"].attack_context(f, foe))
	var p := Resolver.preview_attack(f, foe, Combat.build_weapon_attack(f, f.weapon("main")), w["grid"].attack_context(f, foe))
	assert_eq(int(p["mode"]), 1, "연구된 공격: 빗나간 대상에 다음 공격 유리")


func test_barbarian_11_15() -> void:
	var b := _pc("barbarian", 15)
	var foe := make_creature({"team": "enemy", "hp_max": 300})
	var w := _arena(b, foe)
	assert_true(Features.use(w, b, "rage")["ok"])
	Dice.force([15])
	Resolver.apply_damage(b, [{"amount": b.hp + 5, "damage_type": "fire"}])
	assert_eq(b.hp, 30, "끈질긴 분노: 바바리안 레벨 × 2")
	b.resources["rage"]["current"] = 0
	w["turns"].roll_initiative(b)
	assert_eq(b.resource("rage"), int(b.resources["rage"]["max"]), "끈질긴 분노 유지: 이니셔티브 때 회복")
	b.turn["rage_kept"] = false
	w["turns"].end_turn(b)
	assert_true(b.has_condition("raging"), "연장 없이 유지")
	# 위협적인 존재감
	b.reset_turn()
	Dice.force([1])
	assert_true(Features.use(w, b, "intimidating_presence")["ok"])
	assert_true(foe.has_condition("frightened"))
	b.reset_turn()
	var rage: int = b.resource("rage")
	Features.use(w, b, "intimidating_presence")
	assert_eq(b.resource("rage"), rage - 1, "두 번째는 분노 1회로")
	# 잔혹한 일격 선택지: 13레벨부터
	b.options["brutal_strike"] = "hamstring"
	Actions.toggle_passive(b, "brutal_strike")
	assert_eq(str(b.options["brutal_strike"]), "staggering")
	var low := _pc("barbarian", 12)
	low.options["brutal_strike"] = "hamstring"
	Actions.toggle_passive(low, "brutal_strike")
	assert_eq(str(low.options["brutal_strike"]), "", "12레벨은 다시 처음으로")


func test_rogue_11_15() -> void:
	var r := _pc("rogue", 15)
	assert_true("wis" in r.save_proficiencies and "cha" in r.save_proficiencies, "미끄러운 정신")
	var foe := make_creature({"team": "enemy", "hp_max": 300, "ac_base": 1})
	var w := _arena(r, foe)
	var ally := make_creature({"team": "party", "hp_max": 30})
	w["grid"].place(ally, Vector2i(3, 1))
	r.options["cunning_strike"] = "trip"
	r.options["improved_cunning_strike"] = "obscure"
	Dice.force([15])
	var res := Combat.attack(w, r, foe)
	assert_eq(str(res.get("cunning_strike", "")), "trip")
	assert_eq(str(res.get("cunning_strike_2", "")), "obscure", "두 번째 효과")
	assert_eq(int(res["sneak_attack"]), 8 - 1 - 3, "8d6 − 넘어뜨리기 1 − 시야 가리기 3")


func test_monk_paladin_ranger() -> void:
	var m := _pc("monk", 15)
	assert_eq(m.save_proficiencies.size(), 6, "수련된 생존자: 모든 내성")
	m.resources["focus"]["current"] = 1
	m.resources["uncanny_metabolism"]["current"] = 0
	var w0 := make_world(["...."])
	w0["grid"].place(m, Vector2i(0, 0))
	w0["turns"].roll_initiative(m)
	assert_eq(m.resource("focus"), 4, "완벽한 집중")
	var p := _pc("paladin", 14)
	var foe := make_creature({"team": "enemy", "hp_max": 300, "ac_base": 1})
	var w := _arena(p, foe)
	Dice.force([15])
	var res := Resolver.attack(p, foe, Combat.build_weapon_attack(p, p.weapon("main")), w["grid"].attack_context(p, foe))
	assert_true(res["extra_damage"].any(func(x: Dictionary) -> bool: return x["damage_type"] == "radiant"), "빛나는 일격")
	var ally := make_creature({"team": "party", "hp_max": 30})
	w["grid"].place(ally, Vector2i(1, 2))
	ally.apply_condition("paralyzed", 5)
	p.reset_turn()
	assert_true(Features.use(w, p, "lay_on_hands", ally)["ok"])
	assert_false(ally.has_condition("paralyzed"), "회복의 손길")
	var rg := _pc("ranger", 13)
	rg.concentration = {"spell": "hunters_mark"}
	assert_true(Resolver.concentration_check(rg, 40)["success"], "끈질긴 사냥꾼")


func test_warlock_arcanum_and_wizard_overchannel() -> void:
	var wz := _pc("wizard", 14)
	var foe := make_creature({"team": "enemy", "hp_max": 300})
	var w := make_world(["..............", "..............", ".............."])
	w["grid"].place(wz, Vector2i(0, 1))
	w["grid"].place(foe, Vector2i(10, 1))
	wz.reset_turn()
	wz.options["overchannel"] = "on"
	Dice.force([1])
	assert_true(Spellcasting.cast(w, wz, "fireball", Vector2i(10, 1)).get("ok", false))
	assert_eq(foe.hp, 300 - 48 - wz.ability_mod("int"), "과충전: 화염구 최대 + 강화된 방출")
	assert_eq(str(wz.options["overchannel"]), "off")
	var hp: int = wz.hp
	wz.reset_turn()
	wz.options["overchannel"] = "on"
	Dice.force([1])
	Spellcasting.cast(w, wz, "fireball", Vector2i(10, 1))
	assert_true(wz.hp < hp, "두 번째부터 대가")
