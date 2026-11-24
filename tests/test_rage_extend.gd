extends "res://tests/test_case.gd"
## 분노 유지(BG3): 들어간 턴은 이어지고, 턴마다 적을 공격하거나 피해를 받지 않으면 턴 끝에 끝난다. 10턴.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Features := preload("res://scripts/rules/features.gd")
const Combat := preload("res://scripts/rules/combat.gd")


func test_rage_needs_upkeep() -> void:
	var w := make_world(["......"])
	var b: Node = own(Builder.build(Builder.default_spec("barbarian", 3))["creature"])
	var f := make_creature({"team": "enemy", "hp_max": 80, "ac_base": 5})
	w["grid"].place(b, Vector2i(0, 0))
	w["grid"].place(f, Vector2i(1, 0))
	w["turns"].start_manual([b])
	b.reset_turn()
	Features.use(w, b, "rage")
	w["turns"].end_turn(b)
	assert_true(b.has_condition("raging"), "들어간 턴은 이어진다")
	b.reset_turn()
	Dice.force([15, 3])
	Combat.attack(w, b, f, {"weapon": "greataxe"})
	w["turns"].end_turn(b)
	assert_true(b.has_condition("raging"), "적을 공격하면 이어진다")
	b.reset_turn()
	load("res://scripts/rules/resolver.gd").apply_damage(b, [{"amount": 2, "damage_type": "fire"}], {"attacker": f})
	w["turns"].end_turn(b)
	assert_true(b.has_condition("raging"), "피해를 받아도 이어진다(BG3)")
	b.reset_turn()
	w["turns"].end_turn(b)
	assert_false(b.has_condition("raging"), "아무것도 안 하면 끝난다")
