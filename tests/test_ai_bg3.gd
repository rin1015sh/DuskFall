extends "res://tests/test_case.gd"
## AI BG3 결정(changes.md 2026-11-24): 무기 액션 사용, 명중 −5 / 피해 +10 재주 켜기 판단.

const Builder := preload("res://scripts/rules/character_builder.gd")
const AI := preload("res://scripts/ai/simple_ai.gd")


func _fighter(extra: Dictionary = {}) -> Node:
	var spec := Builder.default_spec("fighter", 5)
	spec["species"] = "human"
	spec.merge(extra, true)
	var r := Builder.build(spec)
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func test_accuracy_trade_toggle() -> void:
	var f := _fighter({"asi": {"4": {"feat": "great_weapon_master"}}, "shield": false, "weapons": {"melee": {"main": "greatsword", "off": ""}, "ranged": {"main": ""}}})
	assert_true(f.feature_data.has("great_weapon_master"), "재주")
	var w := make_world(["....."])
	var weak := make_creature({"team": "enemy", "hp_max": 50, "ac_base": 8})
	w["grid"].place(f, Vector2i(0, 0))
	w["grid"].place(weak, Vector2i(1, 0))
	AI.decide_toggles(w, f, weak)
	assert_eq(str(f.options.get("great_weapon_master")), "on", "AC 낮으면 켠다")
	weak.ac_base = 25
	f.crit_threshold = 20  # 치명타 눈이 넓으면(챔피언 19) 치명타는 늘 맞아 켜는 편이 낫다 — 여기서는 20만
	AI.decide_toggles(w, f, weak)
	assert_eq(str(f.options.get("great_weapon_master")), "off", "AC 높으면 끈다")


func test_weapon_action_used() -> void:
	var f := _fighter()
	var w := make_world(["....."])
	var e := make_creature({"team": "enemy", "hp_max": 80, "ac_base": 5})
	w["grid"].place(f, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(1, 0))
	f.reset_turn()
	var list: Array = load("res://scripts/rules/actions.gd").weapon_actions_for(f)
	assert_false(list.is_empty(), "무기 액션이 있다")
	Dice.force([15, 4, 4, 1, 1])
	assert_true(AI.try_weapon_action(w, f, e), "무기 액션을 쓴다")
	assert_false(AI.try_weapon_action(w, f, e), "턴당 하나")
