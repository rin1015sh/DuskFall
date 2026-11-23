extends "res://tests/test_case.gd"
## 분노 연장(원문): 들어간 턴은 다음 턴 끝까지, 그 턴에 공격·내성 강요·분노 연장이 없으면 턴 끝에 끝난다.

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
	assert_true(Features.use(w, b, "extend_rage")["ok"], "보너스 행동으로 연장")
	w["turns"].end_turn(b)
	assert_true(b.has_condition("raging"))
	b.reset_turn()
	w["turns"].end_turn(b)
	assert_false(b.has_condition("raging"), "아무것도 안 하면 끝난다")
