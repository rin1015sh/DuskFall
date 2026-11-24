extends "res://tests/test_case.gd"
## BG3 수치 우선(2026-11-24): 이니셔티브 d4, 경험치 표, 사거리 상한 12칸·먼 사거리 없음, 던지기 거리 공식(룰북 3·6·7단계).

const Physics := preload("res://scripts/rules/physics.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Levels := preload("res://scripts/rules/levels.gd")


func _str(score: int) -> Node:
	return make_creature({"team": "party", "abilities": {"str": score}, "hp_max": 10})


func test_initiative_is_d4_plus_dex() -> void:
	var w := make_world(["......"])
	var c := make_creature({"team": "party", "is_player_character": true, "abilities": {"dex": 16}, "hp_max": 10})
	w["grid"].place(c, Vector2i(0, 0))
	Dice.force([4, 1])
	assert_eq(w["turns"].roll_initiative(c), 7, "d4 4 + 민첩 3")
	var rolled := Dice.roll_log.filter(func(e: Dictionary) -> bool: return e["kind"] == "d4")
	assert_eq(rolled.size(), 1, "이니셔티브는 d4로 굴린다")
	c.initiative_bonus = 5  # 경계
	Dice.force([1, 1])
	assert_eq(w["turns"].roll_initiative(c), 9, "d4 1 + 민첩 3 + 경계 5")
	for i in 50:
		var v: int = w["turns"].roll_initiative(c)
		assert_true(v >= 9 and v <= 12, "d4 범위")


func test_xp_table_bg3() -> void:
	var expected := {2: 300, 3: 900, 4: 2700, 5: 6500, 6: 13000, 7: 21000, 8: 30000, 9: 42000, 10: 56000, 11: 76000, 12: 100000}
	for lv: int in expected:
		assert_eq(Levels.xp_for(lv), expected[lv], "%d레벨 경험치" % lv)
	assert_eq(Levels.level_for(12999), 5)
	assert_eq(Levels.level_for(13000), 6)


func test_throw_range_formula() -> void:
	# round(3 + 15 × (근력²/5 − 무게) / (2 × 무게)) m, 3~18m → 칸(1.5m) 내림
	assert_eq(Physics.throw_range_tiles(_str(10), 0.45), 12, "단검 무게면 18m 상한")
	assert_eq(Physics.throw_range_tiles(_str(8), 10.0), 3, "5m → 3칸")
	assert_eq(Physics.throw_range_tiles(_str(10), 10.0), 7, "10.5 → 11m → 7칸")
	assert_eq(Physics.throw_range_tiles(_str(10), 20.0), 2, "3m 하한 → 2칸")
	assert_eq(Physics.throw_range_tiles(_str(10), 40.0), 2, "하한 아래도 2칸")


func test_throw_object_uses_formula() -> void:
	var w := make_world(["..............."])
	var c := _str(10)
	var t := make_creature({"team": "enemy", "hp_max": 30})
	w["grid"].place(c, Vector2i(0, 0))
	w["grid"].place(t, Vector2i(8, 0))
	c.reset_turn()
	assert_eq(Combat.throw_object(w, c, t, 10.0).get("reason", ""), "사거리 밖", "10kg는 7칸까지")
	w["grid"].move_creature(t, Vector2i(7, 0))
	Dice.force([15])
	assert_true(Combat.throw_object(w, c, t, 10.0).get("ok", false), "7칸이면 닿는다")


func test_gear_throw_range_is_formula_not_fixed() -> void:
	var c := _str(10)
	var fire := RulesDB.get_entry("item", "alchemists_fire")
	assert_false(fire.get("use", {}).get("throw", {}).has("range_tiles"), "고정 4칸 삭제")
	assert_eq(Combat.gear_throw_range(c, fire), 12, "0.45kg — 12칸")


func test_ranges_capped_at_12_and_no_long_range() -> void:
	for wpn: Dictionary in RulesDB.entries("weapon"):
		if not wpn.has("range_tiles"):
			continue
		var r: Array = wpn["range_tiles"]
		assert_true(int(r[0]) <= 12, "%s 정상 사거리 12칸 이하" % wpn["id"])
		assert_eq(int(r[0]), int(r[1]), "%s 먼 사거리 없음" % wpn["id"])
	assert_eq(Array(RulesDB.get_entry("weapon", "longbow")["range_tiles"]).map(func(x: Variant) -> int: return int(x)), [12, 12], "장궁 18m")
	assert_eq(Array(RulesDB.get_entry("weapon", "hand_crossbow")["range_tiles"]).map(func(x: Variant) -> int: return int(x)), [10, 10], "손 석궁 15m")
	assert_eq(Array(RulesDB.get_entry("weapon", "javelin")["range_tiles"]).map(func(x: Variant) -> int: return int(x)), [12, 12], "던지는 무기 12칸")
	for sp: Dictionary in RulesDB.entries("spell"):
		if str(sp["range"]["type"]) == "tiles":
			assert_true(int(sp["range"]["tiles"]) <= 12, "%s 주문 사거리 12칸 이하" % sp["id"])
	assert_eq(int(RulesDB.get_entry("spell", "fireball")["range"]["tiles"]), 12, "화염구 18m")
