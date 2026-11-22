extends Node2D
## 3/4 탑뷰 맵 그리기(표현 계층). GridWorld를 읽어 던전 에셋 키트(assets/dungeon_kit, scenes/kit/dungeon_kit.gd) 그림으로 그린다.
## - 바닥: 높이마다 TileMapLayer(키트 바닥 4×4 이어지는 그림). 맵 데이터 art.floors(범례 글자 → 키트 바닥)·재질 기본값.
## - 벽: 칸마다 블록(윗면 = 키트 벽 윗면 자동 연결 16가지, 남쪽 면 = 키트 벽면). 높은 칸 남쪽은 절벽 면.
## - 소품: 맵 데이터 art.props(키트 물건). 규칙 물체(기름통 등)는 art 키 또는 기본 그림.
## - 표면·구름: 키트 바닥(물·얼음·진흙)·불꽃 애니메이션·얼룩·안개로 그린다(규칙 상태를 그리기만).
## - 빛: 규칙의 빛 단계로 어둠을 덮는다. 캐릭터를 가리는 앞쪽 블록은 반투명.

const V := preload("res://scenes/battle/view3q.gd")
const DungeonKit := preload("res://scenes/kit/dungeon_kit.gd")

const MATERIAL_FLOORS := {"stone": "floor_flag", "earth": "floor_dirt", "grass": "ground_grass", "brush": "ground_thicket",
	"wood": "room_wood", "burnt_ground": "ground_ash", "metal": "floor_brick", "glass": "floor_flag", "cloth": "floor_old"}
## 표면 → 그림: ["tile", 키트 바닥] 또는 ["prop", 키트 id, 변형]
const SURFACE_ART := {
	"water": ["tile", "ground_water"], "deep_water": ["tile", "ground_water"], "ice": ["tile", "ground_ice"],
	"mud": ["tile", "ground_mud"], "electrified_water": ["tile", "ground_water"], "blood": ["prop", "blood_pool", "fresh"],
	"oil": ["prop", "spill_stain", "oil"], "acid": ["prop", "mana_residue", "green"], "poison": ["prop", "black_slime", "a"],
	"fire": ["prop", "flame", "medium"], "burning_web": ["prop", "flame", "small"], "web": ["prop", "cobweb", "floor"],
	"thorns": ["prop", "weeds", "dead_bush"]}
const SURFACE_TINT := {"electrified_water": Color(0.6, 0.85, 1.4), "acid": Color(0.8, 1.2, 0.6)}
const CLOUD_ART := {"steam": "grey", "fog": "grey", "magical_darkness": "black", "sleet": "blue", "stinking_cloud": "violet"}
## 빛 단계별 어둠 덮개 불투명도(어둠·어스름·밝음)
const DARK_ALPHA := [0.82, 0.5, 0.06]
## 방 남쪽 벽의 잘린 높이
const LOW_WALL_H := 20.0

var grid: Node
var map: Dictionary = {}
var kit: RefCounted
var sorted: Node2D
var _floors := {}  # 높이 → TileMapLayer
var _blocks: Array[Node2D] = []
var _surface_nodes: Array[Node] = []
var _decals: Node2D
var _shade: Node2D
var _overlay: Node2D


class Block extends Node2D:
	## 벽 블록 또는 높은 칸의 절벽 면. 위치 = 칸 아랫변(y 정렬 기준).
	var tex: Texture2D
	var top_src := Rect2()
	var face_src := Rect2()
	var face_h := 0.0
	var top_lift := 0.0
	var has_top := false
	var shade := 1.0
	var top_shade := 0.32

	func _draw() -> void:
		var t := float(V.T)
		if face_h > 0.0 and tex != null:
			draw_texture_rect_region(tex, Rect2(0, -face_h, t, face_h), face_src, Color(shade * 0.78, shade * 0.78, shade * 0.74))
			# 벽 밑동 그늘(바닥과 만나는 선)
			draw_rect(Rect2(0, -6, t, 6), Color(0, 0, 0, 0.35))
		if has_top and tex != null:
			draw_texture_rect_region(tex, Rect2(0, -t - top_lift, t, t), top_src, Color(top_shade, top_shade, top_shade))


class TileOverlay extends Node2D:
	## 표면 바닥 그림(물·얼음·진흙) 칸마다
	var items: Array = []  # [rect, texture, src, color]

	func _draw() -> void:
		for it: Array in items:
			draw_texture_rect_region(it[1], it[0], it[2], it[3])


class Shade extends Node2D:
	## 어둠 덮개: 칸 모서리마다 이웃 평균 불투명도(부드럽게)
	var view: Node

	func _draw() -> void:
		var g: Node = view.grid
		var alpha := {}
		for c: Vector2i in g.all_cells():
			alpha[c] = view.DARK_ALPHA[g.light_at(c)]
		for c: Vector2i in g.all_cells():
			var r: Rect2 = V.top_rect(g, c)
			var cols := PackedColorArray()
			for d: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var s := 0.0
				var n := 0
				for o: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
					var k: Vector2i = c + d + o
					if alpha.has(k):
						s += alpha[k]
						n += 1
				cols.append(Color(0.02, 0.02, 0.05, s / maxi(n, 1)))
			if g.has_flag(c, "wall"):
				# 벽은 윗면과 앞면까지 덮는다
				r = Rect2(r.position, Vector2(r.size.x, r.size.y + V.WALL_H))
			draw_polygon(V.corners(r), cols)


