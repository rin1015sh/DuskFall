extends "res://tests/test_case.gd"
## 4단계 표현 계층: 쿼터뷰 좌표, 바닥 타일맵 정렬, 입력 상태기계(마우스·터치 같은 의미 신호).

const V := preload("res://scenes/battle/view3q.gd")
const InputRouter := preload("res://scenes/battle/input_router.gd")
const MapView := preload("res://scenes/battle/map_view.gd")
const DungeonKit := preload("res://scenes/kit/dungeon_kit.gd")


func test_view3q_ground_and_pick() -> void:
	assert_eq(V.ground(Vector2i(0, 0)), Vector2(32, 32), "칸 중심")
	assert_eq(V.ground(Vector2i(2, 1)), Vector2(160, 96))
	var g := make_grid(["....", "..2.", "...."])
	assert_eq(V.pick(g, V.ground(Vector2i(1, 2))), Vector2i(1, 2))
	assert_eq(V.pick(g, V.top(Vector2i(2, 1), 2)), Vector2i(2, 1), "높은 칸은 올라간 윗면으로 고른다")
	var w := make_grid(["...", ".#.", "..."])
	assert_eq(V.pick(w, V.ground(Vector2i(1, 1)) - Vector2(0, V.WALL_H)), Vector2i(1, 1), "벽은 꼭대기로 고른다")


func test_dungeon_kit_loads() -> void:
	var kit: RefCounted = DungeonKit.open()
	assert_eq(kit.px, 64, "키트 한 칸 64px")
	assert_true(kit.has("floor_flag") and kit.has("wall_stone") and kit.has("brazier"))
	assert_true(kit.texture("brazier", "lit") != null, "키트 그림")


func test_floor_tilemap_aligned_with_view() -> void:
	var g := make_grid(["....", "...."])
	var view: Node2D = own(MapView.new())
	var sorted: Node2D = own(Node2D.new())
	view.add_child(sorted)
	view.build(g, sorted, {})
	var layer: TileMapLayer = view._floors[0]
	for c in [Vector2i(0, 0), Vector2i(3, 1)]:
		assert_eq(layer.position + layer.map_to_local(c), V.ground(c), "바닥 타일 중심 = 칸 중심 %s" % str(c))
		assert_true(layer.get_cell_source_id(c) >= 0, "바닥 타일이 깔렸다")


func _router() -> Array:
	var r: RefCounted = InputRouter.new()
	r.cell_at = func(pos: Vector2) -> Vector2i: return Vector2i(int(pos.x) / 100, int(pos.y) / 100)
	var got: Array = []
	r.preview.connect(func(p: Vector2) -> void: got.append(["preview", p]))
	r.confirm.connect(func(p: Vector2) -> void: got.append(["confirm", p]))
	r.info.connect(func(p: Vector2) -> void: got.append(["info", p]))
	r.pan.connect(func(d: Vector2) -> void: got.append(["pan", d]))
	r.zoom.connect(func(f: float, _p: Vector2) -> void: got.append(["zoom", f]))
	return [r, got]


func _touch(index: int, pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	return e


func _drag(index: int, pos: Vector2, rel: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	e.relative = rel
	return e


func test_mouse_hover_previews_click_confirms() -> void:
	var rg := _router()
	var r: RefCounted = rg[0]
	var got: Array = rg[1]
	var mv := InputEventMouseMotion.new()
	mv.position = Vector2(150, 150)
	r.handle(mv, 0)
	assert_eq(got[0][0], "preview", "올리기 = 미리보기")
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2(150, 150)
	r.handle(down, 10)
	var up := down.duplicate()
	up.pressed = false
	r.handle(up, 20)
	assert_eq(got.back()[0], "confirm", "클릭 = 실행")


func test_touch_first_tap_previews_second_confirms() -> void:
	var rg := _router()
	var r: RefCounted = rg[0]
	var got: Array = rg[1]
	r.handle(_touch(0, Vector2(150, 150), true), 0)
	r.handle(_touch(0, Vector2(150, 150), false), 100)
	assert_eq(got.map(func(x: Array) -> String: return x[0]), ["preview"], "첫 탭 = 미리보기")
	r.handle(_touch(0, Vector2(160, 140), true), 300)
	r.handle(_touch(0, Vector2(160, 140), false), 400)
	assert_eq(got.back()[0], "confirm", "같은 칸 두 번째 탭 = 실행")
	r.handle(_touch(0, Vector2(350, 150), true), 600)
	r.handle(_touch(0, Vector2(350, 150), false), 700)
	assert_eq(got.back()[0], "preview", "다른 칸 탭은 다시 미리보기")


func test_touch_long_press_drag_and_pinch() -> void:
	var rg := _router()
	var r: RefCounted = rg[0]
	var got: Array = rg[1]
	r.handle(_touch(0, Vector2(50, 50), true), 0)
	r.update(600)
	assert_eq(got.back()[0], "info", "길게 누르기 = 정보")
	r.handle(_touch(0, Vector2(50, 50), false), 700)
	assert_eq(got.back()[0], "info", "길게 누른 뒤 떼도 실행하지 않는다")
	got.clear()
	r.handle(_touch(0, Vector2(50, 50), true), 1000)
	r.handle(_drag(0, Vector2(90, 50), Vector2(40, 0)), 1010)
	r.handle(_drag(0, Vector2(120, 50), Vector2(30, 0)), 1020)
	r.handle(_touch(0, Vector2(120, 50), false), 1030)
	assert_eq(got.map(func(x: Array) -> String: return x[0]), ["pan", "pan"], "끌기 = 화면 이동(탭 아님)")
	got.clear()
	r.handle(_touch(0, Vector2(100, 100), true), 2000)
	r.handle(_touch(1, Vector2(200, 100), true), 2001)
	r.handle(_drag(1, Vector2(300, 100), Vector2(100, 0)), 2010)
	assert_eq(got.back()[0], "zoom")
	assert_near(got.back()[1], 2.0, 0.001, "핀치 = 확대")


## 표현 계층 스크립트가 모두 컴파일되는지(화면을 띄우지 않는 테스트에서 놓치기 쉽다).
func test_all_scene_scripts_compile() -> void:
	for path: String in ["res://scenes/battle/battle_scene.gd", "res://scenes/battle/actor_view.gd", "res://scenes/battle/map_view.gd",
			"res://scenes/battle/input_router.gd", "res://scenes/ui/character_creation.gd", "res://scenes/battle/test_roster.gd",
			"res://scenes/ui/hotbar.gd", "res://scenes/ui/ui_style.gd", "res://scenes/ui/character_sheet.gd", "res://scenes/ui/minimap.gd", "res://scenes/battle/vfx.gd", "res://scenes/ui/action_icons.gd"]:
		var s: Script = load(path)
		assert_true(s != null and s.can_instantiate(), "%s 컴파일 실패" % path)
