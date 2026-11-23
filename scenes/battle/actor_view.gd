extends Node3D
## 캐릭터 한 명의 그림(표현 계층, 3/4 탑뷰 3D). Creature 값을 읽어 그리기만 한다.
## 탐험가: assets/actors 걷기 시트(칸 72×108, 줄 = 아래·왼·오른·위, 칸 5 = 걸음A·반걸음A·섬·반걸음B·걸음B, 원점 = 발).
## 몬스터: assets/actors/monsters 한 장 그림(크기에 맞춰 키 맞춤, 좌우 반전으로 방향).
## 그림은 세운 판(Sprite3D, 세로 View3D.UPRIGHT배)이라 화면 크기가 옛 2D와 같다. 노드 위치 = 발(칸 높이 포함).
## 발밑 그림자·선택 고리는 바닥에 눕힌 판, HP 막대·알아챔 표시는 화면 위(Hud)에 그린다.
## 규칙 엔진이 칸을 옮기면(on_enter_tile) 칸 사이를 걸어서 따라간다(높이가 다르면 비탈처럼).

const V := preload("res://scenes/battle/view3d.gd")
const FRAME := Vector2i(72, 108)
const WALK_CYCLE := [2, 1, 0, 1, 2, 3, 4, 3]
const WALK_FPS := 9.0
const STEP_SEC := 0.16
## 그림 키(px): 사람 = 84(1.3칸), 몬스터는 크기 배율
const BODY_PX := 84.0
const SIZE_K := {"tiny": 0.5, "small": 0.8, "medium": 1.0, "large": 1.7}
## 옛 2D 그림자 타원(세로/가로 0.45)을 바닥 판에서 같게 보이게
const SHADOW_Z := 0.45 / V.SIN_P

static var _disc: Texture2D

var creature: Node
var grid: Node
## 그려진 바닥 높이(칸 평면 점 → 높이, map_view.ground_at). 없으면 칸 규칙 높이. 자연 지형의 비탈 위에 발을 붙인다.
var ground: Callable
var selected := false
var current := false
var sprite: Sprite3D
var facing := 0  # 줄: 0 아래, 1 왼, 2 오른, 3 위
var hud: Node2D
var _body: Node3D
var _pivot: Node3D
var _shadow: Sprite3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _sheet := false
## 그림 1px의 화면 px(확대 1) — 몬스터 키 맞춤 배율
var _k := 1.0
var _path: Array[Vector3] = []
var _walk_t := 0.0
var _flash := 0.0
var _last_hp := -1
var _cell := Vector2i(-1, -1)
var _last_facing := Vector2i.ZERO
var _state_col := Color.WHITE


class Hud extends Node2D:
	## 화면 위 표시: HP 막대·임시 HP·알아챔(?, !). 3D 발 위치를 화면에 투영해 그린다.
	var view: Node3D

	func _draw() -> void:
		var cam := view.get_viewport().get_camera_3d()
		var c: Node = view.creature
		if cam == null or c == null or c.dead or not view.visible:
			return
		var air: float = float(int(c.altitude))
		var foot := cam.unproject_position(view.global_position + Vector3(0, air, 0))
		var z: float = view.get_viewport().get_visible_rect().size.y / (cam.size * V.T) if cam.projection == Camera3D.PROJECTION_ORTHOGONAL else 1.0
		draw_set_transform(foot, 0, Vector2(z, z))
		var head: float = view.sprite_px_height()
		var top := Vector2(0, -head - 6)
		var w := 46.0
		var ratio: float = float(c.hp) / maxf(c.hp_max, 1)
		draw_rect(Rect2(top + Vector2(-w / 2, 0), Vector2(w, 6)), Color(0, 0, 0, 0.7))
		var col2: Color = {"party": Color(0.3, 0.85, 0.35), "enemy": Color(0.9, 0.3, 0.25)}.get(c.team, Color(0.9, 0.75, 0.3))
		draw_rect(Rect2(top + Vector2(-w / 2 + 1, 1), Vector2((w - 2) * ratio, 4)), col2)
		# 알아챔 표시(5단계): 의심·수색 = ?, 발견 = !
		var mark := ""
		for k in c.awareness:
			var st: String = c.awareness[k].get("state", "")
			if st == "alerted":
				mark = "!"
			elif st != "" and mark == "":
				mark = "?"
		if mark != "":
			var f := ThemeDB.fallback_font
			draw_string(f, top + Vector2(-6, -8), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 26,
				Color(1, 0.25, 0.2) if mark == "!" else Color(1, 0.85, 0.2))
		if c.temp_hp > 0:
			draw_rect(Rect2(top + Vector2(-w / 2, -3), Vector2(minf(w, c.temp_hp * 4.0), 2)), Color(0.6, 0.8, 1.0))