func build(g: Node, sorted_layer: Node2D, map_data: Dictionary = {}) -> void:
	grid = g
	map = map_data
	sorted = sorted_layer
	kit = DungeonKit.open()
	_decals = Node2D.new()
	_decals.z_index = 1
	add_child(_decals)
	_overlay = Node2D.new()
	_overlay.z_index = 2
	add_child(_overlay)
	_shade = Shade.new()
	_shade.view = self
	_shade.z_index = 40
	add_child(_shade)
	_build_static()
	refresh()


func art() -> Dictionary:
	return map.get("art", {})


func _floor_id(c: Vector2i) -> String:
	var mat: String = grid.material(c)
	if mat == "burnt_ground":
		return "ground_ash"
	var ch := _legend_char(c)
	var floors: Dictionary = art().get("floors", {})
	if floors.has(ch):
		return floors[ch]
	return MATERIAL_FLOORS.get(mat, "floor_flag")


func _legend_char(c: Vector2i) -> String:
	var rows: Array = map.get("rows", [])
	if c.y < rows.size() and c.x < String(rows[c.y]).length():
		return String(rows[c.y])[c.x]
	return ""


## 한 번만: 벽 블록·소품·조명
func _build_static() -> void:
	var wall_kind: String = art().get("wall", "cave")
	var top_kind: String = art().get("wall_top", wall_kind)
	var face_info: Dictionary = kit.info("wall_%s" % wall_kind)
	var top_info: Dictionary = kit.info("wall_top")
	var tex: Texture2D = kit._sheet("wall_faces")
	var top_tex: Texture2D = kit._sheet("wall_tops")
	var face_frame: Array = face_info.get("variants", {}).get("clean", {"frames": [[0, 0, 256, 160, 0, 0]]})["frames"][0]
	var top_frame: Array = top_info.get("variants", {}).get(top_kind, top_info.get("variants", {}).get("a", {"frames": [[0, 0, 256, 256, 0, 0]]}))["frames"][0]
	for c: Vector2i in grid.all_cells():
		if grid.has_flag(c, "wall"):
			var b := Block.new()
			b.position = Vector2(c.x * V.T, (c.y + 1) * V.T)
			b.tex = tex
			var mask := 0
			for bit: Array in [[1, Vector2i.UP], [2, Vector2i.RIGHT], [4, Vector2i.DOWN], [8, Vector2i.LEFT]]:
				var n: Vector2i = c + (bit[1] as Vector2i)
				if not grid.in_bounds(n) or grid.has_flag(n, "wall"):
					mask |= int(bit[0])
			var south := c + Vector2i.DOWN
			var north := c + Vector2i.UP
			var open_south: bool = grid.in_bounds(south) and not grid.has_flag(south, "wall")
			# 방의 남쪽 벽(북쪽이 바닥이고 남쪽이 막힘)은 방 안을 가리지 않게 낮게 자른다(이전 게임 규칙)
			var low: bool = not open_south and grid.in_bounds(north) and not grid.has_flag(north, "wall")
			var wall_h: float = LOW_WALL_H if low else V.WALL_H
			b.face_h = V.WALL_H if open_south else 0.0
			var state: String = ["clean", "cracked", "mossy", "damaged"][posmod(c.x * 7 + c.y * 13, 4)] if open_south else "clean"
			var ff: Array = face_info.get("variants", {}).get(state, {"frames": [face_frame]})["frames"][0]
			b.face_src = Rect2(float(ff[0]) + posmod(c.x, 4) * V.T, float(ff[1]) + float(ff[3]) - V.WALL_H, V.T, V.WALL_H)
			b.has_top = true
			b.top_src = Rect2(float(top_frame[0]) + (mask % 4) * V.T, float(top_frame[1]) + (mask / 4) * V.T, V.T, V.T)
			# 윗면은 다른 그림(벽 윗면 시트)
			var tb := Block.new()
			tb.tex = top_tex
			tb.has_top = true
			tb.top_src = b.top_src
			tb.top_lift = wall_h
			b.add_child(tb)
			b.has_top = false
			sorted.add_child(b)
			_blocks.append(b)
		else:
			var h: int = grid.height(c)
			var south := c + Vector2i.DOWN
			var hs: int = grid.height(south) if grid.in_bounds(south) and not grid.has_flag(south, "wall") else h
			if h > hs:
				var cb := Block.new()
				cb.position = Vector2(c.x * V.T, (c.y + 1) * V.T - hs * V.STEP)
				cb.tex = tex
				cb.face_h = (h - hs) * V.STEP
				var cf: Array = kit.info("wall_%s" % art().get("cliff", wall_kind)).get("variants", {}).get("clean", {"frames": [face_frame]})["frames"][0]
				cb.face_src = Rect2(float(cf[0]) + posmod(c.x, 4) * V.T, float(cf[1]) + float(cf[3]) - cb.face_h, V.T, cb.face_h)
				cb.shade = 0.8
				sorted.add_child(cb)
				_blocks.append(cb)
	# 소품
	for p: Dictionary in art().get("props", []):
		var cell := Vector2i(int(p["at"][0]), int(p["at"][1]))
		var node: Node2D = kit.make(p["id"], p.get("v", ""), {"collision": false, "flip": p.get("flip", false), "up": p.get("up", 0.0)})
		node.position = V.top(cell, grid.height(cell)) + Vector2(float(p.get("dx", 0.0)), float(p.get("dy", 0.0)) + V.T * 0.3)
		node.scale = Vector2.ONE * float(p.get("scale", 1.0))
		var layer := String(node.get_meta("kit_layer", "stand"))
		if layer == "decal":
			node.z_index = 0
			_decals.add_child(node)
		else:
			if layer == "over":
				node.z_index = 30
			else:
				node.z_index = 0
			sorted.add_child(node)


