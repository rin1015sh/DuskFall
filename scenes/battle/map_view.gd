extends Node2D
## 쿼터뷰 맵 그리기(표현 계층). GridWorld를 읽어 그리기만 한다.
## 바닥 = TileMapLayer(아이소메트릭 마름모, 재질·빛 단계별 색 타일을 코드로 만든다 — 임시 그림),
## 높은 칸·벽·물체 = y 정렬 층의 블록 노드(캐릭터와 앞뒤가 맞게), 표면·구름 = 덮개 그리기.
## 캐릭터를 가리는 앞쪽 벽·블록은 반투명이 된다.

const Iso := preload("res://scenes/battle/iso.gd")

const MATERIAL_COLORS := {
	"stone": Color("6b6670"), "earth": Color("6e5a44"), "grass": Color("5d7a3a"), "brush": Color("4f6a32"),
	"wood": Color("7a5a3a"), "cloth": Color("8a7a6a"), "glass": Color("8fb0c0"), "metal": Color("7a8088"),
	"burnt_ground": Color("3a3230"),
}
const SURFACE_COLORS := {
	"water": Color(0.25, 0.45, 0.85, 0.55), "deep_water": Color(0.12, 0.25, 0.6, 0.7),
	"ice": Color(0.75, 0.9, 1.0, 0.65), "oil": Color(0.15, 0.12, 0.08, 0.7), "fire": Color(1.0, 0.45, 0.1, 0.7),
	"acid": Color(0.55, 0.9, 0.2, 0.6), "poison": Color(0.45, 0.7, 0.2, 0.6),
	"electrified_water": Color(0.5, 0.75, 1.0, 0.75), "blood": Color(0.55, 0.05, 0.05, 0.6),
	"mud": Color(0.35, 0.25, 0.15, 0.6), "web": Color(0.9, 0.9, 0.9, 0.5), "burning_web": Color(1.0, 0.6, 0.3, 0.7),
	"thorns": Color(0.3, 0.45, 0.2, 0.6),
}
const CLOUD_COLORS := {
	"steam": Color(0.9, 0.9, 0.95, 0.35), "fog": Color(0.8, 0.8, 0.85, 0.55),
	"magical_darkness": Color(0.02, 0.0, 0.05, 0.8), "sleet": Color(0.8, 0.9, 1.0, 0.4),
	"stinking_cloud": Color(0.55, 0.6, 0.2, 0.5),
}
## 빛 단계별 밝기(어둠·어스름·밝음)
const LIGHT_SHADE := [0.45, 0.72, 1.0]
const WALL_LEVELS := 3

var grid: Node
var ground: TileMapLayer
## 캐릭터·블록·물체를 함께 y 정렬하는 층
var sorted: Node2D
var _blocks: Array[Node2D] = []
var _materials: Array = []
var _overlay: Node2D


class Block extends Node2D:
	var top_h := 0
	var color := Color.GRAY
	var wall := false

	func _draw() -> void:
		var t := Iso.diamond(Vector2(0, -top_h * Iso.STEP))
		var g := Iso.diamond(Vector2.ZERO)
		# 왼쪽 면, 오른쪽 면, 윗면
		draw_colored_polygon(PackedVector2Array([t[3], t[2], g[2], g[3]]), color.darkened(0.35))
		draw_colored_polygon(PackedVector2Array([t[2], t[1], g[1], g[2]]), color.darkened(0.2))
		draw_colored_polygon(t, color.lightened(0.05) if not wall else color.darkened(0.1))
		draw_polyline(PackedVector2Array([t[0], t[1], t[2], t[3], t[0]]), Color(0, 0, 0, 0.35), 1.0)


class Barrel extends Node2D:
	var h := 0

	func _draw() -> void:
		var base := Vector2(0, -h * Iso.STEP)
		draw_rect(Rect2(base + Vector2(-12, -34), Vector2(24, 30)), Color("6a4628"))
		draw_rect(Rect2(base + Vector2(-12, -28), Vector2(24, 3)), Color("2a2a2a"))
		draw_rect(Rect2(base + Vector2(-12, -14), Vector2(24, 3)), Color("2a2a2a"))
		draw_circle(base + Vector2(0, -34), 12, Color("7a5634"))


