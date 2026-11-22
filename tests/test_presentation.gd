extends "res://tests/test_case.gd"
## 4단계 표현 계층: 쿼터뷰 좌표, 바닥 타일맵 정렬, 입력 상태기계(마우스·터치 같은 의미 신호).

const V := preload("res://scenes/battle/view3d.gd")
const InputRouter := preload("res://scenes/battle/input_router.gd")
const MapView := preload("res://scenes/battle/map_view.gd")
const DungeonKit := preload("res://scenes/kit/dungeon_kit.gd")


func test_view3d_coords_and_pick() -> void:
	assert_eq(V.pos(Vector2i(0, 0)), Vector3(0.5, 0, 0.5), "칸 가운데")
	assert_eq(V.pos(Vector2i(2, 1), 2), Vector3(2.5, 2, 1.5), "높이 1단계 = 1유닛")
	assert_near(cos(V.PITCH) * V.T, V.STEP_PX, 0.01, "높이 1단계는 화면 40px(옛 2D와 같다)")
	var g := make_grid(["....", "..2.", "...."])
	var r: Array = V.ray_through(V.pos(Vector2i(1, 2)))
	assert_eq(V.pick(g, r[0], r[1]), Vector2i(1, 2), "바닥 칸")
	r = V.ray_through(V.pos(Vector2i(2, 1), 2))
	assert_eq(V.pick(g, r[0], r[1]), Vector2i(2, 1), "높은 칸은 올라간 윗면으로 고른다")
	# 높은 칸 앞면(절벽)을 누르면 뒤 칸이 아니라 그 높은 칸
	r = V.ray_through(Vector3(2.5, 1.0, 2.0))
	assert_eq(V.pick(g, r[0], r[1]), Vector2i(2, 1), "절벽 면은 그 높은 칸")
	var w := make_grid(["...", ".#.", "..."])
	r = V.ray_through(V.pos(Vector2i(1, 1), V.WALL_H))
	assert_eq(V.pick(w, r[0], r[1]), Vector2i(1, 1), "벽은 꼭대기로 고른다")
	var room := make_grid(["...", "###"])
	assert_true(V.is_low_wall(room, Vector2i(1, 1)), "방 남쪽 벽은 낮게 자른다")
	assert_eq(V.cell_top(room, Vector2i(1, 1)), V.LOW_WALL_H)
	r = V.ray_through(V.pos(Vector2i(1, 0)))
	assert_eq(V.pick(room, r[0], r[1]), Vector2i(1, 0), "낮은 벽 뒤 바닥 칸도 고를 수 있다")
	var hill := make_grid(["###", "1..", "..."])
	assert_eq(V.wall_base(hill, Vector2i(0, 0)), 1.0, "고지대 앞 벽은 고지대 바닥 위에 선다")
	assert_eq(V.cell_top(hill, Vector2i(0, 0)), 1.0 + V.WALL_H)
	assert_eq(V.wall_base(hill, Vector2i(1, 0)), 0.0, "옆 벽은 제 앞 바닥 높이")


func test_camera_matches_view3d() -> void:
	var cam: Camera3D = own(Camera3D.new())
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var target := Vector3(5, 0, 5)
	cam.transform = V.camera_transform(target)
	assert_true(cam.transform.basis.z.y > 0.7 and cam.transform.basis.z.z > 0.5, "남쪽 위에서 내려다본다")
	assert_near((-cam.transform.basis.z).angle_to(Vector3(0, 0, -1)), V.PITCH, 0.001, "내려다보는 각")
	assert_near(V.pan_delta(Vector2(64, 0), 1.0).x, 1.0, 0.001, "가로 64px = 1칸")


## 실제 카메라로: 칸 윗면 가운데를 화면에 투영한 점을 누르면 그 칸(가려진 칸 — 높은 칸 바로 북쪽 — 은 뺀다)
func test_camera_pick_round_trip() -> void:
	var g := make_grid(["......", "..22..", "..22..", "......", ".#....", "......"])
	var cam: Camera3D = own(Camera3D.new())
	tree.root.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = 1.0
	cam.far = V.CAM_DIST * 2.0
	cam.transform = V.camera_transform(Vector3(3, 0, 3))
	cam.size = V.ortho_size(cam.get_viewport().get_visible_rect().size.y, 0.92)
	cam.make_current()
	var hidden := [Vector2i(2, 0), Vector2i(3, 0), Vector2i(1, 2), Vector2i(1, 3)]  # 높은 칸·벽(2.8) 바로 북쪽
	for c: Vector2i in g.all_cells():
		if c in hidden:
			continue
		var sp := cam.unproject_position(V.top(g, c))
		assert_eq(V.pick(g, cam.project_ray_origin(sp), cam.project_ray_normal(sp)), c, "왕복 %s" % str(c))
	# 높이 1단계 = 화면 40px(확대 1)
	cam.size = V.ortho_size(cam.get_viewport().get_visible_rect().size.y, 1.0)
	var a := cam.unproject_position(V.pos(Vector2i(0, 5), 0))
	var b := cam.unproject_position(V.pos(Vector2i(0, 5), 1))
	assert_near(a.y - b.y, V.STEP_PX, 0.5, "높이 1단계 = 40px")


