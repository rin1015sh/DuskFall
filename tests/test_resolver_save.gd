extends "res://tests/test_case.gd"
## 내성 굴림·능력 판정·내성 강요 효과(룰북 2단계 공통 처리 규칙 1, 결정 1, 4단계 상태이상).

const Resolver := preload("res://scripts/rules/resolver.gd")


func test_general_save_has_no_natural_rules() -> void:
	var c := make_creature({"abilities": {"dex": 10}})
	Dice.force([20])
	assert_false(Resolver.saving_throw(c, "dex", 25)["success"], "일반 내성은 자연 20 자동 성공 없음")
	c.abilities["dex"] = 30
	Dice.force([1])
	assert_true(Resolver.saving_throw(c, "dex", 10)["success"], "자연 1 자동 실패 없음(1 + 10 = 11)")


func test_dialogue_save_natural_rules() -> void:
	var c := make_creature()
	Dice.force([20])
	assert_true(Resolver.saving_throw(c, "wis", 25, {"natural_rules": true})["success"])


func test_auto_fail_str_dex_saves() -> void:
	var c := make_creature({"abilities": {"dex": 30}})
	c.apply_condition("paralyzed", -1)
	var r := Resolver.saving_throw(c, "dex", 5)
	assert_true(r["auto"] and not r["success"], "마비: 민첩 내성 자동 실패")
	assert_eq(Resolver.preview_save_fail(c, "dex", 5), 1.0)


func test_restrained_dex_save_disadvantage() -> void:
	var c := make_creature()
	c.apply_condition("restrained", -1)
	Dice.force([15, 4])
	var r := Resolver.saving_throw(c, "dex", 10)
	assert_eq(r["mode"], -1)
	assert_eq(r["natural"], 4)
	Dice.force([15])
	assert_eq(Resolver.saving_throw(c, "con", 10)["mode"], 0, "민첩 내성만 불리")


func test_save_fail_preview() -> void:
	var c := make_creature({"abilities": {"dex": 14}, "proficiency_bonus": 2})
	# 보너스 +2, DC 13 → 11 이상 성공 = 50%
	assert_near(Resolver.preview_save_fail(c, "dex", 13), 0.5)
	assert_near(Resolver.preview_save_fail(c, "dex", 30), 1.0, 0.0001, "일반 내성은 0~100%")
	assert_near(Resolver.preview_save_fail(c, "dex", 2), 0.0)
	c.apply_condition("restrained", -1)
	assert_near(Resolver.preview_save_fail(c, "dex", 13), 0.75, 0.0001, "불리: 성공 0.5² → 실패 0.75")


func test_save_effect_rolls_damage_once_and_halves() -> void:
	var a := make_creature({"hp_max": 50, "abilities": {"dex": 10}})
	var b := make_creature({"hp_max": 50, "abilities": {"dex": 10}})
	# a 실패(5), b 성공(18). 피해 8d6은 한 번만: 강제 8개
	Dice.force([5, 18, 3, 3, 3, 3, 3, 3, 3, 3])
	var fire := [{"type": "damage", "dice": "8d6", "damage_type": "fire"}]
	var half := [{"type": "damage", "dice": "8d6", "damage_type": "fire", "scale": 0.5}]
	var r := Resolver.save_effect([a, b], {"ability": "dex", "dc": 15}, fire, half)
	assert_eq(Dice.forced_left(), 0, "피해 주사위는 한 번만 굴린다")
	assert_eq(a.hp, 26, "실패 24")
	assert_eq(b.hp, 38, "성공 절반 12")
	assert_eq(r.size(), 2)


func test_save_effect_applies_condition_on_fail() -> void:
	var c := make_creature({"abilities": {"wis": 10}})
	Dice.force([3])
	Resolver.save_effect([c], {"ability": "wis", "dc": 13}, [{"type": "apply_condition", "id": "paralyzed"}])
	assert_true(c.has_condition("paralyzed"))


func test_ability_check_natural_rules() -> void:
	var c := make_creature({"abilities": {"str": 10}})
	Dice.force([20])
	assert_true(Resolver.ability_check(c, "str", 30)["success"], "능력 판정은 자연 20 자동 성공")
	c.abilities["str"] = 30
	Dice.force([1])
	assert_false(Resolver.ability_check(c, "str", 5)["success"], "자연 1 자동 실패")


func test_ability_check_conditions() -> void:
	var c := make_creature()
	c.apply_condition("poisoned", -1)
	Dice.force([17, 6])
	assert_eq(Resolver.ability_check(c, "dex", 10)["mode"], -1, "중독: 능력 판정 불리")
	c.apply_condition("blinded", -1)
	assert_true(Resolver.ability_check(c, "wis", 5, {"requires_sight": true})["auto"], "실명: 시각 판정 자동 실패")


func test_failed_check_emits_hook() -> void:
	var c := make_creature()
	var count := [0]
	var f := func(_r: Dictionary) -> void: count[0] += 1
	EventBus.on_check_failed.connect(f)
	Dice.force([2])
	Resolver.ability_check(c, "int", 15)
	EventBus.on_check_failed.disconnect(f)
	assert_eq(count[0], 1)
