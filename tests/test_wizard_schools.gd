extends "res://tests/test_case.gd"
## 위저드 BG3 학파(4단계, 2레벨에 고름): 방호·소환·예언·환혹·방출·환영·사령·변환·검무가(칼날노래).

const Builder := preload("res://scripts/rules/character_builder.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Features := preload("res://scripts/rules/features.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Rest := preload("res://scripts/rules/rest.gd")
const SpellPrep := preload("res://scripts/rules/spell_prep.gd")


func _wz(lv: int, sub: String, extra: Dictionary = {}) -> Node:
	var spec := Builder.default_spec("wizard", lv)
	spec["subclass"] = sub
	spec.merge(extra, true)
	var r := Builder.build(spec)
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func _foe(v: Dictionary = {}) -> Node:
	var d := {"team": "enemy", "ac_base": 10, "hp_max": 100, "abilities": {"str": 10, "dex": 10, "con": 10, "wis": 1, "cha": 1}}
	d.merge(v, true)
	return make_creature(d)


const CLUB := {"name": "몽둥이", "bonus": 5, "kind": "melee", "weapon": false, "damage": [{"dice": "8", "damage_type": "bludgeoning"}]}


func test_abjurer_ward() -> void:
	var c := _wz(6, "abjurer")
	assert_eq(c.resource("arcane_ward"), 12, "충전 = 레벨 × 2")
	var out := Resolver.apply_damage(c, [{"amount": 8, "damage_type": "fire"}])
	assert_eq(int(out["total"]), 0, "충전 12가 8을 막는다")
	assert_eq(c.resource("arcane_ward"), 11, "충전 1 잃음")
	assert_eq(SpellPrep.learn_cost("shield", c), 25, "방호학파 옮겨 적기 절반")
	# 투사 결계
	var ally := make_creature({"team": "party", "hp_max": 30})
	var w := make_world(["....."])
	w["grid"].place(c, Vector2i(0, 0))
	w["grid"].place(ally, Vector2i(2, 0))
	c.refresh_reaction()
	Resolver.apply_damage(ally, [{"amount": 8, "damage_type": "fire"}])
	assert_eq(ally.hp, 30, "투사 결계가 막았다")


func test_diviner_portent() -> void:
	var c := _wz(2, "diviner")
	c.set_meta("portent_values", [2, 18])
	var ally := make_creature({"team": "party", "hp_max": 30})
	var e := _foe()
	var w := make_world(["....."])
	w["grid"].place(c, Vector2i(0, 0))
	w["grid"].place(ally, Vector2i(1, 0))
	w["grid"].place(e, Vector2i(2, 0))
	Dice.force([15])
	var r := Resolver.attack(e, ally, CLUB, w["grid"].attack_context(e, ally))
	assert_false(r["hit"], "예지 2로 적 명중을 빗나감으로")
	assert_eq(c.get_meta("portent_values"), [18])
	Dice.force([3])
	var s := Resolver.saving_throw(ally, "wis", 15)
	assert_true(s["success"], "예지 18로 아군 실패를 성공으로")


func test_enchanter_and_illusionist() -> void:
	var c := _wz(6, "enchanter")
	var e := _foe()
	var w := make_world(["....."])
	w["grid"].place(c, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(1, 0))
	c.reset_turn()
	Dice.force([1])
	assert_true(Features.use(w, c, "hypnotic_gaze", e)["success"])
	assert_true(e.has_condition("hypnotized") and e.is_incapacitated())
	e.remove_condition("hypnotized")
	e.remove_condition("charmed")
	c.refresh_reaction()
	Dice.force([1, 1, 18])
	var r := Resolver.attack(e, c, CLUB, w["grid"].attack_context(e, c))
	assert_false(r["hit"], "본능적 매혹: 빗나감")
	var il := _wz(10, "illusionist")
	assert_true(il.spells.has("minor_illusion"))
	assert_eq(Spellcasting._mm_cost(il, RulesDB.get_entry("spell", "minor_illusion")), "bonus", "하급 환영 보너스 행동")
	var w2 := make_world(["....."])
	w2["grid"].place(il, Vector2i(0, 0))
	var e2 := _foe()
	w2["grid"].place(e2, Vector2i(1, 0))
	il.refresh_reaction()
	Dice.force([20])
	var r2 := Resolver.attack(e2, il, CLUB, w2["grid"].attack_context(e2, il))
	assert_false(r2["hit"], "환영 분신: 치명타도 빗나감")


func test_necromancer_and_conjurer() -> void:
	var n := _wz(10, "necromancer")
	assert_true("necrotic" in n.damage_resistances)
	assert_true(n.spells.has("animate_dead"))
	var c := _wz(6, "conjurer")
	var w := make_world(["........"])
	w["grid"].place(c, Vector2i(0, 0))
	c.reset_turn()
	assert_true(Features.use(w, c, "benign_transposition", Vector2i(5, 0))["ok"])
	assert_eq(w["grid"].cell_of(c), Vector2i(5, 0))


func test_transmuter_stone() -> void:
	var c := _wz(6, "transmuter")
	c.options["transmuters_stone"] = "fire"
	var w := make_world(["....."])
	w["grid"].place(c, Vector2i(0, 0))
	c.reset_turn()
	assert_true(Features.use(w, c, "transmuters_stone", c)["ok"])
	assert_true(c.resists("fire"))


func test_bladesinger() -> void:
	var c := _wz(6, "bladesinger", {"weapons": {"melee": {"main": "rapier", "off": ""}, "ranged": {"main": ""}}})
	assert_eq(c.attacks_per_action, 2, "추가 공격")
	assert_true(c.weapon_proficiencies.has("rapier") and "light" in c.get_meta("armor_training"))
	var ac0: int = c.ac()
	var con0: int = c.save_bonus("con")
	var w := make_world(["....."])
	w["grid"].place(c, Vector2i(0, 0))
	c.reset_turn()
	assert_true(Features.use(w, c, "bladesong")["ok"])
	assert_eq(c.ac(), ac0 + 2)
	assert_eq(c.save_bonus("con"), con0 + 2)
