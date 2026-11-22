extends Node3D
## 3/4 탑뷰 맵 그리기(표현 계층, 3D). GridWorld를 읽어 던전 에셋 키트(assets/dungeon_kit, scenes/kit/dungeon_kit.gd) 그림으로 쌓는다.
## 좌표는 view3d.gd(1칸 = 1유닛, 높이 1단계 = 1유닛).
## - 바닥: 칸마다 높이에 놓인 네모(키트 바닥 4×4 이어지는 그림). 맵 데이터 art.floors(범례 글자 → 키트 바닥)·재질 기본값.
##   floor.gdshader가 칸 데이터 텍스처(_info_tex·_cells_tex)로 칸마다 바닥을 찾아 그린다: 종류가 다른 바닥 경계는 들쭉날쭉 맞물리고
##   (같은 높이끼리만), 같은 바닥의 변형 a·b는 불규칙한 얼룩 경계로 섞인다(변형 b는 2칸 밀어 반복이 덜 보이게).
## - 벽: 칸마다 기둥(윗면 = 키트 벽 윗면 자동 연결 16가지, 남쪽 면 = 키트 벽면). 벽은 둘레에서 가장 높은 바닥 위에 선다(View3D.wall_base).
##   남쪽 칸 윗면이 더 낮으면 그 차이만큼 남쪽 면을 세운다(벽 아래로 더 내려가는 부분·높은 칸은 절벽 면).
## - 높은 칸 가장자리: 둘레보다 높은 바닥 윗면의 테두리에 어두운 턱 띠(보이지 않는 동·서·북 면 대신 경계를 읽히게).
##   카메라는 남쪽에서만 보므로(회전 없음) 동·서·북 면은 보이지 않아 만들지 않는다.
## - 소품: 맵 데이터 art.props(키트 물건 — 서 있는 것은 세운 판, 바닥 무늬는 눕힌 판). 규칙 물체(기름통 등)는 art 키 또는 기본 그림.
## - 표면·구름: 키트 바닥(물·얼음·진흙 — overlay.gdshader가 가장자리를 웅덩이처럼 흔듦)·불꽃 애니메이션·얼룩·안개로 그린다(규칙 상태를 그리기만).
## - 빛: 규칙의 빛 단계로 정점 색을 어둡게(칸 모서리마다 이웃 평균). 캐릭터를 가리는 앞쪽 벽·절벽은 체크무늬로 비친다.

const V := preload("res://scenes/battle/view3d.gd")
const DungeonKit := preload("res://scenes/kit/dungeon_kit.gd")
const Kit3D := preload("res://scenes/kit/kit3d.gd")
const TERRAIN_SHADER := preload("res://scenes/battle/terrain.gdshader")
const OVERLAY_SHADER := preload("res://scenes/battle/overlay.gdshader")
const FLOOR_SHADER := preload("res://scenes/battle/floor.gdshader")

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
## 벽 윗면·벽면·절벽 면 밝기(옛 2D와 같다)
const TOP_SHADE := 0.32
const FACE_SHADE := Color(0.78, 0.78, 0.74)
const CLIFF_SHADE := 0.8
## 벽 밑동 그늘 띠(유닛)·밝기
const FOOT_H := 0.15
const FOOT_SHADE := 0.65
## 높은 칸 턱 띠 너비(유닛)·가장자리 진하기
const RIM_W := 0.12
const RIM_ALPHA := 0.7

var grid: Node
var map: Dictionary = {}
var kit: RefCounted
var sorted: Node3D
## 지형 그물(바닥·벽윗면·벽면) 하나씩
var _floor_mi: MeshInstance3D
var _top_mi: MeshInstance3D
var _face_mi: MeshInstance3D
var _water_mi: MeshInstance3D
var _rim_mi: MeshInstance3D
## 칸 데이터 텍스처(셰이더용): 높이·바닥 있음 / 바닥 조각 / 표면 조각
var _info_tex: ImageTexture
var _cells_tex: ImageTexture
var _surf_tex: ImageTexture
var _mats := {}  # 이름 → ShaderMaterial
## 서 있는 큰 소품(나무·천막 등): 캐릭터를 가리면 반투명
var _tall_props: Array[Node3D] = []
## 소품 → 칸(빛 단계 색)
var _prop_cells := {}
var _surface_nodes: Array[Node] = []
## 같은 칸 정보면 지형을 다시 쌓지 않는다
var _terrain_key := ""


