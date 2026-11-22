extends "res://tests/test_case.gd"
## 범위 템플릿(룰북 4단계 '범위 템플릿', 9단계 E·F).

const Area := preload("res://scripts/rules/area.gd")


func test_circle_counts() -> void:
	assert_eq(Area.circle(null, Vector2i.ZERO, 4).size(), 69, "화염구 20피트 → 69칸")
	assert_eq(Area.circle(null, Vector2i.ZERO, 2).size(), 21, "반경 2칸 → 21칸")
	assert_eq(Area.circle(null, Vector2i.ZERO, 1).size(), 9)


func test_circle_shape_radius_2() -> void:
	var cells := Area.circle(null, Vector2i.ZERO, 2)
	assert_false(Vector2i(2, 2) in cells, "모서리는 빠진다")
	assert_true(Vector2i(2, 1) in cells)
	assert_true(Vector2i(0, 2) in cells)


func test_cone_counts_all_directions() -> void:
	for dir in GridWorldScript.DIRS_8:
		var cells := Area.cone(null, Vector2i.ZERO, dir, 3)
		assert_eq(cells.size(), 7, "15피트 원뿔 → 7칸 (%s)" % str(dir))
		assert_false(Vector2i.ZERO in cells, "시전자 칸은 빠진다")
	var east := Area.cone(null, Vector2i.ZERO, Vector2i(1, 0), 3)
	for c in [Vector2i(1, 0), Vector2i(2, -1), Vector2i(2, 1), Vector2i(3, 1)]:
		assert_true(c in east, "그림의 칸 %s" % str(c))


func test_line_stops_at_wall() -> void:
	assert_eq(Area.line(null, Vector2i.ZERO, Vector2i(1, 0), 20).size(), 20, "100피트 선 → 20칸")
	var g := make_grid(["......#..."])
	var cells := Area.line(g, Vector2i(0, 0), Vector2i(9, 0), 20)
	assert_eq(cells.size(), 5, "벽에서 멈춘다")
	var diag := Area.line(null, Vector2i.ZERO, Vector2i(3, 3), 4)
	assert_eq(diag, [Vector2i(1, 1), Vector2i(2, 2), Vector2i(3, 3), Vector2i(4, 4)])


func test_cube_touches_caster() -> void:
	var cells := Area.cube_from(null, Vector2i.ZERO, Vector2i(1, 0), 3)
	assert_eq(cells.size(), 9, "15피트 정육면체 → 9칸")
	assert_true(Vector2i(1, 0) in cells and Vector2i(1, -1) in cells and Vector2i(3, 1) in cells)
	var diag := Area.cube_from(null, Vector2i.ZERO, Vector2i(1, 1), 3)
	assert_true(Vector2i(1, 1) in diag and Vector2i(3, 3) in diag)


func test_wall_blocks_area() -> void:
	var g := make_grid([
		".......",
		"...#...",
		".......",
	])
	var cells := Area.circle(g, Vector2i(1, 1), 4)
	assert_false(Vector2i(3, 1) in cells, "벽 칸은 빠진다")
	assert_false(Vector2i(4, 1) in cells, "시작점에서 벽으로 막힌 칸은 빠진다")
	assert_true(Vector2i(4, 0) in cells)


func test_emanation_and_large_creature() -> void:
	var g := make_grid([".........", ".........", ".........", "........."])
	var cleric := make_creature()
	var ogre := make_creature()
	g.place(cleric, Vector2i(1, 1))
	g.place(ogre, Vector2i(4, 1), 2)
	var cells := Area.emanation(g, cleric, 3)
	assert_true(Vector2i(1, 1) in cells, "발산 중심은 시전자 칸")
	assert_eq(Area.creatures_in(g, cells).size(), 2, "큰 생물은 점유 칸 하나만 걸려도 포함")