func setup(c: Node, g: Node) -> void:
	creature = c
	grid = g
	_body = Node3D.new()
	_body.scale = Vector3(1, V.UPRIGHT, 1)
	add_child(_body)
	_pivot = Node3D.new()
	_body.add_child(_pivot)
	sprite = Sprite3D.new()
	var art: Dictionary = c.get_meta("art", {})
	if art.has("sheet") and ResourceLoader.exists(art["sheet"]):
		sprite.texture = load(art["sheet"])
		sprite.region_enabled = true
		sprite.region_rect = Rect2(Vector2(FRAME.x * 2, 0), Vector2(FRAME))
		_sheet = true
	elif art.has("image") and ResourceLoader.exists(art["image"]):
		sprite.texture = load(art["image"])
		var tex_h: float = sprite.texture.get_size().y
		_k = BODY_PX * float(SIZE_K.get(c.size, 1.0)) / maxf(tex_h, 1.0)
	preload("res://scenes/kit/kit3d.gd").setup_sprite(sprite, _k / V.T)
	_pivot.add_child(sprite)
	_build_ground_marks()
	hud = Hud.new()
	hud.view = self
	add_child(hud)
	_last_hp = c.hp
	_cell = grid.cell_of(c)
	position = _foot(_cell)
	sync()


## 발밑 그림자(눕힌 원판)·선택 고리(눕힌 고리)
func _build_ground_marks() -> void:
	var rad: float = 0.34 * grid.size_of(creature)
	if _disc == null:
		var gr := Gradient.new()
		gr.offsets = PackedFloat32Array([0.0, 0.92, 1.0])
		gr.colors = PackedColorArray([Color(0, 0, 0, 0.35), Color(0, 0, 0, 0.35), Color(0, 0, 0, 0)])
		var gt := GradientTexture2D.new()
		gt.gradient = gr
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 64
		gt.height = 64
		_disc = gt
	_shadow = Sprite3D.new()
	_shadow.texture = _disc
	_shadow.pixel_size = rad * 2.0 / 64.0
	_shadow.shaded = false
	_shadow.double_sided = true
	_shadow.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	_shadow.render_priority = 1
	_shadow.rotation.x = -PI / 2.0
	_shadow.scale = Vector3(1, SHADOW_Z, 1)
	_shadow.position.y = 0.006
	add_child(_shadow)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var r0 := rad
	var r1 := rad + 3.0 / V.T
	for i in 33:
		var a := TAU * i / 32.0
		var d := Vector3(cos(a), 0, sin(a) * SHADOW_Z)
		im.surface_add_vertex(d * r1)
		im.surface_add_vertex(d * r0)
	im.surface_end()
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_mat.render_priority = 2
	_ring = MeshInstance3D.new()
	_ring.mesh = im
	_ring.material_override = _ring_mat
	_ring.position.y = 0.01
	_ring.visible = false
	add_child(_ring)


## 칸의 발 위치(칸 높이 포함). 큰 생물은 점유 칸 가운데.
func _foot(cell: Vector2i) -> Vector3:
	var sz: int = grid.size_of(creature)
	var h: float = float(grid.height(cell)) if grid.in_bounds(cell) else 0.0
	var p := V.pos(cell, h) + Vector3((sz - 1) * 0.5, 0.0, (sz - 1) * 0.5 + 0.18)
	if ground.is_valid():
		p.y = ground.call(Vector2(p.x, p.z))
	return p


func sync() -> void:
	var cell: Vector2i = grid.cell_of(creature)
	if cell != _cell:
		var d := cell - _cell
		_face(d)
		_path.append(_foot(cell))
		_cell = cell
	if creature.facing != _last_facing:
		# 규칙 쪽에서 바라보는 쪽을 바꿨다(의심해 돌아봄 등)
		_last_facing = creature.facing
		_face(creature.facing)
	if creature.hp < _last_hp:
		_flash = 0.35
	_last_hp = creature.hp
	if creature.dead:
		_state_col = Color(0.45, 0.45, 0.45, 0.45)
	elif creature.is_down() or creature.has_condition("prone"):
		_state_col = Color(0.8, 0.7, 0.7, 1.0)
	elif creature.has_condition("invisible"):
		_state_col = Color(1, 1, 1, 0.45)
	else:
		_state_col = Color.WHITE
	_pivot.rotation.z = deg_to_rad(80) if (creature.is_down() or creature.dead) else 0.0
	_shadow.visible = not creature.dead
	_ring.visible = (current or selected) and not creature.dead
	_ring_mat.albedo_color = Color(1, 0.85, 0.2) if current else Color(0.4, 0.8, 1.0)
	_place_sprite()
	_apply_color()
	_tilt_ground_marks()
	hud.queue_redraw()


