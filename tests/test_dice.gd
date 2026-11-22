extends "res://tests/test_case.gd"
## Dice 오토로드와 주사위 식(룰북 8단계 Dice, 2단계 공통 처리 규칙 5 로그).

const DiceExpr := preload("res://scripts/rules/dice_expr.gd")


func test_parse_expressions() -> void:
	assert_eq(DiceExpr.parse("2d6+3"), {"dice": [{"count": 2, "sides": 6, "sign": 1}], "flat": 3})
	assert_eq(DiceExpr.parse("-1d4"), {"dice": [{"count": 1, "sides": 4, "sign": -1}], "flat": 0})
	assert_eq(DiceExpr.parse("5")["flat"], 5)
	assert_eq(DiceExpr.parse("1d6+1d4+2")["dice"].size(), 2)
	for bad in ["", "d6", "2d", "2d6+", "2d6x3", "0d6", "1d6 2"]:
		assert_eq(DiceExpr.parse(bad), {}, "잘못된 식 '%s'" % bad)


func test_stats() -> void:
	assert_eq(DiceExpr.stats("1d6+2"), {"min": 3.0, "max": 8.0, "avg": 5.5})
	assert_eq(DiceExpr.stats("2d4+4"), {"min": 6.0, "max": 12.0, "avg": 9.0})
	assert_eq(DiceExpr.stats("1d8", true), {"min": 2.0, "max": 16.0, "avg": 9.0}, "치명타는 주사위만 2배")
	assert_eq(DiceExpr.stats("1d6+2", true)["max"], 14.0, "치명타에 수정치는 그대로")


func test_seed_is_deterministic() -> void:
	Dice.set_seed(42)
	var a: Array = []
	for i in 20:
		a.append(Dice.die(20))
	Dice.set_seed(42)
	var b: Array = []
	for i in 20:
		b.append(Dice.die(20))
	assert_eq(a, b, "같은 시드 → 같은 눈")


func test_force_and_advantage() -> void:
	Dice.force([5, 17])
	assert_eq(Dice.d20(1)["natural"], 17, "유리는 높은 쪽")
	Dice.force([5, 17])
	assert_eq(Dice.d20(-1)["natural"], 5, "불리는 낮은 쪽")
	Dice.force([9])
	var r := Dice.d20(0)
	assert_eq(r["rolls"].size(), 1, "보통은 하나만")


func test_crit_doubles_dice_only() -> void:
	Dice.force([3, 4])
	var r := Dice.roll("1d6+2", "", true)
	assert_eq(r["rolls"], [3, 4])
	assert_eq(r["total"], 9, "3 + 4 + 2")


func test_every_roll_is_logged() -> void:
	Dice.set_seed(1)
	Dice.d20(0, "a")
	Dice.roll("2d6", "b")
	Dice.log_text("요약")
	assert_eq(Dice.roll_log.size(), 3)
	assert_eq(Dice.roll_log[1]["reason"], "b")
