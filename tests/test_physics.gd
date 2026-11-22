extends "res://tests/test_case.gd"
## 밀치기·낙하·던지기·물약 던지기(룰북 3단계 밀치기, 4단계 위치·물리, 2단계 낙하, 9단계 물약).

const Physics := preload("res://scripts/rules/physics.gd")


func _shover(str_score: int = 17) -> Node:
	return make_creature({"abilities": {"str": str_score}, "proficiency_bonus": 2})


func test_shove_distance_bands() -> void:
	# 근력 17 → 한계 204kg
	var cases := [[20.0, 4], [51.0, 4], [52.0, 3], [102.0, 3], [103.0, 2], [153.0, 2], [154.0, 1], [204.0, 1]]
	for case: Array in cases:
		var g := make_grid(["........."])
		var f := _shover()
		var t := make_creature({"weight_kg": case[0]})
		g.place(f, Vector2i(0, 0))
		g.place(t, Vector2i(1, 0))
		assert_eq(Physics.plan_shove(g, f, t)["distance"], case[1], "%.0fkg" % case[0])


func test_shove_too_heavy() -> void:
	var g := make_grid(["...."])
	var f := _shover()
	var ogre := make_creature({"weight_kg": 300.0})
	g.place(f, Vector2i(0, 0))
	g.place(ogre, Vector2i(1, 0))
	assert_false(Physics.plan_shove(g, f, ogre)["valid"], "근력 × 12kg보다 무거우면 못 민다")


func test_shove_save_and_ally() -> void:
	var g := make_grid(["......."])
	var f := _shover()
	var t := make_creature({"weight_kg": 20.0, "abilities": {"str": 8, "dex": 14}})
	g.place(f, Vector2i(0, 0))
	g.place(t, Vector2i(1, 0))
	var p := Physics.preview_shove(g, f, t)
	assert_eq(p["dc"], 13, "DC 8 + 근력 3 + 숙련 2")
	assert_near(p["chance"], 0.5, 0.0001, "나은 쪽(민첩 +2)으로 내성: 11 이상 성공 → 실패 50%")
	Dice.force([15])
	assert_false(Physics.shove(g, f, t)["success"], "내성 성공이면 안 밀린다")
	assert_eq(g.cell_of(t), Vector2i(1, 0))
	var r := Physics.shove(g, f, t, true)
	assert_true(r["success"], "아군은 판정 없이")
	assert_eq(g.cell_of(t), Vector2i(5, 0), "4칸")


func test_shove_blocked_path_means_no_push() -> void:
	var g := make_grid(["...#..."])
	var f := _shover()
	var t := make_creature({"weight_kg": 20.0})
	g.place(f, Vector2i(0, 0))
	g.place(t, Vector2i(1, 0))
	var p := Physics.plan_shove(g, f, t)
	assert_false(p["valid"], "중간이 막히면 밀리지 않는다(changes.md)")
	var g2 := make_grid(["..1...."])
	g2.place(f, Vector2i(0, 0))
	g2.place(t, Vector2i(1, 0))
	assert_false(Physics.plan_shove(g2, f, t)["valid"], "더 높은 칸으로는 못 민다")


func test_shove_off_ledge_falls() -> void:
	var g := make_grid(["4400000"])
	var f := _shover()
	var t := make_creature({"weight_kg": 70.0, "hp_max": 30, "abilities": {"str": 8, "dex": 8}})
	g.place(f, Vector2i(0, 0))
	g.place(t, Vector2i(1, 0))
	var p := Physics.plan_shove(g, f, t)
	assert_eq(p["distance"], 3, "70 / 204 = 34% → 50% 이하 3칸")
	assert_eq(p["landing"], Vector2i(4, 0))
	assert_eq(p["fall_levels"], 4, "낮은 칸으로 밀리면 낙하")
	Dice.force([2, 3, 4])  # 내성 2 실패, 낙하 4단계 = 2d6 → 3 + 4
	var r := Physics.shove(g, f, t)
	assert_true(r["success"])
	assert_eq(r["fall"]["damage"], 7)
	assert_true(t.has_condition("prone"), "낙하 피해를 받으면 넘어짐")