## 정점·UV·색을 모아 ArrayMesh로
class MeshBuilder:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()

	## p: 네 모서리(왼위·오른위·오른아래·왼아래 — 그림 기준), uv: 그림 네모(px), size: 그림 판 크기(px), c: 네 모서리 색
	## src2: 두 번째 그림 조각(바닥 변형 b). 쓰면 모든 네모에 준다.
	func quad(p: Array, src: Rect2, size: Vector2, c: Array, src2 := Rect2()) -> void:
		var n := verts.size()
		var uv := _corners(src, size)
		var uv2 := _corners(src2, size) if src2.size.x > 0.0 else []
		for i in 4:
			verts.append(p[i])
			uvs.append(uv[i])
			if not uv2.is_empty():
				uv2s.append(uv2[i])
			cols.append(c[i])
		idx.append_array(PackedInt32Array([n, n + 1, n + 2, n, n + 2, n + 3]))

	func _corners(src: Rect2, size: Vector2) -> Array:
		var inset := Vector2(0.25, 0.25)
		var a := (src.position + inset) / size
		var b := (src.end - inset) / size
		return [a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)]

	func mesh() -> ArrayMesh:
		var m := ArrayMesh.new()
		if verts.is_empty():
			return m
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_TEX_UV] = uvs
		if uv2s.size() == verts.size():
			arr[Mesh.ARRAY_TEX_UV2] = uv2s
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_INDEX] = idx
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m


func build(g: Node, sorted_layer: Node3D, map_data: Dictionary = {}) -> void:
	grid = g
	map = map_data
	sorted = sorted_layer
	kit = DungeonKit.open()
	kit.tileset()
	_floor_mi = _mesh_node("floors", FLOOR_SHADER, false)
	_top_mi = _mesh_node("wall_tops", TERRAIN_SHADER, true)
	_face_mi = _mesh_node("wall_faces", TERRAIN_SHADER, true)
	_water_mi = _mesh_node("floors", OVERLAY_SHADER, false, "floors_overlay")
	var rim_mat := StandardMaterial3D.new()
	rim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim_mat.vertex_color_use_as_albedo = true
	rim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rim_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	rim_mat.render_priority = 1
	_rim_mi = MeshInstance3D.new()
	_rim_mi.material_override = rim_mat
	_rim_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rim_mi)
	_build_props()
	refresh()


func _mesh_node(sheet: String, shader: Shader, cutaway: bool, key: String = "") -> MeshInstance3D:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("tex", kit._sheet(sheet))
	if cutaway:
		mat.set_shader_parameter("cutaway", true)
	if shader == OVERLAY_SHADER:
		mat.render_priority = 1
	_mats[key if key != "" else sheet] = mat
	var mi := MeshInstance3D.new()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


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


func _sheet_size(sheet: String) -> Vector2:
	var t: Texture2D = kit._sheet(sheet)
	return t.get_size() if t != null else Vector2.ONE


## 한 번만: 소품(맵 데이터 art.props)
func _build_props() -> void:
	for p: Dictionary in art().get("props", []):
		var cell := Vector2i(int(p["at"][0]), int(p["at"][1]))
		var node: Node3D = Kit3D.make(kit, p["id"], p.get("v", ""), {"flip": p.get("flip", false), "up": p.get("up", 0.0), "scale": float(p.get("scale", 1.0))})
		node.position = _prop_pos(cell, float(p.get("dx", 0.0)), float(p.get("dy", 0.0)))
		sorted.add_child(node)
		_prop_cells[node] = cell
		if String(node.get_meta("kit_layer", "stand")) == "stand" and (String(p["id"]).begins_with("tree") or p["id"] in ["tent", "pillar", "gibbet", "statue"]):
			_tall_props.append(node)