## 불러오기 등으로 칸이 순간 바뀌었을 때 걷지 않고 바로 놓는다.
func snap() -> void:
	_path.clear()
	_cell = grid.cell_of(creature)
	position = _foot(_cell)
	_last_hp = creature.hp
	sync()


## 바라보는 쪽(공격 대상 등)
func face_toward(cell: Vector2i) -> void:
	_face(cell - grid.cell_of(creature))
	_place_sprite()


func _face(d: Vector2i) -> void:
	if d == Vector2i.ZERO:
		return
	if absi(d.x) > absi(d.y):
		facing = 2 if d.x > 0 else 1
	else:
		facing = 0 if d.y > 0 else 3


## 그림 키(그림 px × 배율 — 화면 px, 확대 1)
func sprite_px_height() -> float:
	if sprite.texture == null:
		return 60.0
	var h: float = float(FRAME.y) if _sheet else sprite.texture.get_size().y
	return h * _k


func _place_sprite() -> void:
	if sprite.texture == null:
		return
	var size: Vector2 = Vector2(FRAME) if _sheet else sprite.texture.get_size()
	# 판 가운데 정렬 → 발(그림 아래 가운데에서 4px 위)이 _pivot에 오게
	sprite.position = (Vector3(0, size.y * 0.5 - 4.0, 0) + preload("res://scenes/kit/kit3d.gd").footprint_shift(4.0)) * _k / V.T
	# 비행·부양: 고도만큼 그림을 띄운다(그림자는 바닥에 남는다)
	_body.position.y = float(int(creature.altitude))
	if _sheet:
		var col: int = WALK_CYCLE[int(_walk_t * WALK_FPS) % WALK_CYCLE.size()] if not _path.is_empty() else 2
		sprite.region_rect = Rect2(Vector2(FRAME.x * col, FRAME.y * facing), Vector2(FRAME))
	else:
		sprite.flip_h = facing == 1


func _apply_color() -> void:
	var lt := V.light_tint(grid, _cell)
	var col := Color(_state_col.r * lt.r, _state_col.g * lt.g, _state_col.b * lt.b, _state_col.a)
	if _flash > 0.0 and fmod(_flash, 0.12) > 0.06:
		col = Color(col.r, col.g * 0.4, col.b * 0.4, col.a)
	sprite.modulate = col
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED if col.a < 0.99 else SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS


func _process(delta: float) -> void:
	if not _path.is_empty():
		_walk_t += delta
		var target: Vector3 = _path[0]
		var speed: float = 1.0 / STEP_SEC * (1.0 + _path.size() * 0.15)
		position = position.move_toward(target, speed * delta)
		if ground.is_valid():
			# 비탈을 따라 걷는다(칸 사이 직선이 아니라 그려진 바닥 위)
			var gy: float = ground.call(Vector2(position.x, position.z))
			if absf(target.y - gy) < 1.5:
				position.y = gy
		if position.distance_to(target) < 0.01:
			_pop_step()
		_place_sprite()
		_tilt_ground_marks()
	if _flash > 0.0:
		_flash -= delta
		_apply_color()
	hud.queue_redraw()


func _pop_step() -> void:
	_path.pop_front()
	if _path.is_empty():
		_apply_color()


## 발밑 그림자·선택 고리를 그려진 바닥 기울기에 맞춘다(자연 지형 비탈에서 묻히지 않게)
func _tilt_ground_marks() -> void:
	if not ground.is_valid():
		return
	var p := Vector2(position.x, position.z)
	var e := 0.2
	var dx: float = (float(ground.call(p + Vector2(e, 0))) - float(ground.call(p - Vector2(e, 0)))) / (2.0 * e)
	var dz: float = (float(ground.call(p + Vector2(0, e))) - float(ground.call(p - Vector2(0, e)))) / (2.0 * e)
	var n := Vector3(-dx, 1.0, -dz).normalized()
	if n.y < 0.6:
		n = Vector3(n.x, 0.6, n.z).normalized()
	var tilt := Basis(Quaternion(Vector3.UP, n))
	_shadow.basis = tilt * Basis(Vector3.RIGHT, -PI / 2.0) * Basis.from_scale(Vector3(1, SHADOW_Z, 1))
	_ring.basis = tilt
	_shadow.position.y = 0.006 + 0.02 * (1.0 - n.y) * 4.0
	_ring.position.y = 0.01 + 0.02 * (1.0 - n.y) * 4.0


func is_moving() -> bool:
	return not _path.is_empty()


## 가림 판정용: 발 위치와 크기 배율(셰이더가 이 둘레를 비춘다)
func occlusion_info() -> Array:
	return [global_position + Vector3(0, float(int(creature.altitude)), 0), maxf(1.0, sprite_px_height() / BODY_PX) * grid.size_of(creature)]