func test_shove_landing_surface_applies() -> void:
	var g := make_grid(["......"])
	var s := make_surfaces(g)
	s.place_surface([Vector2i(5, 0)], "water")
	s.place_surface([Vector2i(3, 0)], "poison")
	var f := _shover()
	var t := make_creature({"weight_kg": 20.0})
	g.place(f, Vector2i(0, 0))
	g.place(t, Vector2i(1, 0))
	Physics.shove(g, f, t, true)
	assert_true(t.has_condition("wet"), "착지 칸 표면 효과를 즉시")
	assert_eq(t.hp, t.hp_max, "지나간 칸의 표면은 받지 않는다")


func test_fall_damage() -> void:
	var c := make_creature({"hp_max": 200})
	assert_eq(Physics.fall(c, 1)["damage"], 0, "1단계(5피트)는 피해 없음")
	assert_false(c.has_condition("prone"), "피해가 없으면 넘어지지 않는다")
	Dice.force([6, 6])
	assert_eq(Physics.fall(c, 5)["dice"], 2, "2단계마다 1d6 → 5단계는 2d6")
	assert_eq(Physics.fall(c, 100)["dice"], 20, "최대 20d6")


func test_on_fall_can_prevent() -> void:
	var c := make_creature({"hp_max": 50})
	var feather := func(ctx: Dictionary) -> void: ctx["prevented"] = true
	EventBus.on_fall.connect(feather)
	var r := Physics.fall(c, 10)
	EventBus.on_fall.disconnect(feather)
	assert_true(r["prevented"])
	assert_eq(c.hp, 50, "Feather Fall 같은 반응이 낙하 피해를 막는다")


func test_throw_damage_and_limits() -> void:
	assert_eq(Physics.throw_damage_dice(9.9), "1")
	assert_eq(Physics.throw_damage_dice(10.0), "1d4")
	assert_eq(Physics.throw_damage_dice(50.0), "1d4")
	assert_eq(Physics.throw_damage_dice(50.1), "2d4")
	assert_near(Physics.max_throw_kg(_shover(15)), 45.0, 0.001, "0.2 × 15²")


func test_throw_push_and_prone() -> void:
	var g := make_grid(["....."])
	var thrower := _shover()
	var gob := make_creature({"weight_kg": 20.0, "hp_max": 20})
	g.place(thrower, Vector2i(0, 0))
	g.place(gob, Vector2i(2, 0))
	Dice.force([3])
	var r := Physics.throw_hit(g, thrower, gob, 15.0)
	assert_true(r["pushed"], "대상 무게의 절반을 넘으면 1칸 밀림")
	assert_eq(g.cell_of(gob), Vector2i(3, 0))
	assert_false(r["prone"])
	Dice.force([1])
	r = Physics.throw_hit(g, thrower, gob, 25.0)
	assert_true(r["prone"], "대상보다 무거우면 넘어짐")


func test_throw_potion_cross() -> void:
	var g := make_grid([".....", ".....", "....."])
	var a := make_creature({"hp_max": 20, "hp": 5})
	var b := make_creature({"hp_max": 20, "hp": 5})
	var far := make_creature({"hp_max": 20, "hp": 5})
	g.place(a, Vector2i(2, 1))
	g.place(b, Vector2i(3, 1))
	g.place(far, Vector2i(3, 2))
	a.apply_condition("burning")
	Dice.force([2, 3])
	var hit: Array = Physics.throw_potion(g, Vector2i(2, 1), [{"type": "heal", "dice": "2d4+2"}], a)
	assert_eq(hit.size(), 2, "착지 칸 + 직교 4칸, 대각선 제외")
	assert_eq(a.hp, 11, "5 − 1(직접 맞음) + 7")
	assert_eq(b.hp, 12, "전체 효과")
	assert_eq(far.hp, 5)
	assert_false(a.has_condition("burning"), "연소 해제")