## 소품 발 위치. 옛 2D 배치(칸 가운데 + 아래로 0.3칸 + dx·dy px)를 바닥 위 위치로 옮긴다.
## 벽 칸의 소품(횃불·이끼·거미줄 등)은 벽 남쪽 면 바로 앞에 붙인다(dy px만큼 화면 위아래).
func _prop_pos(cell: Vector2i, dx: float, dy: float) -> Vector3:
	var x := cell.x + 0.5 + dx / V.T
	if grid.in_bounds(cell) and grid.has_flag(cell, "wall"):
		var south := cell + Vector2i.DOWN
		var base: float = maxf(V.wall_base(grid, cell), float(grid.height(south)) if grid.in_bounds(south) and not grid.has_flag(south, "wall") else 0.0)
		# 옛 2D: 발이 벽면 아래 끝에서 (0.2칸 − dy)px 위
		return Vector3(x, base + maxf(0.0, (V.T * 0.2 - dy) / V.STEP_PX), cell.y + 1.02)
	return Vector3(x, float(grid.height(cell)) if grid.in_bounds(cell) else 0.0, cell.y + 0.8 + dy / V.T)


## 칸 데이터가 바뀌면(표면·재질·빛) 다시 그린다.
func refresh() -> void:
	var key := _make_terrain_key()
	if key != _terrain_key:
		_terrain_key = key
		_build_terrain()
	_refresh_surfaces()
	for n: Node3D in _prop_cells:
		if is_instance_valid(n):
			Kit3D.tint(n, V.light_tint(grid, _prop_cells[n]))


func _make_terrain_key() -> String:
	var parts := PackedStringArray()
	for c: Vector2i in grid.all_cells():
		parts.append("%d%s%d" % [grid.light_at(c), grid.material(c), grid.height(c)])
	return "".join(parts)


## 칸 모서리(왼위 기준 d)의 어둠 = 둘레 네 칸 평균
func _corner_dark(dark: Dictionary, c: Vector2i, d: Vector2i) -> float:
	var s := 0.0
	var n := 0
	for o: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var k: Vector2i = c + d + o
		if dark.has(k):
			s += dark[k]
			n += 1
	return s / maxi(n, 1)


func _corner_cols(dark: Dictionary, c: Vector2i, base: Color) -> Array:
	var out := []
	for d: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
		var k := 1.0 - _corner_dark(dark, c, d)
		out.append(Color(base.r * k, base.g * k, base.b * k, base.a))
	return out