class Overlay extends Node2D:
	var view: Node

	func _draw() -> void:
		var g: Node = view.grid
		for c: Vector2i in g.all_cells():
			var sid: String = g.surface_id(c)
			var h: int = g.height(c)
			if sid != "":
				draw_colored_polygon(Iso.diamond(Iso.top(c, h)), view.SURFACE_COLORS.get(sid, Color(1, 0, 1, 0.4)))
			var cid: String = g.cloud_id(c)
			if cid != "":
				var center := Iso.top(c, h) - Vector2(0, 14)
				draw_colored_polygon(Iso.diamond(center), view.CLOUD_COLORS.get(cid, Color(1, 1, 1, 0.3)))


func build(g: Node, sorted_layer: Node2D) -> void:
	grid = g
	sorted = sorted_layer
	_materials = MATERIAL_COLORS.keys()
	ground = TileMapLayer.new()
	ground.tile_set = _make_tileset()
	# 아이소메트릭 TileMapLayer의 칸 중심은 (W/2, H/2)만큼 밀려 있다 → Iso 좌표와 맞춘다.
	ground.position = -ground.map_to_local(Vector2i.ZERO)
	add_child(ground)
	_overlay = Overlay.new()
	_overlay.view = self
	_overlay.z_index = 1
	add_child(_overlay)
	refresh()


## 칸 데이터가 바뀌면(표면·재질·빛) 다시 그린다.
func refresh() -> void:
	ground.clear()
	for b in _blocks:
		b.queue_free()
	_blocks.clear()
	for c: Vector2i in grid.all_cells():
		var mat: String = grid.material(c)
		var light: int = grid.light_at(c)
		var wall: bool = grid.has_flag(c, "wall")
		var h: int = grid.height(c)
		if not wall and h == 0:
			var col := maxi(_materials.find(mat), 0)
			ground.set_cell(c, 0, Vector2i(col, light))
		else:
			var b := Block.new()
			b.wall = wall
			b.top_h = WALL_LEVELS if wall else h
			b.color = (Color("3a3540") if wall else MATERIAL_COLORS.get(mat, Color.GRAY)) * LIGHT_SHADE[light]
			b.color.a = 1.0
			b.position = Iso.ground(c)
			b.set_meta("cell", c)
			sorted.add_child(b)
			_blocks.append(b)
		var obj: Dictionary = grid.object_at(c)
		if not obj.is_empty():
			var barrel := Barrel.new()
			barrel.h = h
			barrel.position = Iso.ground(c) + Vector2(0, 0.5)
			sorted.add_child(barrel)
			_blocks.append(barrel)
	_overlay.queue_redraw()


## 캐릭터를 가리는 블록(앞쪽에 있고 화면에서 겹침)을 반투명하게.
func update_occlusion(actor_rects: Array) -> void:
	for b in _blocks:
		var faded := false
		if b is Block:
			var top_h: int = (b as Block).top_h
			var rect := Rect2(b.position + Vector2(-Iso.TILE_W / 2.0, -top_h * Iso.STEP - Iso.TILE_H / 2.0),
				Vector2(Iso.TILE_W, top_h * Iso.STEP + Iso.TILE_H))
			for ar: Array in actor_rects:
				if b.position.y > ar[1] and rect.intersects(ar[0]):
					faded = true
					break
		b.modulate.a = 0.35 if faded else 1.0


func _make_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = Vector2i(Iso.TILE_W, Iso.TILE_H)
	var img := Image.create(Iso.TILE_W * _materials.size(), Iso.TILE_H * 3, false, Image.FORMAT_RGBA8)
	for mi in _materials.size():
		for li in 3:
			var base: Color = MATERIAL_COLORS[_materials[mi]] * LIGHT_SHADE[li]
			_paint_diamond(img, mi * Iso.TILE_W, li * Iso.TILE_H, base, mi * 31 + li)
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(Iso.TILE_W, Iso.TILE_H)
	for mi in _materials.size():
		for li in 3:
			src.create_tile(Vector2i(mi, li))
	ts.add_source(src, 0)
	return ts


func _paint_diamond(img: Image, ox: int, oy: int, base: Color, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var hw := Iso.TILE_W / 2.0
	var hh := Iso.TILE_H / 2.0
	for y in Iso.TILE_H:
		for x in Iso.TILE_W:
			var dx: float = absf(x + 0.5 - hw) / hw
			var dy: float = absf(y + 0.5 - hh) / hh
			if dx + dy <= 1.0:
				var c := base.lightened(rng.randf_range(-0.04, 0.06))
				if dx + dy > 0.94:
					c = base.darkened(0.3)
				c.a = 1.0
				img.set_pixel(ox + x, oy + y, c)
