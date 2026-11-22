extends "res://tests/test_case.gd"
## GridWorld: 거리, 대각선·벽 모서리, 높이 이동, 어려운 지형, 경로, 큰 생물(룰북 3단계 이동, 4단계, 9단계 E).


func test_distance_is_chebyshev() -> void:
	assert_eq(GridWorldScript.distance(Vector2i(0, 0), Vector2i(3, 2)), 3)
	assert_eq(GridWorldScript.distance(Vector2i(1, 1), Vector2i(2, 2)), 1, "대각선 1칸")


func test_distance_between_large_creature() -> void:
	var g := make_grid([".....", ".....", ".....", "....."])
	var ogre := make_creature()
	var pc := make_creature()
	g.place(ogre, Vector2i(0, 0), 2)
	g.place(pc, Vector2i(2, 1))
	assert_eq(g.distance_between(ogre, pc), 1, "점유 칸 둘레에서 잰다")
	assert_eq(g.occupied_cells(ogre).size(), 4)
	assert_eq(g.creature_at(Vector2i(1, 1)), ogre)


func test_diagonal_corner_rule() -> void:
	var g := make_grid(["..", "#."])
	assert_false(g.can_step(Vector2i(0, 0), Vector2i(1, 1)), "양옆 중 하나라도 벽이면 대각선 불가")
	var g2 := make_grid(["..", ".."])
	assert_true(g2.can_step(Vector2i(0, 0), Vector2i(1, 1)))
	var cr := make_creature()
	g2.place(cr, Vector2i(1, 0))
	assert_true(g2.can_step(Vector2i(0, 0), Vector2i(1, 1)), "생물은 모서리로 치지 않는다")


func test_height_steps() -> void:
	var g := make_grid(["0123", "0300"])
	assert_true(g.can_step(Vector2i(0, 0), Vector2i(1, 0)), "1단계는 그냥 걷는다")
	assert_eq(g.step_cost(Vector2i(0, 0), Vector2i(1, 0)), 1, "추가 비용 없음")
	assert_false(g.can_step(Vector2i(0, 1), Vector2i(1, 1)), "3단계 오르기는 오르기 지점만")
	g.set_flag(Vector2i(1, 1), "climb")
	assert_true(g.can_step(Vector2i(0, 1), Vector2i(1, 1)))
	assert_eq(g.step_cost(Vector2i(0, 1), Vector2i(1, 1)), 4, "1칸 + 높이 3단계")
	assert_false(g.can_step(Vector2i(1, 1), Vector2i(2, 1)), "2단계 이상 내려가기는 걷기로 불가")


func test_difficult_terrain_costs_double() -> void:
	var g := make_grid(["...."])
	g.set_flag(Vector2i(1, 0), "difficult")
	assert_eq(g.step_cost(Vector2i(0, 0), Vector2i(1, 0)), 2)
	g.set_surface(Vector2i(2, 0), {"id": "mud", "turns_left": -1, "source": null, "dc": 12})
	assert_eq(g.step_cost(Vector2i(1, 0), Vector2i(2, 0)), 2, "진흙 표면도 어려운 지형")


func test_find_path_around_walls() -> void:
	var g := make_grid([
		".....",
		".###.",
		".....",
	])
	var cr := make_creature()
	g.place(cr, Vector2i(0, 1))
	var p: Dictionary = g.find_path(cr, Vector2i(4, 1))
	assert_eq(p["cost"], 6, "벽 모서리를 대각선으로 못 끊어 6칸")
	assert_eq(p["path"].back(), Vector2i(4, 1))
	assert_eq(g.find_path(cr, Vector2i(4, 1), 5), {}, "이동력 5로는 못 간다")


func test_path_blocked_by_creatures() -> void:
	var g := make_grid(["#.#", "...", "#.#"])
	var a := make_creature()
	var b := make_creature()
	g.place(a, Vector2i(1, 0))
	g.place(b, Vector2i(1, 1))
	assert_eq(g.find_path(a, Vector2i(1, 2)), {}, "다른 생물 칸은 지나갈 수 없다")
	assert_false(g.find_path(a, Vector2i(1, 2), -1, [b]).is_empty(), "ignore로 예외")


func test_large_creature_needs_room() -> void:
	var g := make_grid([
		"......",
		"......",
		"###.##",
		"......",
		"......",
	])
	var ogre := make_creature()
	g.place(ogre, Vector2i(0, 0), 2)
	assert_eq(g.find_path(ogre, Vector2i(0, 3)), {}, "1칸 통로는 2×2가 지나갈 수 없다")
	g.set_flag(Vector2i(4, 2), "wall", false)
	assert_false(g.find_path(ogre, Vector2i(0, 3)).is_empty(), "2칸 통로는 지나간다")


func test_move_emits_tile_hooks() -> void:
	var g := make_grid(["..."])
	var cr := make_creature()
	g.place(cr, Vector2i(0, 0))
	var seen: Array = []
	var on_leave := func(_c: Object, cell: Vector2i) -> void: seen.append(["leave", cell])
	var on_enter := func(_c: Object, cell: Vector2i) -> void: seen.append(["enter", cell])
	EventBus.on_leave_tile.connect(on_leave)
	EventBus.on_enter_tile.connect(on_enter)
	g.move_creature(cr, Vector2i(2, 0))
	EventBus.on_leave_tile.disconnect(on_leave)
	EventBus.on_enter_tile.disconnect(on_enter)
	assert_eq(seen, [["leave", Vector2i(0, 0)], ["enter", Vector2i(2, 0)]])