func _build_terrain() -> void:
	var dark := {}
	for c: Vector2i in grid.all_cells():
		dark[c] = V.DARK_ALPHA[grid.light_at(c)]
	var floors := MeshBuilder.new()
	var tops := MeshBuilder.new()
	var faces := MeshBuilder.new()
	var fsize := _sheet_size("floors")
	var tsize := _sheet_size("wall_tops")
	var wsize := _sheet_size("wall_faces")
	var wall_kind: String = art().get("wall", "cave")
	var top_kind: String = art().get("wall_top", wall_kind)
	var face_info: Dictionary = kit.info("wall_%s" % wall_kind)
	var top_info: Dictionary = kit.info("wall_top")
	var face_frame: Array = face_info.get("variants", {}).get("clean", {"frames": [[0, 0, 256, 160, 0, 0]]})["frames"][0]
	var top_frame: Array = top_info.get("variants", {}).get(top_kind, top_info.get("variants", {}).get("a", {"frames": [[0, 0, 256, 256, 0, 0]]}))["frames"][0]
	var cliff_frame: Array = kit.info("wall_%s" % art().get("cliff", wall_kind)).get("variants", {}).get("clean", {"frames": [face_frame]})["frames"][0]
	var t := float(V.T)
	var rims := MeshBuilder.new()
	for c: Vector2i in grid.all_cells():
		var x0 := float(c.x)
		var z0 := float(c.y)
		var top_c: float = V.cell_top(grid, c)
		var south := c + Vector2i.DOWN
		var has_south: bool = grid.in_bounds(south)
		var top_s: float = V.cell_top(grid, south) if has_south else top_c
		# 남쪽 면 밝기: 남쪽이 열린 바닥이면 그 칸(면이 보는 쪽), 아니면 자기 칸
		var k := 1.0 - float(dark.get(south, dark[c]) if has_south and not grid.has_flag(south, "wall") else dark[c])
		if grid.has_flag(c, "wall"):
			var mask := 0
			for bit: Array in [[1, Vector2i.UP], [2, Vector2i.RIGHT], [4, Vector2i.DOWN], [8, Vector2i.LEFT]]:
				var n: Vector2i = c + (bit[1] as Vector2i)
				if not grid.in_bounds(n) or grid.has_flag(n, "wall"):
					mask |= int(bit[0])
			var tsrc := Rect2(float(top_frame[0]) + (mask % 4) * t, float(top_frame[1]) + (mask / 4) * t, t, t)
			tops.quad(_flat_quad(x0, z0, top_c), tsrc, tsize, _corner_cols(dark, c, Color(TOP_SHADE, TOP_SHADE, TOP_SHADE)))
			if has_south and top_s < top_c:
				var base: float = V.wall_base(grid, c)
				var y0 := maxf(top_s, base)
				var state: String = ["clean", "cracked", "mossy", "damaged"][posmod(c.x * 7 + c.y * 13, 4)]
				var ff: Array = face_info.get("variants", {}).get(state, {"frames": [face_frame]})["frames"][0]
				var px := minf((top_c - y0) * V.STEP_PX, float(ff[3]))
				var src := Rect2(float(ff[0]) + posmod(c.x, 4) * t, float(ff[1]) + float(ff[3]) - px, t, px)
				_face(faces, x0, z0 + 1.0, y0, top_c, src, wsize, FACE_SHADE, k, not grid.has_flag(south, "wall"))
				if top_s < base:
					_cliff(faces, cliff_frame, wsize, x0, z0 + 1.0, top_s, base, k, false)
		else:
			var fsrc := _floor_src(c, "a")
			if fsrc.size.x > 0.0:
				# 변형 a·b가 모두 있을 때만 섞는다(하나뿐이면 같은 조각 — 섞임 없음)
				var vs: PackedStringArray = kit.variants(_floor_id(c))
				var fsrc2 := _floor_src(c, "b", Vector2i(2, 2)) if vs.has("a") and vs.has("b") else fsrc
				floors.quad(_flat_quad(x0, z0, top_c), fsrc, fsize, _corner_cols(dark, c, Color.WHITE), fsrc2)
			if has_south and top_s < top_c:
				_cliff(faces, cliff_frame, wsize, x0, z0 + 1.0, top_s, top_c, k, not grid.has_flag(south, "wall"))
			_rims(rims, c, top_c, 1.0 - float(dark[c]))
	_rim_mi.mesh = rims.mesh()
	_floor_mi.mesh = floors.mesh()
	_build_cell_textures()
	_top_mi.mesh = tops.mesh()
	_face_mi.mesh = faces.mesh()


