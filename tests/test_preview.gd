extends "res://tests/test_case.gd"
## 미리보기(굴림 없이 확률 계산, 룰북 8단계 판정 순서 끝 문단).

const Resolver := preload("res://scripts/rules/resolver.gd")


func test_hit_probability_formula() -> void:
	assert_near(Resolver.hit_probability(15, 5), 0.55, 0.0001, "(21 − 10) / 20")
	assert_near(Resolver.hit_probability(30, 0), 0.05, 0.0001, "최소 5%(자연 20)")
	assert_near(Resolver.hit_probability(5, 10), 0.95, 0.0001, "최대 95%(자연 1)")


func test_advantage_formula() -> void:
	assert_near(Resolver.apply_mode(0.5, 1), 0.75)
	assert_near(Resolver.apply_mode(0.5, -1), 0.25)
	assert_near(Resolver.apply_mode(0.5, 0), 0.5)


func test_preview_does_not_roll() -> void:
	var a := make_creature()
	var t := make_creature({"ac_base": 12, "hp_max": 10})
	var before := Dice.roll_log.size()
	var atk := {"bonus": 4, "damage": [{"dice": "1d6+2", "damage_type": "piercing"}]}
	var r := Resolver.preview_attack(a, t, atk)
	assert_eq(Dice.roll_log.size(), before, "굴림 기록이 늘지 않는다")
	assert_eq(t.hp, 10)
	assert_eq(r["damage"], {"min": 3.0, "max": 8.0, "avg": 5.5}, "피해 3~8(평균 5.5)")


func test_preview_damage_reflects_resistance() -> void:
	var a := make_creature()
	var t := make_creature({"damage_resistances": ["fire"]})
	var r := Resolver.preview_attack(a, t, {"bonus": 0, "damage": [{"dice": "2d6", "damage_type": "fire"}]})
	assert_eq(r["damage"]["min"], 1.0)
	assert_eq(r["damage"]["max"], 6.0)
	assert_near(r["damage"]["avg"], 3.5)