func test_dungeon_kit_loads() -> void:
	var kit: RefCounted = DungeonKit.open()
	assert_eq(kit.px, 64, "키트 한 칸 64px")
	assert_true(kit.has("floor_flag") and kit.has("wall_stone") and kit.has("brazier"))
	assert_true(kit.texture("brazier", "lit") != null, "키트 그림")


func test_map_view_builds_terrain() -> void:
	var g := make_grid(["....", "..2.", "...."])
	var root: Node3D = own(Node3D.new())
	var view: Node3D = MapView.new()
	root.add_child(view)
	var sorted := Node3D.new()
	root.add_child(sorted)
	view.build(g, sorted, {})
	var floors: ArrayMesh = view._floor_mi.mesh
	assert_true(floors.get_surface_count() == 1, "바닥 그물")
	var verts: PackedVector3Array = floors.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(verts.size(), 12 * 4, "칸마다 네모 하나")
	assert_true(verts.has(Vector3(2, 2, 1)) and verts.has(Vector3(3, 2, 2)), "높은 칸 바닥은 높이 2에")
	var arrs: Array = floors.surface_get_arrays(0)
	var uv: PackedVector2Array = arrs[Mesh.ARRAY_TEX_UV]
	var uv2: PackedVector2Array = arrs[Mesh.ARRAY_TEX_UV2]
	assert_eq(uv2.size(), uv.size(), "바닥 변형 b 조각(UV2) — 셰이더가 a·b를 섞는다")
	assert_true(uv2[0] != uv[0], "기본 돌바닥(floor_flag)은 변형 a·b가 다른 조각")
	assert_true(view._floor_mi.material_override.shader.resource_path.ends_with("floor.gdshader"))
	# 셰이더용 칸 데이터: 높이·바닥 있음, 바닥 조각(종류 경계 섞기)
	var info: Image = view._info_tex.get_image()
	assert_eq(info.get_size(), Vector2i(4, 3))
	assert_eq(info.get_pixel(2, 1).r8, 2, "칸 높이")
	assert_eq(info.get_pixel(0, 0).g8, 1, "바닥 있음")
	var cells: Image = view._cells_tex.get_image()
	var flag_a: Vector2i = view.kit.tile_of("floor_flag.a")["base"]
	assert_eq(Vector2i(cells.get_pixel(0, 0).r8, cells.get_pixel(0, 0).g8), flag_a, "변형 a 묶음 첫 조각")
	var faces: ArrayMesh = view._face_mi.mesh
	assert_true(faces.get_surface_count() == 1, "높은 칸 남쪽 절벽 면")
	var fv: PackedVector3Array = faces.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for v: Vector3 in fv:
		assert_near(v.z, 2.0, 0.001, "절벽 면은 높은 칸 남쪽 변에 세운다")


## 물 표면: 표면 칸과 둘레에 네모(셰이더가 흔든 가장자리를 그림), 칸 데이터에 팔레트 번호
func test_map_view_water_edges() -> void:
	var g := make_grid([".....", ".....", "....."])
	var surfaces: Node = make_surfaces(g)
	surfaces.place_surface([Vector2i(2, 1)], "water", {"turns": -1})
	var root: Node3D = own(Node3D.new())
	var view: Node3D = MapView.new()
	root.add_child(view)
	var sorted := Node3D.new()
	root.add_child(sorted)
	view.build(g, sorted, {})
	var verts: PackedVector3Array = view._water_mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(verts.size(), 9 * 4, "물 칸 + 둘레 8칸")
	var surf: Image = view._surf_tex.get_image()
	assert_eq(surf.get_pixel(2, 1).b8, 1, "물 칸 팔레트 1")
	assert_eq(surf.get_pixel(0, 0).b8, 0, "표면 없음")


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
			"res://scenes/ui/hotbar.gd", "res://scenes/ui/ui_style.gd", "res://scenes/ui/character_sheet.gd", "res://scenes/ui/minimap.gd", "res://scenes/battle/vfx.gd", "res://scenes/ui/action_icons.gd",
			"res://scenes/battle/view3d.gd", "res://scenes/kit/kit3d.gd"]:
		var s: Script = load(path)
		assert_true(s != null and s.can_instantiate(), "%s 컴파일 실패" % path)