## 셰이더용 칸 데이터: info(RG8: 높이·바닥 있음), cells(RGBA8: 변형 a·b 묶음 첫 조각)
func _build_cell_textures() -> void:
	var w: int = grid.size.x
	var h: int = grid.size.y
	var info := Image.create(w, h, false, Image.FORMAT_RG8)
	var cells := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for c: Vector2i in grid.all_cells():
		var wall: bool = grid.has_flag(c, "wall")
		info.set_pixel(c.x, c.y, Color8(clampi(grid.height(c), 0, 255), 0 if wall else 1, 0))
		if wall:
			continue
		var a := _floor_block(c, "a")
		var vs: PackedStringArray = kit.variants(_floor_id(c))
		var b := _floor_block(c, "b") if vs.has("a") and vs.has("b") else a
		cells.set_pixel(c.x, c.y, Color8(a.x, a.y, b.x, b.y))
	_info_tex = ImageTexture.create_from_image(info)
	_cells_tex = ImageTexture.create_from_image(cells)
	var fm: ShaderMaterial = _mats["floors"]
	fm.set_shader_parameter("cells", _cells_tex)
	fm.set_shader_parameter("info", _info_tex)
	fm.set_shader_parameter("map_size", Vector2i(w, h))
	fm.set_shader_parameter("atlas_px", _sheet_size("floors"))
	var om: ShaderMaterial = _mats["floors_overlay"]
	om.set_shader_parameter("info", _info_tex)
	om.set_shader_parameter("map_size", Vector2i(w, h))
	om.set_shader_parameter("atlas_px", _sheet_size("floors"))


## 칸 바닥 변형의 4×4 묶음 첫 조각(조각 단위)
func _floor_block(c: Vector2i, variant: String) -> Vector2i:
	var id := _floor_id(c)
	var tl: Dictionary = kit.tile_of("%s.%s" % [id, kit._variant_name(id, variant)])
	return tl.get("base", Vector2i.ZERO)


## 절벽 면: 한 단계(40px)씩 키트 벽면 조각을 아래에서부터 쌓는다(y0 → y1, 맨 위 조각은 남는 높이만큼).
func _cliff(mb: MeshBuilder, frame: Array, size: Vector2, x0: float, z: float, y0: float, y1: float, k: float, foot: bool) -> void:
	var t := float(V.T)
	var j := 0
	var y := y0
	while y < y1 - 0.001:
		var y_next := minf(y + 1.0, y1)
		var px := (y_next - y) * V.STEP_PX
		var sy := float(frame[1]) + float(frame[3]) - V.STEP_PX * posmod(j, 4) - px
		var src := Rect2(float(frame[0]) + posmod(int(x0), 4) * t, sy, t, px)
		_face(mb, x0, z, y, y_next, src, size, FACE_SHADE * CLIFF_SHADE, k, foot and j == 0)
		y = y_next
		j += 1


## 높은 칸 턱 띠: 이웃 윗면이 더 낮은 변마다 윗면 가장자리를 어둡게(가장자리 진하고 안쪽으로 옅어짐)
func _rims(mb: MeshBuilder, c: Vector2i, top_c: float, k: float) -> void:
	var y := top_c + V.LIFT * 0.5
	var x0 := float(c.x)
	var z0 := float(c.y)
	var edge := Color(0, 0, 0, RIM_ALPHA * clampf(k + 0.3, 0.0, 1.0))
	var fade := Color(0, 0, 0, 0)
	var w := RIM_W
	for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var n := c + d
		if not grid.in_bounds(n) or grid.has_flag(n, "wall") or float(grid.height(n)) >= top_c:
			continue
		var p: Array
		var cols: Array
		match d:
			Vector2i.UP:
				p = [Vector3(x0, y, z0), Vector3(x0 + 1, y, z0), Vector3(x0 + 1, y, z0 + w), Vector3(x0, y, z0 + w)]
				cols = [edge, edge, fade, fade]
			Vector2i.DOWN:
				p = [Vector3(x0, y, z0 + 1 - w), Vector3(x0 + 1, y, z0 + 1 - w), Vector3(x0 + 1, y, z0 + 1), Vector3(x0, y, z0 + 1)]
				cols = [fade, fade, edge, edge]
			Vector2i.LEFT:
				p = [Vector3(x0, y, z0), Vector3(x0 + w, y, z0), Vector3(x0 + w, y, z0 + 1), Vector3(x0, y, z0 + 1)]
				cols = [edge, fade, fade, edge]
			_:
				p = [Vector3(x0 + 1 - w, y, z0), Vector3(x0 + 1, y, z0), Vector3(x0 + 1, y, z0 + 1), Vector3(x0 + 1 - w, y, z0 + 1)]
				cols = [fade, edge, edge, fade]
		mb.quad(p, Rect2(0, 0, 1, 1), Vector2.ONE, cols)


