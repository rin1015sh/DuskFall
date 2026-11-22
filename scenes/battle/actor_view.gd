extends Node2D
## 캐릭터 한 명의 그림(표현 계층). Creature의 값을 읽어 그리기만 한다. 임시 그림: assets/actors 걷기 시트.
## 시트: 칸 72×108, 줄 = 아래·왼·오른·위, 칸 5 = 걸음 A·반걸음 A·섬·반걸음 B·걸음 B, 원점 = 발.

const Iso := preload("res://scenes/battle/iso.gd")
const FRAME := Vector2i(72, 108)

var creature: Node
var grid: Node
var selected := false
var current := false
var sprite: Sprite2D
var _flash := 0.0
var _last_hp := -1


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
		sprite.scale = Vector2(0.85, 0.85)
	elif art.has("image") and ResourceLoader.exists(art["image"]):
		sprite.texture = load(art["image"])
		sprite.scale = Vector2(1.4, 1.4)
	if sprite.texture != null:
		var size: Vector2 = sprite.texture.get_size() * sprite.scale
		sprite.position = Vector2(-size.x / 2.0, -size.y + 4)
	add_child(sprite)
	_last_hp = c.hp
	sync()


## 위치·상태를 규칙 데이터에 맞춘다.
func sync() -> void:
	var cell: Vector2i = grid.cell_of(creature)
	position = Iso.ground(cell) + Vector2(0, 1)
	sprite.position.y = -(sprite.texture.get_size().y * sprite.scale.y) + 4 - grid.height(cell) * Iso.STEP if sprite.texture else 0.0
	if creature.hp < _last_hp:
		_flash = 0.35
	_last_hp = creature.hp
	if creature.dead:
		modulate = Color(0.5, 0.5, 0.5, 0.35)
	elif creature.is_down() or creature.has_condition("prone"):
		modulate = Color(0.8, 0.7, 0.7, 1.0)
	else:
		modulate = Color.WHITE
	sprite.rotation = deg_to_rad(80) if (creature.is_down() or creature.dead) else 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		sprite.modulate = Color(1, 0.4, 0.4) if fmod(_flash, 0.12) > 0.06 else Color.WHITE
		if _flash <= 0.0:
			sprite.modulate = Color.WHITE


## 화면에서 차지하는 네모(가림 판정용).
func screen_rect() -> Rect2:
	if sprite.texture == null:
		return Rect2(position, Vector2.ONE)
	return Rect2(position + sprite.position, sprite.texture.get_size() * sprite.scale)


func _draw() -> void:
	var h: int = grid.height(grid.cell_of(creature))
	var foot := Vector2(0, -h * Iso.STEP)
	if current or selected:
		var d := Iso.diamond(foot)
		var col := Color(1, 0.85, 0.2) if current else Color(0.4, 0.8, 1.0)
		draw_polyline(PackedVector2Array([d[0], d[1], d[2], d[3], d[0]]), col, 3.0)
	if creature.dead:
		return
	# HP 막대
	var top := foot + Vector2(0, -100)
	var w := 46.0
	var ratio: float = float(creature.hp) / maxf(creature.hp_max, 1)
	draw_rect(Rect2(top + Vector2(-w / 2, 0), Vector2(w, 6)), Color(0, 0, 0, 0.7))
	var col := Color(0.3, 0.85, 0.35) if creature.team == "party" else Color(0.9, 0.3, 0.25)
	draw_rect(Rect2(top + Vector2(-w / 2 + 1, 1), Vector2((w - 2) * ratio, 4)), col)
	if creature.temp_hp > 0:
		draw_rect(Rect2(top + Vector2(-w / 2, -3), Vector2(minf(w, creature.temp_hp * 4.0), 2)), Color(0.6, 0.8, 1.0))
