extends "res://tests/test_case.gd"
## 상태이상과 중첩 규칙(룰북 4단계 '상태이상', '중첩 규칙').


func test_same_condition_keeps_longest() -> void:
	var c := make_creature()
	c.apply_condition("poisoned", 3)
	c.apply_condition("poisoned", 1)
	assert_eq(c.conditions.size(), 1, "겹치지 않는다")
	assert_eq(c.condition_instance("poisoned")["turns_left"], 3, "짧은 쪽은 무시")
	c.apply_condition("poisoned", 5)
	assert_eq(c.condition_instance("poisoned")["turns_left"], 5, "긴 쪽으로 바뀜")
	c.apply_condition("poisoned", -1)
	assert_eq(c.condition_instance("poisoned")["turns_left"], -1, "풀릴 때까지가 가장 길다")


func test_tick_removes_expired() -> void:
	var c := make_creature()
	c.apply_condition("poisoned", 1)
	c.apply_condition("blinded", 2)
	c.tick_conditions()
	assert_false(c.has_condition("poisoned"))
	assert_true(c.has_condition("blinded"))


func test_includes_incapacitated() -> void:
	var c := make_creature()
	for id in ["paralyzed", "petrified", "stunned", "unconscious"]:
		c.conditions.clear()
		c.apply_condition(id, -1)
		assert_true(c.is_incapacitated(), "%s → 무력화" % id)
	c.conditions.clear()
	c.apply_condition("prone", -1)
	assert_false(c.is_incapacitated(), "넘어짐은 무력화가 아님")


func test_unconscious_leaves_prone() -> void:
	var c := make_creature()
	c.apply_condition("unconscious", -1)
	assert_true(c.has_condition("prone"), "무의식이면 넘어짐도 걸린다")
	c.remove_condition("unconscious")
	assert_true(c.has_condition("prone"), "무의식이 풀려도 넘어짐은 남는다(원문)")


func test_speed_zero_and_auto_fail_saves() -> void:
	var c := make_creature({"speed_tiles": 6})
	assert_eq(c.speed(), 6)
	c.apply_condition("restrained", -1)
	assert_eq(c.speed(), 0, "속박 → 속도 0")
	assert_false(c.auto_fails_save("dex"), "속박은 민첩 내성 불리일 뿐")
	c.apply_condition("stunned", -1)
	assert_true(c.auto_fails_save("str") and c.auto_fails_save("dex"))
	assert_false(c.auto_fails_save("con"))


func test_petrified_resists_all_and_immune_to_poison() -> void:
	var c := make_creature()
	c.apply_condition("petrified", -1)
	assert_true(c.resists("fire") and c.resists("slashing"), "모든 피해 저항")
	assert_false(c.apply_condition("poisoned", 3), "중독 면역")


func test_wet_and_burning_exclusive() -> void:
	var c := make_creature()
	c.apply_condition("burning")
	assert_eq(c.condition_instance("burning")["turns_left"], 2, "연소 기본 2턴")
	c.apply_condition("wet")
	assert_false(c.has_condition("burning"), "젖으면 연소가 풀린다")
	assert_false(c.apply_condition("burning"), "젖은 동안 연소 면역")
	assert_true(c.resists("fire"), "젖음: 화염 저항")
	assert_true(c.vulnerable_to("cold") and c.vulnerable_to("lightning"), "젖음: 냉기·번개 취약")


func test_wet_removes_invisible_and_coating() -> void:
	var c := make_creature()
	c.apply_condition("invisible", -1, "hide")
	c.apply_condition("coated_weapon", 0, null, {"damage_type": "poison"})
	c.apply_condition("wet")
	assert_false(c.has_condition("invisible"), "젖으면 투명 해제")
	assert_false(c.has_condition("coated_weapon"), "젖으면 무기 담금 제거")


func test_acid_lowers_ac() -> void:
	var c := make_creature({"ac_base": 15})
	c.apply_condition("acid")
	assert_eq(c.ac(), 13, "산: AC −2")


func test_incapacitated_breaks_concentration() -> void:
	var c := make_creature()
	c.start_concentration("bless")
	c.apply_condition("prone", -1)
	assert_true(c.concentration.is_empty(), "BG3: 넘어지면 집중이 끊긴다")
	c.apply_condition("stunned", 1)
	assert_true(c.concentration.is_empty(), "무력화 → 집중 깨짐")


func test_outlined_suppresses_invisible() -> void:
	var c := make_creature()
	c.apply_condition("invisible", -1)
	assert_true(c.has_condition("invisible"))
	c.apply_condition("outlined", 10)
	assert_false(c.has_condition("invisible"), "윤곽이 있으면 투명 효과 없음")


func test_condition_signals() -> void:
	var c := make_creature()
	var seen: Array = []
	var on_apply := func(_cr: Object, id: String) -> void: seen.append("+" + id)
	var on_remove := func(_cr: Object, id: String) -> void: seen.append("-" + id)
	EventBus.on_condition_applied.connect(on_apply)
	EventBus.on_condition_removed.connect(on_remove)
	c.apply_condition("prone", -1)
	c.remove_condition("prone")
	EventBus.on_condition_applied.disconnect(on_apply)
	EventBus.on_condition_removed.disconnect(on_remove)
	assert_eq(seen, ["+prone", "-prone"])