## 수평 네모(그림 위 = 북쪽)
func _flat_quad(x0: float, z0: float, y: float) -> Array:
	return [Vector3(x0, y, z0), Vector3(x0 + 1, y, z0), Vector3(x0 + 1, y, z0 + 1), Vector3(x0, y, z0 + 1)]


## 남쪽을 보는 세운 면(z 고정, y0 → y1). foot이면 밑동 그늘 띠를 따로 어둡게.
func _face(mb: MeshBuilder, x0: float, z: float, y0: float, y1: float, src: Rect2, size: Vector2, shade: Color, k: float, foot: bool) -> void:
	var col := Color(shade.r * k, shade.g * k, shade.b * k)
	var split := y0 + FOOT_H if foot and y1 - y0 > FOOT_H * 2.0 else y0
	if split > y0:
		var fy := src.end.y - (split - y0) / (y1 - y0) * src.size.y
		var dim := Color(col.r * FOOT_SHADE, col.g * FOOT_SHADE, col.b * FOOT_SHADE)
		mb.quad([Vector3(x0, split, z), Vector3(x0 + 1, split, z), Vector3(x0 + 1, y0, z), Vector3(x0, y0, z)],
			Rect2(src.position.x, fy, src.size.x, src.end.y - fy), size, [col, col, dim, dim])
		src = Rect2(src.position, Vector2(src.size.x, fy - src.position.y))
	mb.quad([Vector3(x0, y1, z), Vector3(x0 + 1, y1, z), Vector3(x0 + 1, split, z), Vector3(x0, split, z)], src, size, [col, col, col, col])


## 칸의 키트 바닥 그림 네모(px). 넓은 그림(span 4)은 칸 좌표를 나눈 나머지 조각 — 이웃 칸과 이어진다.
## variant가 없으면 첫 변형. shift: 조각을 밀어 고른다(변형 b의 반복 위치를 a와 어긋나게).
func _floor_src(c: Vector2i, variant: String, shift := Vector2i.ZERO) -> Rect2:
	var id := _floor_id(c)
	var tl: Dictionary = kit.tile_of("%s.%s" % [id, kit._variant_name(id, variant)])
	if tl.is_empty():
		return Rect2()
	var span: Vector2i = tl["span"]
	var at: Vector2i = (tl["base"] as Vector2i) + Vector2i(posmod(c.x + shift.x, span.x), posmod(c.y + shift.y, span.y))
	return Rect2(Vector2(at) * V.T, Vector2(V.T, V.T))