## 칸 데이터가 바뀌면(표면·재질·빛) 다시 그린다.
func refresh() -> void:
	for h: int in _floors.keys():
		_floors[h].clear()
	for c: Vector2i in grid.all_cells():
		if grid.has_flag(c, "wall"):
			continue
		var h: int = grid.height(c)
		if not _floors.has(h):
			var tl := TileMapLayer.new()
			tl.tile_set = kit.tileset()
			tl.collision_enabled = false
			tl.position = -tl.map_to_local(Vector2i.ZERO) + V.ground(Vector2i.ZERO) - Vector2(0, h * V.STEP)
			tl.z_index = -10 + h
			add_child(tl)
			_floors[h] = tl
		kit.put_floor(_floors[h], c, _floor_id(c), "a" if posmod(c.x / 4 + c.y / 4, 2) == 0 else "b")
	_refresh_surfaces()
	_shade.queue_redraw()


func _refresh_surfaces() -> void:
	for n in _surface_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_surface_nodes.clear()
	var tiles := TileOverlay.new()
	tiles.z_index = 1
	_overlay.add_child(tiles)
	_surface_nodes.append(tiles)
	for c: Vector2i in grid.all_cells():
		var sid: String = grid.surface_id(c)
		var h: int = grid.height(c)
		if sid != "" and SURFACE_ART.has(sid):
			var a: Array = SURFACE_ART[sid]
			if a[0] == "tile":
				var info: Dictionary = kit.info(a[1])
				var f: Array = info.get("variants", {}).values()[0]["frames"][0]
				var src := Rect2(float(f[0]) + posmod(c.x, 4) * V.T, float(f[1]) + posmod(c.y, 4) * V.T, V.T, V.T)
				var col: Color = SURFACE_TINT.get(sid, Color(1, 1, 1, 0.92))
				tiles.items.append([V.top_rect(grid, c), kit._sheet(String(info["sheet"])), src, col])
			else:
				var node: Node2D = kit.make(a[1], a[2], {"collision": false})
				node.position = V.top(c, h) + Vector2(0, V.T * 0.25)
				if SURFACE_TINT.has(sid):
					node.modulate = SURFACE_TINT[sid]
				if a[1] == "flame" or a[1] == "weeds":
					sorted.add_child(node)
				else:
					_overlay.add_child(node)
				_surface_nodes.append(node)
		var cid: String = grid.cloud_id(c)
		if cid != "" and posmod(c.x + c.y, 2) == 0:
			var m: Node2D = kit.make("mist", CLOUD_ART.get(cid, "grey"), {"collision": false})
			m.position = V.top(c, h) + Vector2(V.T * 0.5, V.T * 0.4)
			m.z_index = 30
			m.modulate.a = 0.85
			add_child(m)
			_surface_nodes.append(m)
		var obj: Dictionary = grid.object_at(c)
		if not obj.is_empty():
			var ref: String = obj.get("art", "barrel.intact")
			var on: Node2D = kit.make(ref.get_slice(".", 0), ref.get_slice(".", 1), {"collision": false})
			on.position = V.top(c, h) + Vector2(0, V.T * 0.3)
			sorted.add_child(on)
			_surface_nodes.append(on)
	tiles.queue_redraw()


## 캐릭터를 가리는 블록(앞쪽이고 화면에서 겹침)을 반투명하게.
func update_occlusion(actor_rects: Array) -> void:
	for b in _blocks:
		var faded := false
		var rect := Rect2(b.position + Vector2(0, -V.WALL_H - V.T), Vector2(V.T, V.WALL_H + V.T))
		for ar: Array in actor_rects:
			if b.position.y > ar[1] + 8 and rect.intersects(ar[0]):
				faded = true
				break
		b.modulate.a = 0.4 if faded else 1.0
