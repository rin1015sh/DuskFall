extends Node2D
## 캐릭터 한 명의 그림(표현 계층, 3/4 탑뷰). Creature 값을 읽어 그리기만 한다.
## 탐험가: assets/actors 걷기 시트(칸 72×108, 줄 = 아래·왼·오른·위, 칸 5 = 걸음A·반걸음A·섬·반걸음B·걸음B, 원점 = 발).
## 몬스터: assets/actors/monsters 한 장 그림(크기에 맞춰 키 맞춤, 좌우 반전으로 방향).
## 규칙 엔진이 칸을 옮기면(on_enter_tile) 칸 사이를 걸어서 따라간다.

const V := preload("res://scenes/battle/view3q.gd")
const FRAME := Vector2i(72, 108)
const WALK_CYCLE := [2, 1, 0, 1, 2, 3, 4, 3]
const WALK_FPS := 9.0
const STEP_SEC := 0.16
## 그림 키(px): 사람 = 84(1.3칸), 몬스터는 크기 배율
const BODY_PX := 84.0
const SIZE_K := {"tiny": 0.5, "small": 0.8, "medium": 1.0, "large": 1.7}

var creature: Node
var grid: Node
var selected := false
var current := false
var sprite: Sprite2D
var facing := 0  # 줄: 0 아래, 1 왼, 2 오른, 3 위
var _sheet := false
var _path: Array[Vector2] = []
var _walk_t := 0.0
var _flash := 0.0
var _last_hp := -1
var _cell := Vector2i(-1, -1)
var _last_facing := Vector2i.ZERO


func setup(c: Node, g: Node) -> void:
	creature = c
	grid = g
	sprite = Sprite2D.new()
	sprite.centered = false
	var art: Dictionary = c.get_meta("art", {})
	if art.has("sheet") and ResourceLoader.exists(art["sheet"]):
		var at := AtlasTexture.new()
		at.atlas = load(art["sheet"])
		at.region = Rect2(Vector2(FRAME.x * 2, 0), Vector2(FRAME))
		sprite.texture = at
		_sheet = true
	elif art.has("image") and ResourceLoader.exists(art["image"]):
		sprite.texture = load(art["image"])
		var tex_h: float = sprite.texture.get_size().y
		var k: float = BODY_PX * float(SIZE_K.get(c.size, 1.0)) / maxf(tex_h, 1.0)
		sprite.scale = Vector2(k, k)
	add_child(sprite)
	_last_hp = c.hp
	_cell = grid.cell_of(c)
	position = _foot(_cell)
	sync()


## 칸의 발 위치(y 정렬 기준 = 바닥 높이 0 기준, 그림은 높이만큼 올린다)
func _foot(cell: Vector2i) -> Vector2:
	var sz: int = grid.size_of(creature)
	return V.ground(cell) + Vector2((sz - 1) * V.T * 0.5, (sz - 1) * V.T * 0.5 + V.T * 0.18)


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
		modulate = Color(0.45, 0.45, 0.45, 0.45)
	elif creature.is_down() or creature.has_condition("prone"):
		modulate = Color(0.8, 0.7, 0.7, 1.0)
	elif creature.has_condition("invisible"):
		modulate = Color(1, 1, 1, 0.45)
	else:
		modulate = Color.WHITE
	sprite.rotation = deg_to_rad(-80) if (creature.is_down() or creature.dead) else 0.0
	_place_sprite()
	queue_redraw()


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


func _place_sprite() -> void:
	if sprite.texture == null:
		return
	var size: Vector2 = sprite.texture.get_size() * sprite.scale
	# 비행·부양: 고도만큼 그림을 띄운다(그림자는 바닥에 남는다)
	var lift: float = (grid.height(grid.cell_of(creature)) + int(creature.altitude)) * V.STEP
	sprite.position = Vector2(-size.x / 2.0, -size.y + 4 - lift)
	if _sheet:
		var col: int = WALK_CYCLE[int(_walk_t * WALK_FPS) % WALK_CYCLE.size()] if not _path.is_empty() else 2
		(sprite.texture as AtlasTexture).region = Rect2(Vector2(FRAME.x * col, FRAME.y * facing), Vector2(FRAME))
	else:
		sprite.flip_h = facing == 1


func _process(delta: float) -> void:
	if not _path.is_empty():
		_walk_t += delta
		var target: Vector2 = _path[0]
		var speed: float = V.T / STEP_SEC * (1.0 + _path.size() * 0.15)
		position = position.move_toward(target, speed * delta)
		if position.distance_to(target) < 0.5:
			_path.pop_front()
		_place_sprite()
	if _flash > 0.0:
		_flash -= delta
		sprite.modulate = Color(1, 0.4, 0.4) if fmod(_flash, 0.12) > 0.06 else Color.WHITE
		if _flash <= 0.0:
			sprite.modulate = Color.WHITE


func is_moving() -> bool:
	return not _path.is_empty()


func screen_rect() -> Rect2:
	if sprite.texture == null:
		return Rect2(position, Vector2.ONE)
	return Rect2(position + sprite.position, sprite.texture.get_size() * sprite.scale)


func _draw() -> void:
	var lift: float = grid.height(grid.cell_of(creature)) * V.STEP
	var foot := Vector2(0, -lift)
	var air: float = int(creature.altitude) * V.STEP
	var rad: float = V.T * 0.34 * grid.size_of(creature)
	# 발밑 그림자
	draw_set_transform(foot, 0, Vector2(1, 0.45))
	draw_circle(Vector2.ZERO, rad, Color(0, 0, 0, 0.35))
	if current or selected:
		var col := Color(1, 0.85, 0.2) if current else Color(0.4, 0.8, 1.0)
		draw_arc(Vector2.ZERO, rad + 2, 0, TAU, 32, col, 3.0)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	if creature.dead:
		return
	var head: float = (sprite.texture.get_size().y * sprite.scale.y if sprite.texture else 60.0)
	var top := foot + Vector2(0, -head - 6 - air)
	var w := 46.0
	var ratio: float = float(creature.hp) / maxf(creature.hp_max, 1)
	draw_rect(Rect2(top + Vector2(-w / 2, 0), Vector2(w, 6)), Color(0, 0, 0, 0.7))
	var col2: Color = {"party": Color(0.3, 0.85, 0.35), "enemy": Color(0.9, 0.3, 0.25)}.get(creature.team, Color(0.9, 0.75, 0.3))
	draw_rect(Rect2(top + Vector2(-w / 2 + 1, 1), Vector2((w - 2) * ratio, 4)), col2)
	# 알아챔 표시(5단계): 의심·수색 = ?, 발견 = !
	var mark := ""
	for k in creature.awareness:
		var st: String = creature.awareness[k].get("state", "")
		if st == "alerted":
			mark = "!"
		elif st != "" and mark == "":
			mark = "?"
	if mark != "":
		var f := ThemeDB.fallback_font
		draw_string(f, top + Vector2(-6, -8), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 26,
			Color(1, 0.25, 0.2) if mark == "!" else Color(1, 0.85, 0.2))
	if creature.temp_hp > 0:
		draw_rect(Rect2(top + Vector2(-w / 2, -3), Vector2(minf(w, creature.temp_hp * 4.0), 2)), Color(0.6, 0.8, 1.0))