func _refresh_surfaces() -> void:
	for n in _surface_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_surface_nodes.clear()
	var water := MeshBuilder.new()
	var fsize := _sheet_size("floors")
	var surf := Image.create(grid.size.x, grid.size.y, false, Image.FORMAT_RGBA8)
	var palette: Array[String] = []
	var water_cells := {}  # 네모를 깔 칸(표면 칸 + 둘레 — 셰이더가 흔든 가장자리를 그린다)
	for c: Vector2i in grid.all_cells():
		var sid: String = grid.surface_id(c)
		var h: float = float(grid.height(c))
		var tint := V.light_tint(grid, c)
		if sid != "" and SURFACE_ART.has(sid):
			var a: Array = SURFACE_ART[sid]
			if a[0] == "tile":
				var info: Dictionary = kit.info(a[1])
				var f: Array = info.get("variants", {}).values()[0]["frames"][0]
				if not sid in palette and palette.size() < 8:
					palette.append(sid)
				var pi := palette.find(sid)
				if pi >= 0:
					surf.set_pixel(c.x, c.y, Color8(int(f[0]) / V.T, int(f[1]) / V.T, pi + 1, 0))
					for dy in range(-1, 2):
						for dx in range(-1, 2):
							var n := c + Vector2i(dx, dy)
							if grid.in_bounds(n) and not grid.has_flag(n, "wall"):
								water_cells[n] = true
			else:
				var node: Node3D = Kit3D.make(kit, a[1], a[2])
				node.position = V.pos(c, h) + Vector3(0, 0.004 if node.rotation.x != 0.0 else 0.0, 0.25)
				var col: Color = SURFACE_TINT.get(sid, Color.WHITE)
				Kit3D.tint(node, Color(col.r * tint.r, col.g * tint.g, col.b * tint.b))
				sorted.add_child(node)
				_surface_nodes.append(node)
		var cid: String = grid.cloud_id(c)
		if cid != "" and posmod(c.x + c.y, 2) == 0:
			var m: Node3D = Kit3D.make(kit, "mist", CLOUD_ART.get(cid, "grey"))
			m.position = V.pos(c, h) + Vector3(0, 0, 0.4)
			var ms: Variant = m.get_meta("sprite", null)
			if ms is SpriteBase3D:
				(ms as SpriteBase3D).alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
				(ms as SpriteBase3D).modulate = Color(tint.r, tint.g, tint.b, 0.85)
			add_child(m)
			_surface_nodes.append(m)
		var obj: Dictionary = grid.object_at(c)
		if not obj.is_empty():
			var ref: String = obj.get("art", "barrel.intact")
			var on: Node3D = Kit3D.make(kit, ref.get_slice(".", 0), ref.get_slice(".", 1))
			on.position = V.pos(c, h) + Vector3(0, 0, 0.3)
			Kit3D.tint(on, tint)
			sorted.add_child(on)
			_surface_nodes.append(on)
	var dark := {}
	for c: Vector2i in grid.all_cells():
		dark[c] = V.DARK_ALPHA[grid.light_at(c)]
	for c: Vector2i in water_cells:
		# 어둠은 바닥과 같게 모서리마다 이웃 평균(칸 경계에 어두운 네모가 생기지 않게)
		water.quad(_flat_quad(c.x, c.y, float(grid.height(c)) + V.LIFT), Rect2(0, 0, 1, 1), fsize, _corner_cols(dark, c, Color.WHITE))
	_water_mi.mesh = water.mesh()
	_surf_tex = ImageTexture.create_from_image(surf)
	var tints := PackedVector4Array()
	for i in 8:
		var tc: Color = SURFACE_TINT.get(palette[i], Color(1, 1, 1, 0.92)) if i < palette.size() else Color.WHITE
		tints.append(Vector4(tc.r, tc.g, tc.b, tc.a))
	var om: ShaderMaterial = _mats["floors_overlay"]
	om.set_shader_parameter("surf", _surf_tex)
	om.set_shader_parameter("tints", tints)


## 캐릭터를 가리는 앞쪽 벽·절벽은 셰이더가 비춘다(발 위치·크기 배율 목록). 큰 소품은 반투명.
## actors: [[발 위치 Vector3, 크기 배율 float], ...]
func update_occlusion(actors: Array) -> void:
	var arr := PackedVector4Array()
	for a: Array in actors.slice(0, 24):
		var p: Vector3 = a[0]
		arr.append(Vector4(p.x, p.y, p.z, float(a[1])))
	var count := arr.size()
	arr.resize(24)
	for key: String in ["wall_tops", "wall_faces"]:
		var mat: ShaderMaterial = _mats[key]
		mat.set_shader_parameter("actors", arr)
		mat.set_shader_parameter("actor_count", count)
	for p in _tall_props:
		if not is_instance_valid(p):
			continue
		var hide := false
		for a: Array in actors:
			var ap: Vector3 = a[0]
			if p.position.z > ap.z + 0.1 and p.position.z - ap.z < 3.0 and absf(p.position.x - ap.x) < 1.2:
				hide = true
				break
		var s: Variant = p.get_meta("sprite", null)
		if s is SpriteBase3D:
			var sp := s as SpriteBase3D
			var target := 0.35 if hide else 1.0
			sp.modulate.a = lerpf(sp.modulate.a, target, 0.25)
			sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED if sp.modulate.a < 0.99 else SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
