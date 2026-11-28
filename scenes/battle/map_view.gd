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
## - 자연 지형(art.terrain = "natural", terrain_natural.gd): 높이 차 1단계 이하 이웃끼리는 부드러운 언덕, 2단계 이상은 바위 절벽
##   (art.cliff_rock = 키트 벽면 바위 그림 wall_<값>: cave·sandstone). 절벽 위·아래에 풀·바위를 흩고(art.cliff_decor = false로 끔),
##   오르기 지점(climb) 칸의 보이는 절벽 면에 사다리(art.climb_art = ladder·vines)를 세운다. 규칙 높이는 그대로(칸 가운데 = 규칙 높이).
## - 빛: 규칙의 빛 단계로 정점 색을 어둡게(칸 모서리마다 이웃 평균). 캐릭터를 가리는 앞쪽 벽·절벽은 체크무늬로 비친다.

const V := preload("res://scenes/battle/view3d.gd")
const DungeonKit := preload("res://scenes/kit/dungeon_kit.gd")
const Kit3D := preload("res://scenes/kit/kit3d.gd")
const TERRAIN_SHADER := preload("res://scenes/battle/terrain.gdshader")
const OVERLAY_SHADER := preload("res://scenes/battle/overlay.gdshader")
const FLOOR_SHADER := preload("res://scenes/battle/floor.gdshader")
const TerrainNatural := preload("res://scenes/battle/terrain_natural.gd")
const MapStamps := preload("res://scripts/rules/map_stamps.gd")
## 자연 지형 장식: 절벽 위(풀·덤불·작은 바위)·절벽 아래(바위·이끼 바위) — [키트 id, 변형, 확률]
const CLIFF_TOP_DECOR := [["grass_tall", "a", 0.22], ["grass_tall", "c", 0.14], ["bush", "a", 0.06], ["rock", "small_a", 0.08]]
const CLIFF_FOOT_DECOR := [["rock", "medium_a", 0.12], ["rock", "small_b", 0.12], ["boulder_mossy", "a", 0.04], ["grass_tall", "b", 0.1]]

## 흩뿌림 장식(도트 화면 — assets/pixel_decor, tools/make_decor.py): 키트 바닥 id → [칸당 개수, [[장식 id, 무게], ...]].
## 다른 바닥과 맞닿은 칸은 SCATTER_EDGE개를 더해 경계 쪽으로 붙인다(풀이 길 위로 넘어온 느낌). 맵 art.scatter = false면 끔,
## art.scatter_density = 배율, art.scatter = {바닥 id: [개수, [[id, 무게]...]]}로 바닥별 덮어쓰기.
const SCATTER := {
	"ground_meadow": [1.3, [["tuft", 6], ["flowers", 2], ["pebble", 0.4], ["leaf", 0.6]]],
	"ground_grass": [1.0, [["tuft", 6], ["flowers", 0.8], ["pebble", 0.5], ["leaf", 0.6]]],
	"ground_thicket": [1.4, [["tuft", 7], ["leaf", 1.5]]],
	"floor_dirt": [0.25, [["pebble", 3], ["leaf", 1], ["tuft", 0.6]]],
	"ground_hardpan": [0.2, [["pebble", 3], ["tuft", 1]]],
	"ground_rock": [0.25, [["pebble", 3], ["tuft", 1]]],
	"ground_mud": [0.1, [["pebble", 1], ["leaf", 1]]],
	"floor_cobble": [0.15, [["tuft", 2], ["pebble", 1]]],
}
const SCATTER_EDGE := 1.2
## 맵 둘레(도트 화면, 규칙 밖 그림만): 갈 수 없지만 이어져 보이는 지형. 맵 밖 SURROUND_W칸에 맵 바닥과 이어지는 바닥(둘레 바닥 + 얼룩),
## 경계 바로 바깥 SURROUND_BAND칸은 지형에 맞는 큰 나무·바위로 빽빽하게 막고(남쪽 = 화면 앞은 낮은 바위·덤불), 그 너머는 드문 나무·바위·풀.
## 아주 먼 곳만 살짝 어둡게(검은 바탕으로 사라지지 않는다). 지형 = 풀 바닥 40%↑ 숲, 아니면 바위 땅.
## 맵 art.surround: false = 끔, {biome, floor, patch, wall/low/far: [[id, 무게, [변형]]...], width, density}로 덮어쓰기.
const SURROUND_W := 16
const SURROUND_BAND := 2.6
## [id, 무게, 쓸 변형(null = 전부)] — 계절이 다른 변형(눈·단풍·마른 것)은 뺀다
const SURROUND_BIOMES := {
	"forest": {"floor": "", "patch": "floor_dirt",
		"wall": [["tree_broadleaf", 5, ["a", "b", "c"]], ["tree_pine", 3, ["a", "b"]], ["tree_giant", 0.8, ["a", "b"]], ["boulder_mossy", 1.5, ["a", "b"]]],
		"low": [["bush", 4, ["a", "b", "wide"]], ["boulder_mossy", 2, ["a", "b"]], ["stump", 0.8, ["mossy", "a"]], ["log", 0.8, ["mossy", "a"]]],
		"far": [["tree_broadleaf", 4, ["a", "b", "c", "young"]], ["tree_pine", 2, ["a", "b", "young"]], ["bush", 3, ["a", "b", "wide"]], ["boulder_mossy", 0.7, ["a", "b"]], ["stump", 0.4, ["mossy"]]]},
	"rocky": {"floor": "ground_rock", "patch": "ground_hardpan",
		"wall": [["column_natural", 3, ["a", "b"]], ["boulder_mossy", 4, ["a", "b"]], ["tree_pine", 0.8, ["a", "b"]]],
		"low": [["boulder_mossy", 3, ["a", "b"]], ["rubble", 2, null], ["rock", 2, null]],
		"far": [["boulder_mossy", 2, ["a", "b"]], ["rock", 3, null], ["rubble", 2, null], ["tree_pine", 0.8, ["a", "b"]]]},
	# 동굴(어두운 맵, 바위·맨땅 바닥): 돌기둥·석순·수정으로 막고, 너머는 석순·버섯·뼈
	"cave": {"floor": "ground_rock", "patch": "ground_hardpan",
		"wall": [["column_natural", 3, ["a", "b"]], ["stalagmite", 4, ["tall", "cluster", "cluster_b"]], ["rock_basalt", 1.5, ["columns_a", "columns_b", "spire"]], ["rock_crystal", 0.6, ["a", "b", "dim"]]],
		"low": [["stalagmite", 3, ["small", "broken"]], ["rock", 3, null], ["rubble", 2, ["small", "scatter"]], ["mushroom", 1, ["cluster_a", "cluster_b", "pale"]]],
		"far": [["stalagmite", 3, null], ["rock", 2, null], ["crystal", 0.5, ["blue_small", "violet_small"]], ["mushroom", 1, null], ["bones", 0.5, ["scatter_a", "scatter_b"]]]},
	# 던전(판석·벽돌 바닥): 무너진 기둥·석상·잔해로 막고, 너머는 쓰러진 기둥·잔해·뼈·부서진 통
	"dungeon": {"floor": "floor_flag", "patch": "floor_cracked",
		"wall": [["pillar", 3, ["intact", "cracked", "mossy"]], ["statue", 1, ["headless", "broken", "ruined"]], ["rubble", 3, ["large_b", "brick_large"]], ["column_natural", 1, ["a"]]],
		"low": [["rubble", 4, ["small", "small_b", "brick", "scatter"]], ["bones", 1.5, ["scatter_a", "pile", "ribcage"]], ["barrel", 1, ["broken", "toppled"]], ["crate", 1, ["broken"]]],
		"far": [["pillar", 2, ["broken", "stump", "fallen"]], ["rubble", 3, null], ["bones", 1, null], ["statue", 0.4, ["ruined"]]]},
	# 마을(포장 길): 집 벽·울타리·가로수로 막고, 너머는 통·상자·수레·우물·가로등
	"town": {"floor": "street_setts", "patch": "street_gravel",
		"wall": [["house_wall_stone", 2, ["plain", "plain_b", "window", "worn"]], ["wood_fence", 3, ["rail", "picket"]], ["street_tree", 2, ["ring", "trimmed"]]],
		"low": [["barrel", 3, ["intact", "stack"]], ["crate", 3, ["intact", "stack"]], ["wood_fence", 2, ["rail", "broken"]], ["cart", 1, ["sacks", "hay", "empty"]]],
		"far": [["street_tree", 2, ["ring", "trimmed"]], ["well", 0.3, ["plain"]], ["barrel", 1, null], ["crate", 1, null]], "density": 0.5},
}
const DECOR_KIT := "res://assets/pixel_decor/kit.json"

const MATERIAL_FLOORS := {"stone": "floor_flag", "earth": "floor_dirt", "grass": "ground_grass", "brush": "ground_thicket",
	"wood": "room_wood", "burnt_ground": "ground_ash", "metal": "floor_brick", "glass": "floor_flag", "cloth": "floor_old"}
## 표면 → 그림: ["tile", 키트 바닥] 또는 ["prop", 키트 id, 변형]
const SURFACE_ART := {
	"water": ["tile", "ground_water"], "deep_water": ["tile", "ground_water"], "ice": ["tile", "ground_ice"],
	"mud": ["tile", "ground_mud"], "electrified_water": ["tile", "ground_water"], "blood": ["tile", "ground_mud"],
	"oil": ["tile", "ground_mud"], "acid": ["tile", "ground_mud"], "poison": ["tile", "ground_mud"], "grease": ["tile", "ground_mud"],
	"fire": ["prop", "flame", "medium"], "burning_web": ["prop", "flame", "small"], "web": ["prop", "cobweb", "floor"],
	"thorns": ["prop", "weeds", "dead_bush"]}
## 표면 그림 방식(overlay.gdshader look): [방식(1 액체·2 진흙·3 얼음), 본색, 장식(0 없음·1 거품·2 기름 무지개)] — 도트 화면에서만
const SURFACE_LOOK := {"oil": [1, Color("#1e1a16"), 2], "grease": [1, Color("#4a4030"), 2], "blood": [1, Color("#5a1218"), 0],
	"acid": [1, Color("#3e5a16"), 1], "poison": [1, Color("#2e4a1e"), 1], "mud": [2, Color("#4a3624"), 0], "ice": [3, Color.WHITE, 0]}
const SURFACE_TINT := {"electrified_water": Color(0.6, 0.85, 1.4), "acid": Color(0.8, 1.2, 0.6)}
## 표면 반사 세기(overlay.gdshader 반사 층 — 도트 화면 거울 카메라 pixel_view가 비친 세계를 그린다). 진흙은 비치지 않는다.
const SURFACE_REFLECT := {"water": 0.5, "deep_water": 0.6, "electrified_water": 0.45, "ice": 0.3}
## 물을 나눈 표면 그림 층 소식: 반사 표면이 있는지·거울 높이(가장 많은 반사 칸의 바닥 높이) — battle_scene이 pixel_view로 넘긴다
var reflect_on := false
var reflect_h := 0.0
var reflect_version := 0
## 물가 소품 반사 짝 만들기(도트 화면 물 반사가 켜졌을 때 — battle_scene이 정한다)
static var reflect_doubles := true
const REFL_REACH := 7  # 반사 표면에서 북쪽·옆으로 몇 칸 안의 소품까지 짝을 만드나(큰 나무 높이까지 비친다)
var _refl_key := ""
var _sky_leafy := -1.0
var _refl_nodes: Array[Node3D] = []
const CLOUD_ART := {"steam": "grey", "fog": "grey", "magical_darkness": "black", "sleet": "blue", "stinking_cloud": "violet"}
## 벽 윗면·벽면·절벽 면 밝기(옛 2D와 같다). 폐허 벽 윗면은 윗돌 블록(CAP_SHADE).
const TOP_SHADE := 0.32
## 폐허 벽: 높이 배율 범위(벽 높이 × 0.42~1), 무너진 홈 확률·배율, 장식 확률(벽면 덩굴·이끼, 밑동 잔해, 밑동·윗면 풀)
const RUIN_H := Vector2(0.42, 1.0)
const RUIN_NOTCH := [0.14, 0.6]
const RUIN_DECOR := {"face": 0.32, "rubble": 0.22, "foot_tuft": 0.6, "top_tuft": 0.4}
const RUIN_FACE_ART := [["vines", 3], ["wall_moss", 3], ["wall_roots", 1.5]]
const FACE_SHADE := Color(0.78, 0.78, 0.74)
const CLIFF_SHADE := 0.8
## 벽 밑동 그늘 띠(유닛)·밝기
const FOOT_H := 0.15
const FOOT_SHADE := 0.65
## 높은 칸 턱 띠 너비(유닛)·가장자리 진하기
const RIM_W := 0.12
const RIM_ALPHA := 0.7

## 그림 도트 밀도(칸당 도트, 0 = 도트 아님). 도트 화면이 켜지면 battle_scene이 정한다(assets/pixel_kit = 32).
## 바닥 경계를 이 격자에 맞추고, 흩뿌림 장식 크기도 도트에 맞춘다.
static var art_dots := 0.0

var grid: Node
var map: Dictionary = {}
var kit: RefCounted
var sorted: Node3D
## 지형 그물(바닥·벽윗면·벽면) 하나씩
var _floor_mi: MeshInstance3D
var _top_mi: MeshInstance3D
## 폐허 벽 윗면: 칸마다 크기·높이가 다른 윗돌 블록 그물(map_view._ruin_cap — 앞면이 보여 입체), 재질 assets/pixel_decor/ruin_stone.png(돌·이끼)
var _ruin_top_mi: MeshInstance3D
const RUIN_TOP_TEX := "res://assets/pixel_decor/ruin_stone.png"
## 윗돌: 높이(벽 윗면 위 유닛 범위), 빠진 돌 확률, 이끼 확률(얼룩 밖), 밝기(윗면·앞면·줄눈)
const CAP_H := Vector2(0.05, 0.3)
const CAP_MISSING := 0.08
const CAP_MOSS := 0.05
const CAP_SHADE := [0.78, 0.5, 0.22]
var _face_mi: MeshInstance3D
var _water_mi: MeshInstance3D
var _rim_mi: MeshInstance3D
## 자연 지형(없으면 블록 지형)
var natural: RefCounted
## 지형 도장이 덮은 칸(바닥 그림 floor) — 규칙 쪽 map_stamps.gd와 같은 계산
var _stamp_cells := {}
var _height_key := ""
## 칸 데이터 텍스처(셰이더용): 높이·바닥 있음 / 바닥 조각 / 표면 조각
var _info_tex: ImageTexture
var _cells_tex: ImageTexture
var _surf_tex: ImageTexture
var _mats := {}  # 이름 → ShaderMaterial
## 서 있는 큰 소품(나무·천막 등): 캐릭터를 가리면 반투명
var _tall_props: Array[Node3D] = []
## 둘레가 켜진 자연 지형 맵: 맵 가장자리 벽 칸(규칙상 경계)은 벽으로 그리지 않고 둘레 바닥·숲으로 덮는다
var _veil := {}
## 폐허 벽(바깥 맵의 블록 지형): 벽 높이를 칸마다 들쭉날쭉(그림만), 윗면 밝게, 덩굴·잔해 장식
var _ruin := false
## 둘레 거리를 재는 놀이 영역(가장자리 벽을 덮으면 그 안쪽)
var _play := Rect2()
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
	# 드리운 그림자: 해가 있는 맵(밝음·어스름)만, 도트 화면에서
	Kit3D.cast_strength = 0.0 if art_dots <= 0.0 else {"bright": 0.45, "dim": 0.26}.get(String(map.get("light", "bright")), 0.0)
	sorted = sorted_layer
	kit = DungeonKit.open()
	kit.tileset()
	_stamp_cells = MapStamps.cells(map)
	_floor_mi = _mesh_node("floors", FLOOR_SHADER, false)
	_top_mi = _mesh_node("wall_tops", TERRAIN_SHADER, true)
	_face_mi = _mesh_node("wall_faces", TERRAIN_SHADER, true)
	_water_mi = _mesh_node("floors", OVERLAY_SHADER, false, "floors_overlay")
	_water_mi.layers = PixelView.WATER_LAYER  # 물 전용 층(도트 카메라는 보고 거울 카메라는 안 본다 — 층은 한 비트라도 겹치면 보인다)
	# 자연 암벽: 키트 벽면 중 바위 그림(wall_cave 등 — cliff_drop은 아래로 꺼지는 낭떠러지라 검다)
	var rock_f: Array = kit.info("wall_%s" % String(art().get("cliff_rock", "cave"))).get("variants", {}).get("clean", {"frames": [[0, 0, 256, 160]]})["frames"][0]
	if String(art().get("terrain", "block")) == "natural":
		natural = TerrainNatural.new(grid)
		_height_key = _make_height_key()
		var fm: ShaderMaterial = _mats["floors"]
		fm.set_shader_parameter("rock_on", true)
		fm.set_shader_parameter("rock_tex", kit._sheet("wall_faces"))
		fm.set_shader_parameter("rock_frame", Vector4(float(rock_f[0]), float(rock_f[1]), float(rock_f[2]), float(rock_f[3])))
		fm.set_shader_parameter("rock_atlas", _sheet_size("wall_faces"))
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
	if _stamp_cells.has(c) and (_stamp_cells[c] as Dictionary).has("floor"):
		return _stamp_cells[c]["floor"]
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
	for p: Dictionary in art().get("props", []) + MapStamps.props(map):
		var cell := Vector2i(int(p["at"][0]), int(p["at"][1]))
		var node: Node3D = Kit3D.make(kit, p["id"], p.get("v", ""), {"flip": p.get("flip", false), "up": p.get("up", 0.0), "scale": float(p.get("scale", 1.0))})
		node.position = _prop_pos(cell, float(p.get("dx", 0.0)), float(p.get("dy", 0.0)))
		sorted.add_child(node)
		_lay_on_ground(node)
		_prop_cells[node] = cell
		if String(node.get_meta("kit_layer", "stand")) == "stand" and (String(p["id"]).begins_with("tree") or p["id"] in ["tent", "pillar", "gibbet", "statue"]):
			_tall_props.append(node)
	if art_dots > 0.0 and not (art().get("scatter", true) is bool and not bool(art().get("scatter", true))):
		_build_scatter()
	if art_dots > 0.0:
		_build_surround()
		_build_canopy()
		_ruin = natural == null and bool(art().get("ruin", art().get("surround", null) != false)) and String(art().get("wall", "cave")) == "stone"
		if _ruin:
			_build_ruin_decor()
		elif natural == null and bool(art().get("wall_decor", true)):
			_build_ruin_decor(0.55, false)  # 실내·동굴 벽도 벽면 이끼·뿌리·밑동 잔해(풀은 없이, 조금 덜)
	if natural != null:
		if bool(art().get("cliff_decor", true)):
			_build_cliff_decor()
		_build_climb_art()
		for n: Node3D in _prop_cells:
			if String(n.get_meta("kit_layer", "")) == "stand" and n.get_meta("kit_id", "") != "ladder":
				_blob_shadow(n)


static var _blob_tex: Texture2D


## 서 있는 소품 발밑 그림자(자연 지형): 그림 폭에 맞춘 부드러운 타원, 키가 클수록 햇빛 반대쪽(남동)으로 밀린다.
func _blob_shadow(n: Node3D) -> void:
	var sp: Variant = n.get_meta("sprite", null)
	if not (sp is SpriteBase3D):
		return
	var size := Vector2(64, 64)
	if sp is Sprite3D and (sp as Sprite3D).texture != null:
		size = (sp as Sprite3D).texture.get_size()
	elif sp is AnimatedSprite3D and (sp as AnimatedSprite3D).sprite_frames != null:
		size = (sp as AnimatedSprite3D).sprite_frames.get_frame_texture(&"default", 0).get_size()
	if _blob_tex == null:
		var gr := Gradient.new()
		gr.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		gr.colors = PackedColorArray([Color(0, 0, 0, 0.42), Color(0, 0, 0, 0.3), Color(0, 0, 0, 0)])
		var gt := GradientTexture2D.new()
		gt.gradient = gr
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 64
		gt.height = 64
		_blob_tex = gt
	var k: float = n.scale.x
	var rad := clampf(size.x / V.T * 0.42 * k, 0.18, 1.3)
	var tall := size.y / V.STEP_PX * k  # 그림 키(높이 단계)
	var l := TerrainNatural.SUN.normalized()
	var away := -Vector2(l.x, l.z).normalized() * minf(tall * 0.22, 1.1)
	var s := Sprite3D.new()
	s.texture = _blob_tex
	s.pixel_size = rad * 2.0 / 64.0
	s.shaded = false
	s.double_sided = true
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	s.render_priority = 1
	s.rotation.x = -PI / 2.0
	s.scale = Vector3(1.0 + minf(tall * 0.08, 0.6), 0.75, 1.0)
	var at := Vector2(n.position.x, n.position.z) + away
	s.position = Vector3(at.x, ground_at(at) + 0.008, at.y)
	add_child(s)


func _add_prop(id: String, variant: String, pos: Vector3, cell: Vector2i, opts: Dictionary = {}) -> Node3D:
	var node: Node3D = Kit3D.make(kit, id, variant, opts)
	node.position = pos
	sorted.add_child(node)
	_prop_cells[node] = cell
	_lay_on_ground(node)
	return node


## 땅의 기울기(칸 평면 점) — 그려진 바닥에서 잰 법선
func ground_normal(p: Vector2) -> Vector3:
	var e := 0.2
	var dx := (ground_at(p + Vector2(e, 0)) - ground_at(p - Vector2(e, 0))) / (2.0 * e)
	var dz := (ground_at(p + Vector2(0, e)) - ground_at(p - Vector2(0, e))) / (2.0 * e)
	return Vector3(-dx, 1.0, -dz).normalized()


## 눕힌 판(바닥 무늬·표면 얼룩)을 자연 지형의 비탈에 맞춰 기울인다(절벽처럼 가파른 곳은 너무 세우지 않게 제한).
func _lay_on_ground(node: Node3D) -> void:
	if natural == null or String(node.get_meta("kit_layer", "")) != "decal" or node.rotation.x == 0.0:
		return
	var n := ground_normal(Vector2(node.position.x, node.position.z))
	if n.y < 0.6:
		n = Vector3(n.x, 0.6, n.z).normalized()
	node.basis = Basis(Quaternion(Vector3.UP, n)) * node.basis
	node.position.y += 0.01

## 절벽 위 가장자리·아래 발치에 풀·바위를 흩는다(칸·방향으로 정한 난수 — 매번 같은 배치).
## 오르기 지점·물체·맵 이동 칸은 비운다.
func _build_cliff_decor() -> void:
	var busy := {}
	for o: Variant in map.get("objects", []) + map.get("transitions", []) + map.get("spawns", []):
		if o is Dictionary and (o as Dictionary).has("cell"):
			busy[Vector2i(int(o["cell"][0]), int(o["cell"][1]))] = true
	for e: Array in natural.cliff_edges():
		var hi: Vector2i = e[0]
		var lo: Vector2i = e[1]
		var d: Vector2i = lo - hi
		for side in 2:
			var cell: Vector2i = hi if side == 0 else lo
			if busy.has(cell) or grid.has_flag(cell, "climb"):
				continue
			var table: Array = CLIFF_TOP_DECOR if side == 0 else CLIFF_FOOT_DECOR
			var r := _rand(cell, d, side)
			var acc := 0.0
			for row: Array in table:
				acc += float(row[2])
				if r < acc:
					# 가장자리 쪽으로 붙이고(위: 변에서 0.22 안쪽, 아래: 0.3 앞) 변을 따라 흩는다
					var along := (_rand(cell, d, side + 7) - 0.5) * 0.7
					var edge_pt := Vector2(cell) + Vector2(0.5, 0.5) + Vector2(d) * (0.28 if side == 0 else -0.2)
					var pt := edge_pt + Vector2(absf(d.y), absf(d.x)) * along
					_add_prop(row[0], row[1], Vector3(pt.x, ground_at(pt), pt.y), cell, {"flip": _rand(cell, d, 3) < 0.5})
					break


## 오르기 지점: 보이는 절벽 면(높은 칸이 북·동·서쪽)에 사다리나 덩굴을 세운다. 높이 차에 맞춰 늘인다.
func _build_climb_art() -> void:
	var kind := String(art().get("climb_art", "ladder"))
	var done := {}
	for e: Array in natural.cliff_edges():
		var hi: Vector2i = e[0]
		var lo: Vector2i = e[1]
		if not (grid.has_flag(hi, "climb") or grid.has_flag(lo, "climb")):
			continue
		var d: Vector2i = lo - hi  # 높은 칸에서 낮은 칸 쪽
		if d == Vector2i.UP or done.has([hi, lo]):
			continue  # 북쪽을 보는 면은 화면에서 보이지 않는다
		done[[hi, lo]] = true
		var edge := (Vector2(hi) + Vector2(0.5, 0.5) + Vector2(d) * 0.5)
		var top_y := ground_at(edge - Vector2(d) * 0.05)
		var foot := edge + Vector2(d) * 0.3
		var dh := top_y - ground_at(foot)
		var pos := Vector3(foot.x, ground_at(foot), foot.y)
		var node: Node3D
		if kind == "vines":
			node = _add_prop("vines", "ivy_a", pos + Vector3(0, dh, 0), lo)
		else:
			node = _add_prop("ladder", "wall", pos, lo)
			# 그림 176px(원점 위) → 높이 차 + 반 단계
			var k := (dh + 0.5) * V.STEP_PX / 176.0
			node.scale = Vector3(1.0, V.UPRIGHT * k, 1.0)


## 흩뿌림: 칸마다 정한 난수(매번 같은 배치)로 칸 안 아무 데나. 벽·물체·맵 이동·오르기 칸·가파른 곳·소품 칸은 비운다.
func _build_scatter() -> void:
	var dk: RefCounted = DungeonKit.open(DECOR_KIT)
	if dk.data.is_empty():
		return
	var table: Dictionary = SCATTER.duplicate()
	var over: Variant = art().get("scatter", true)
	if over is Dictionary:
		table.merge(over, true)
	var mul := float(art().get("scatter_density", 1.0))
	var busy := {}
	for o: Variant in map.get("objects", []) + map.get("transitions", []) + map.get("spawns", []):
		if o is Dictionary and (o as Dictionary).has("cell"):
			busy[Vector2i(int(o["cell"][0]), int(o["cell"][1]))] = true
	for n: Node3D in _prop_cells:
		busy[_prop_cells[n]] = true
	for c: Vector2i in grid.all_cells():
		if busy.has(c) or grid.has_flag(c, "wall") or grid.has_flag(c, "climb") or grid.object_at(c).size() > 0:
			continue
		var fid := _floor_id(c)
		var row: Variant = table.get(fid, null)
		if not (row is Array) or (row as Array).size() < 2:
			continue
		# 맞닿은 다른 바닥 쪽(경계 덤불)
		var edge := Vector2.ZERO
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var nb := c + d
			if grid.in_bounds(nb) and not grid.has_flag(nb, "wall") and _floor_id(nb) != fid and grid.height(nb) == grid.height(c):
				edge += Vector2(d)
		var want := float(row[0]) * mul
		var grassy := fid.contains("grass") or fid.contains("meadow") or fid.contains("thicket")
		if grassy and edge != Vector2.ZERO:
			want += SCATTER_EDGE * mul
		# 덤불 무리: 3칸 크기 얼룩으로 밀도를 0.15~2배(빈 땅과 우거진 곳이 갈리게)
		want *= _patch(Vector2(c)) if grassy else 1.0
		var count := int(want) + (1 if _rand(c, Vector2i.ZERO, 91) < want - floorf(want) else 0)
		var tint := V.light_tint(grid, c)
		for i in count:
			var pt := Vector2(c) + Vector2(_rand(c, Vector2i(i, 1), 13), _rand(c, Vector2i(i, 2), 17)) * 0.9 + Vector2(0.05, 0.05)
			var id := _pick_weighted(row[1], _rand(c, Vector2i(i, 3), 23))
			if grassy and edge != Vector2.ZERO and i >= int(float(row[0]) * mul):
				# 경계 덤불: 맞닿은 쪽 변으로 붙이고 조금 넘어가게
				id = "tuft"
				var e := edge.normalized()
				var along := Vector2(-e.y, e.x) * (_rand(c, Vector2i(i, 4), 29) - 0.5) * 0.9
				pt = Vector2(c) + Vector2(0.5, 0.5) + e * (0.38 + _rand(c, Vector2i(i, 5), 31) * 0.2) + along
			if natural != null and ground_normal(pt).y < 0.8:
				continue
			var vs: PackedStringArray = dk.variants(id)
			if vs.is_empty():
				continue
			var v := vs[int(_rand(c, Vector2i(i, 6), 37) * vs.size()) % vs.size()]
			# 덤불은 1~3개를 붙여 한 무리로
			var clump := 1 + int(_rand(c, Vector2i(i, 8), 43) * 2.6) if id == "tuft" else 1
			for j in clump:
				var q := pt + (Vector2(_rand(c, Vector2i(i, 10 + j), 47), _rand(c, Vector2i(i, 20 + j), 53)) - Vector2(0.5, 0.5)) * (0.3 if j > 0 else 0.0)
				var vj := v if j == 0 else vs[int(_rand(c, Vector2i(i, 30 + j), 59) * vs.size()) % vs.size()]
				var node: Node3D = Kit3D.make(dk, id, vj, {"flip": _rand(c, Vector2i(i, 7 + j), 41) < 0.5})
				node.position = Vector3(q.x, ground_at(q) if natural != null else float(grid.height(c)), q.y)
				if String(node.get_meta("kit_layer", "")) == "decal":
					node.position.y += V.LIFT
				Kit3D.tint(node, tint)
				sorted.add_child(node)
				_lay_on_ground(node)


## 맵 둘레: 맵 밖 바닥(맵 바닥과 이어 섞는 칸 데이터 + 둘레 바닥·얼룩) + 막는 띠(큰 나무·바위) + 그 너머 드문 나무·바위·풀
func _build_surround() -> void:
	var cfg: Variant = art().get("surround", null)
	if cfg is bool and not bool(cfg):
		return
	var opt: Dictionary = cfg if cfg is Dictionary else {}
	var biome_id := String(opt.get("biome", _surround_biome()))
	var biome: Dictionary = (SURROUND_BIOMES.get(biome_id, SURROUND_BIOMES["forest"]) as Dictionary).duplicate()
	biome.merge(opt, true)
	var floor_id := String(biome.get("floor", ""))
	if floor_id == "":
		floor_id = _most_common_floor(["grass", "meadow", "thicket"], "ground_grass")
	var patch_id := String(biome.get("patch", ""))
	var w := int(opt.get("width", SURROUND_W))
	_play = Rect2(Vector2.ZERO, Vector2(grid.size))
	if natural != null:
		for c: Vector2i in grid.all_cells():
			if grid.has_flag(c, "wall") and (c.x == 0 or c.y == 0 or c.x == grid.size.x - 1 or c.y == grid.size.y - 1):
				_veil[c] = true
		if not _veil.is_empty():
			_play = Rect2(Vector2.ONE, Vector2(grid.size) - Vector2(2, 2))
	# 칸 데이터: 맵 칸은 맵 바닥 그대로(경계에서 이어 섞이게), 둘레 칸은 둘레 바닥 + 얼룩
	var org := Vector2i(-w, -w)
	var tw: int = grid.size.x + 2 * w
	var th: int = grid.size.y + 2 * w
	var cimg := Image.create(tw, th, false, Image.FORMAT_RGBA8)
	var iimg := Image.create(tw, th, false, Image.FORMAT_RG8)
	var main_ab := _floor_ab(floor_id)
	var patch_ab := _floor_ab(patch_id) if patch_id != "" else main_ab
	for y in th:
		for x in tw:
			var c := Vector2i(x, y) + org
			var ab: Vector4i
			var hh := 0
			if grid.in_bounds(c) and not _veil.has(c):
				if grid.has_flag(c, "wall"):
					iimg.set_pixel(x, y, Color8(clampi(grid.height(c), 0, 255), 0, 0))
					continue
				var fa := _floor_block(c, "a")
				var vs: PackedStringArray = kit.variants(_floor_id(c))
				var fb := _floor_block(c, "b") if vs.has("a") and vs.has("b") else fa
				ab = Vector4i(fa.x, fa.y, fb.x, fb.y)
				hh = grid.height(c)
			else:
				ab = patch_ab if _patch(Vector2(c) * 1.7 + Vector2(40, 40)) > 1.6 else main_ab
				hh = roundi(_edge_height(Vector2(c) + Vector2(0.5, 0.5)))
			cimg.set_pixel(x, y, Color8(ab.x, ab.y, ab.z, ab.w))
			iimg.set_pixel(x, y, Color8(clampi(hh, 0, 255), 1, 0))
	var mat: ShaderMaterial = (_mats["floors"] as ShaderMaterial).duplicate()
	mat.set_shader_parameter("cells", ImageTexture.create_from_image(cimg))
	mat.set_shader_parameter("info", ImageTexture.create_from_image(iimg))
	mat.set_shader_parameter("map_size", Vector2i(tw, th))
	mat.set_shader_parameter("cell_origin", org)
	mat.set_shader_parameter("blend_dh", 1.0)
	mat.set_shader_parameter("rock_on", false)
	mat.set_shader_parameter("dot_px", art_dots)
	_surround_mat = mat
	var mb := MeshBuilder.new()
	var fsize := _sheet_size("floors")
	for y in range(-w, grid.size.y + w):
		for x in range(-w, grid.size.x + w):
			if grid.in_bounds(Vector2i(x, y)) and not _veil.has(Vector2i(x, y)):
				continue
			var ps := []
			var cs := []
			for o: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
				var pt := Vector2(x, y) + o
				ps.append(Vector3(pt.x, _edge_height(pt), pt.y))
				var k := _surround_fade(pt, _play, w) * _amb_k()
				cs.append(Color(k, k, k))
			mb.quad(ps, Rect2(0, 0, 1, 1), fsize, cs)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.mesh()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# 막는 띠(경계에서 SURROUND_BAND칸) → 그 너머 드문 나무·바위
	var dens := float(biome.get("density", 1.0))
	var dk: RefCounted = DungeonKit.open(DECOR_KIT)
	for y in range(-w, grid.size.y + w):
		for x in range(-w, grid.size.x + w):
			var c := Vector2i(x, y)
			if grid.in_bounds(c) and not _veil.has(c):
				continue
			var pt := Vector2(c) + Vector2(_rand(c, Vector2i(1, 1), 61), _rand(c, Vector2i(2, 2), 67)) * 0.8 + Vector2(0.1, 0.1)
			var d := _out_dist(pt, _play)
			var south := pt.y > _play.end.y - 0.2 and absf(pt.x - _play.get_center().x) < _play.size.x * 0.5 + d
			var k := _surround_fade(pt, _play, w) * _amb_k()
			var tint := Color(k, k, k)
			var r := _rand(c, Vector2i(3, 3), 71)
			var list := ""
			if d < SURROUND_BAND:
				list = "low" if south else "wall"
				if r > (0.6 if south else 0.78) * dens or (south and d < 1.1):
					list = ""  # 남쪽 첫 칸은 비운다(맨 아래 줄 캐릭터를 가리지 않게)
			elif r < 0.13 * dens:
				list = "low" if south and d < 7.0 else "far"
			if list != "":
				var row := _pick_row(biome[list], _rand(c, Vector2i(4, 4), 73))
				var id := String(row[0])
				var vs: PackedStringArray = kit.variants(id)
				if row.size() > 2 and row[2] is Array:
					vs = PackedStringArray(row[2])
				if not vs.is_empty():
					var v := vs[int(_rand(c, Vector2i(5, 5), 79) * vs.size()) % vs.size()]
					var node: Node3D = Kit3D.make(kit, id, v, {"flip": _rand(c, Vector2i(6, 6), 83) < 0.5})
					node.position = Vector3(pt.x, _edge_height(pt), pt.y)
					Kit3D.tint(node, tint)
					sorted.add_child(node)
					if not id.begins_with("rock") and not id.begins_with("rubble"):
						_tall_props.append(node)
			# 풀 덤불: 띠는 빽빽하게, 너머는 드문드문
			if dk.data.is_empty() or (biome_id == "rocky" and r > 0.5):
				continue
			var tufts := int(_rand(c, Vector2i(7, 7), 89) * (3.0 if d < SURROUND_BAND else 1.6))
			var vs2: PackedStringArray = dk.variants("tuft")
			for j in tufts:
				var q := Vector2(c) + Vector2(_rand(c, Vector2i(8, j), 97), _rand(c, Vector2i(9, j), 101))
				var n2: Node3D = Kit3D.make(dk, "tuft", vs2[int(_rand(c, Vector2i(10, j), 103) * vs2.size()) % vs2.size()], {"flip": _rand(c, Vector2i(11, j), 107) < 0.5})
				n2.position = Vector3(q.x, _edge_height(q), q.y)
				Kit3D.tint(n2, tint)
				sorted.add_child(n2)


## 둘레 지형: 풀 바닥이 40% 넘으면 숲, 아니면 바위 땅
## 둘레 지형 고르기: 풀 40%↑ 숲, 어두운 맵 = 동굴(판석·실내 바닥 40%↑면 던전), 포장 길 40%↑ 마을, 실내 바닥 40%↑ 던전, 나머지 바위 땅
func _surround_biome() -> String:
	var open := 0
	var green := 0
	var street := 0
	var inner := 0
	for c: Vector2i in grid.all_cells():
		if grid.has_flag(c, "wall"):
			continue
		open += 1
		var f := _floor_id(c)
		if f.contains("grass") or f.contains("meadow") or f.contains("thicket"):
			green += 1
		elif f.begins_with("street_") or f == "floor_cobble":
			street += 1
		elif f.begins_with("floor_") and f != "floor_dirt" and f != "floor_sand" or f.begins_with("room_"):
			inner += 1
	if open == 0:
		return "rocky"
	var k := 1.0 / float(open)
	if green * k >= 0.4:
		return "forest"
	if String(map.get("light", "bright")) == "dark":
		return "cave" if inner * k < 0.4 else "dungeon"
	if street * k >= 0.4:
		return "town"
	if inner * k >= 0.4:
		return "dungeon"
	return "rocky"


## 맵에서 가장 많이 쓴 바닥(이름에 keys 중 하나가 든 것), 없으면 fallback
func _most_common_floor(keys: Array, fallback: String) -> String:
	var count := {}
	for c: Vector2i in grid.all_cells():
		if grid.has_flag(c, "wall"):
			continue
		var f := _floor_id(c)
		for k: String in keys:
			if f.contains(k):
				count[f] = int(count.get(f, 0)) + 1
	var best := fallback
	var n := 0
	for f: String in count:
		if int(count[f]) > n:
			n = int(count[f])
			best = f
	return best


## 키트 바닥 id → 변형 a·b 묶음 첫 조각(칸 데이터 RGBA)
func _floor_ab(id: String) -> Vector4i:
	var ta: Dictionary = kit.tile_of("%s.%s" % [id, kit._variant_name(id, "a")])
	var tb: Dictionary = kit.tile_of("%s.%s" % [id, kit._variant_name(id, "b")])
	var a: Vector2i = ta.get("base", Vector2i.ZERO)
	var b: Vector2i = tb.get("base", a)
	return Vector4i(a.x, a.y, b.x, b.y)


## 화면에 씌우는 빛과 그림자의 빛 지도(pixel_light.gdshader가 화면 깊이로 세계 위치를 되짚어 찾는다). 그림만 — 규칙 빛 단계는 그대로.
## glow(RGBA8): 광원 빛 = 색 × 세기(가장자리로 갈수록 약하게, 광원에서 시야선이 닿는 칸만), info(RGB8): 빛 단계·드리운 그림자·광원 뺀 기본 빛.
## 드리운 그림자: 북서쪽 해(높이각 tan = SUN_TAN) — 북서쪽으로 거슬러 올라가며 더 높은 칸(벽 윗면·높은 땅)이 해를 가리면 그늘.
## 맵 밖(둘레)은 맵 기본 빛 단계, 그림자 없음. 갱신은 칸 빛·높이가 바뀔 때(refresh의 지형 키).
const LIGHT_RES := 4
const SUN_TAN := 0.9
const LIGHT_COLORS := [["fire", Color(1.0, 0.6, 0.26)], ["torch", Color(1.0, 0.62, 0.28)], ["brazier", Color(1.0, 0.58, 0.24)],
	["ember", Color(1.0, 0.5, 0.22)], ["camp", Color(1.0, 0.62, 0.3)], ["glow", Color(0.55, 0.78, 1.0)], ["moon", Color(0.7, 0.8, 1.0)],
	["light", Color(1.0, 0.92, 0.7)], ["carried", Color(1.0, 0.82, 0.5)]]
var lighting: Dictionary = {}
var lighting_version := 0


func _light_color(id: String) -> Color:
	for row: Array in LIGHT_COLORS:
		if id.contains(String(row[0])):
			return row[1]
	return Color(1.0, 0.78, 0.48)


func _build_lighting() -> void:
	var w := SURROUND_W if not _play.size.is_zero_approx() else 2
	var org := Vector2(-w, -w)
	var cells := Vector2i(grid.size.x + 2 * w, grid.size.y + 2 * w)
	var iw := cells.x * LIGHT_RES
	var ih := cells.y * LIGHT_RES
	var base := 1.0
	match String(map.get("light", "bright")):
		"dark":
			base = 0.0
		"dim":
			base = 0.5
	# 빛 단계·광원 뺀 기본 빛: 칸 단위로 통째로 칠한다
	var info := Image.create(iw, ih, false, Image.FORMAT_RGB8)
	info.fill(Color(base, 0, base))
	for c: Vector2i in grid.all_cells():
		var o := (c - Vector2i(org)) * LIGHT_RES
		info.fill_rect(Rect2i(o, Vector2i(LIGHT_RES, LIGHT_RES)), Color(float(grid.light_at(c)) * 0.5, 0, float(grid.base_light(c)) * 0.5))
	# 광원 빛: 광원 반지름 안 화소만, 광원에서 시야선이 닿는 칸만
	var glow := Image.create(iw, ih, false, Image.FORMAT_RGB8)
	var acc := PackedColorArray()
	acc.resize(iw * ih)
	for src: Dictionary in grid.light_sources:
		var sc: Vector2i = grid.cell_of(src["creature"]) if src.get("creature") != null and is_instance_valid(src["creature"]) else src.get("cell", Vector2i(-99, -99))
		if not grid.in_bounds(sc):
			continue
		var r := float(int(src.get("bright", 0))) + float(int(src.get("dim", 0))) * 0.7 + 0.5
		var boost := 1.0 + float(int(src.get("bright", 0))) / maxf(r, 0.5) * 0.3
		var col := _light_color(String(src.get("id", "")))
		var cen := Vector2(sc) + Vector2(0.5, 0.5)
		var seen := {}
		var lo := ((cen - Vector2(r, r) - org) * LIGHT_RES).floor()
		var hi := ((cen + Vector2(r, r) - org) * LIGHT_RES).ceil()
		for py in range(maxi(0, int(lo.y)), mini(ih, int(hi.y))):
			for px in range(maxi(0, int(lo.x)), mini(iw, int(hi.x))):
				var pt := org + (Vector2(px, py) + Vector2(0.5, 0.5)) / LIGHT_RES
				var d := pt.distance_to(cen) / r
				if d >= 1.0:
					continue
				var c := Vector2i(floori(pt.x), floori(pt.y))
				if grid.in_bounds(c):
					if not seen.has(c):
						seen[c] = grid.has_line_of_sight(sc, c, true)
					if not seen[c]:
						continue
				var k := pow(1.0 - d, 1.6) * boost
				var i := py * iw + px
				var g := acc[i]
				acc[i] = Color(minf(1.0, g.r + col.r * k), minf(1.0, g.g + col.g * k), minf(1.0, g.b + col.b * k))
	for i in acc.size():
		if acc[i].r + acc[i].g + acc[i].b > 0.0:
			glow.set_pixel(i % iw, i / iw, acc[i])
	# 드리운 그림자: 높이(벽 포함)가 바뀔 때만
	var hkey := _make_height_key() + str(_ruin)
	if hkey != _shadow_key or _shadow_tex == null:
		_shadow_key = hkey
		_shadow_tex = ImageTexture.create_from_image(_build_shadows(org, iw, ih))
	lighting = {"glow": ImageTexture.create_from_image(glow), "info": ImageTexture.create_from_image(info), "shadow": _shadow_tex, "origin": org, "size": Vector2(cells)}
	lighting_version += 1
	# 물 그림 층(그림자·빛 반짝임)도 같은 빛 지도를 본다
	var om: ShaderMaterial = _mats.get("floors_overlay")
	if om != null:
		om.set_shader_parameter("light_on", true)
		om.set_shader_parameter("glow_tex", lighting["glow"])
		om.set_shader_parameter("linfo_tex", lighting["info"])
		om.set_shader_parameter("shadow_tex", _shadow_tex)
		om.set_shader_parameter("l_origin", org)
		om.set_shader_parameter("l_size", Vector2(cells))


var _shadow_key := ""
var _shadow_tex: Texture2D


## 드리운 그림자 그림(L8, 1 없음 → 0 짙음): 맵 안 바닥 화소마다 북서쪽으로 거슬러 가며 해를 가리는 더 높은 칸(벽 윗면·높은 땅)
func _build_shadows(org: Vector2, iw: int, ih: int) -> Image:
	var img := Image.create(iw, ih, false, Image.FORMAT_L8)
	img.fill(Color(1, 1, 1))
	var dir := Vector2(-0.7071, -0.7071)
	for c: Vector2i in grid.all_cells():
		if grid.has_flag(c, "wall"):
			continue
		var h := float(grid.height(c))
		# 북서쪽 4칸 안에 더 높은 칸이 없으면 건너뛴다
		var any := false
		for dy in range(-4, 1):
			for dx in range(-4, 1):
				var q := c + Vector2i(dx, dy)
				if grid.in_bounds(q) and not _veil.has(q) and (_vis_top(q) if grid.has_flag(q, "wall") else float(grid.height(q))) > h + 0.2:
					any = true
		if not any:
			continue
		for sy in LIGHT_RES:
			for sx in LIGHT_RES:
				var pt := Vector2(c) + (Vector2(sx, sy) + Vector2(0.5, 0.5)) / LIGHT_RES
				var sh := 1.0
				var s2 := 0.25
				while s2 <= 4.0:
					var q := pt + dir * s2
					var qc := Vector2i(floori(q.x), floori(q.y))
					if grid.in_bounds(qc) and not _veil.has(qc):
						var top := _vis_top(qc) if grid.has_flag(qc, "wall") else float(grid.height(qc))
						if top - h > s2 * SUN_TAN:
							sh = 0.0 if top - h > s2 * SUN_TAN + 0.35 else 0.5
							break
					s2 += 0.25
				if sh < 1.0:
					var p := (c - Vector2i(org)) * LIGHT_RES + Vector2i(sx, sy)
					img.set_pixel(p.x, p.y, Color(sh, sh, sh))
	return img


## 수관 그늘: 나무(키트 id tree_*)마다 수관 크기 둥근 그늘을 칸당 CANOPY_RES 화소 그림에 모아 바닥 셰이더(맵·둘레)에 준다.
## 그늘 가운데 = 줄기에서 햇빛 반대쪽(남동)으로 조금. 크기 = 그림 폭.
const CANOPY_RES := 4
const CANOPY_SHIFT := Vector2(0.25, 0.2)
var _surround_mat: ShaderMaterial


func _build_canopy() -> void:
	var trees: Array[Node3D] = []
	for n: Node3D in _prop_cells:
		if String(n.get_meta("kit_id", "")).begins_with("tree"):
			trees.append(n)
	for n: Node3D in _tall_props:
		if is_instance_valid(n) and String(n.get_meta("kit_id", "")).begins_with("tree") and not trees.has(n):
			trees.append(n)
	if trees.is_empty():
		return
	var w := SURROUND_W
	var org := Vector2(-w, -w)
	var cells := Vector2i(grid.size.x + 2 * w, grid.size.y + 2 * w)
	var img := Image.create(cells.x * CANOPY_RES, cells.y * CANOPY_RES, false, Image.FORMAT_R8)
	var acc := PackedFloat32Array()
	acc.resize(img.get_width() * img.get_height())
	for n in trees:
		var sp: Variant = n.get_meta("sprite", null)
		var wpx := 160.0
		if sp is Sprite3D and (sp as Sprite3D).texture != null:
			wpx = (sp as Sprite3D).texture.get_size().x
		var r := clampf(wpx / V.T * 0.5 * n.scale.x, 0.8, 2.4)
		var cen := Vector2(n.position.x, n.position.z) + CANOPY_SHIFT
		var lo := ((cen - Vector2(r, r) - org) * CANOPY_RES).floor()
		var hi := ((cen + Vector2(r, r) - org) * CANOPY_RES).ceil()
		for py in range(maxi(0, int(lo.y)), mini(img.get_height(), int(hi.y))):
			for px in range(maxi(0, int(lo.x)), mini(img.get_width(), int(hi.x))):
				var pt := org + (Vector2(px, py) + Vector2(0.5, 0.5)) / CANOPY_RES
				var d := pt.distance_to(cen) / r
				if d < 1.0:
					var i := py * img.get_width() + px
					acc[i] = maxf(acc[i], 1.0 - smoothstep(0.55, 1.0, d))
	for py in img.get_height():
		for px in img.get_width():
			var v := acc[py * img.get_width() + px]
			if v > 0.0:
				img.set_pixel(px, py, Color(v, 0, 0))
	var tex := ImageTexture.create_from_image(img)
	for m: Variant in [_mats.get("floors"), _surround_mat, _mats.get("floors_overlay")]:
		if m is ShaderMaterial:
			(m as ShaderMaterial).set_shader_parameter("canopy_on", true)
			(m as ShaderMaterial).set_shader_parameter("canopy", tex)
			(m as ShaderMaterial).set_shader_parameter("canopy_origin", org)
			(m as ShaderMaterial).set_shader_parameter("canopy_size", Vector2(cells))


## 폐허 벽 윗면 블록: 칸을 앞뒤 2줄로 나누고 줄마다 2~3개 돌(나눔 자리·높이 칸마다 다르게). 돌마다 윗면 + 남쪽 앞면(카메라에 보이는 면),
## 돌 사이·빠진 자리는 어두운 줄눈 바닥. 이끼는 칸을 넘는 얼룩 + 가끔. 재질은 세계 좌표로 입혀(돌·이끼 잔무늬) 반복이 드러나지 않는다.
func _ruin_cap(mb: MeshBuilder, c: Vector2i, top: float, k: float) -> void:
	var t := float(V.T)
	var size := Vector2(2.0 * t, t)
	var x0 := float(c.x)
	var z0 := float(c.y)
	var mortar := Color(CAP_SHADE[2] * k, CAP_SHADE[2] * k, CAP_SHADE[2] * k)
	mb.quad(_flat_quad(x0, z0, top), Rect2(0, 0, t, t), size, [mortar, mortar, mortar, mortar])
	var g := 1.0 / 32.0  # 줄눈 1도트
	var zs := [0.0, 0.4 + _rand(c, Vector2i(0, 1), 401) * 0.2, 1.0]
	for row in 2:
		var cols := 2 + int(_rand(c, Vector2i(row, 2), 409) * 1.99)
		var xs := [0.0]
		for i in range(1, cols):
			xs.append((float(i) + (_rand(c, Vector2i(row, 10 + i), 419) - 0.5) * 0.5) / cols)
		xs.append(1.0)
		for i in cols:
			var key := Vector2i(row, 20 + i)
			if _rand(c, key, 421) < CAP_MISSING:
				continue
			var bx0: float = x0 + float(xs[i]) + (g * 0.5 if i > 0 else 0.0)
			var bx1: float = x0 + float(xs[i + 1]) - (g * 0.5 if i < cols - 1 else g)
			var bz0: float = z0 + float(zs[row]) + (g * 0.5 if row > 0 else 0.0)
			var bz1: float = z0 + float(zs[row + 1]) - (g * 0.5 if row == 0 else g)
			var h := top + lerpf(CAP_H.x, CAP_H.y, _rand(c, key, 431))
			var moss := _patch(Vector2(bx0, bz0) * 0.9 + Vector2(31, 17)) > 1.85 or _rand(c, key, 433) < CAP_MOSS
			var u0 := t if moss else 0.0
			var lit := float(CAP_SHADE[0]) * k * (0.92 + 0.16 * _rand(c, key, 439))
			var tc := Color(lit, lit, lit)
			var src := Rect2(u0 + fposmod(bx0, 1.0) * t, fposmod(bz0, 1.0) * t, (bx1 - bx0) * t, (bz1 - bz0) * t)
			mb.quad([Vector3(bx0, h, bz0), Vector3(bx1, h, bz0), Vector3(bx1, h, bz1), Vector3(bx0, h, bz1)], src, size, [tc, tc, tc, tc])
			var fk := float(CAP_SHADE[1]) * k * (1.1 if moss else 1.0)
			var fc := Color(fk, fk, fk)
			var fsrc := Rect2(u0 + fposmod(bx0, 1.0) * t, 0.0, (bx1 - bx0) * t, (h - top) * V.STEP_PX)
			mb.quad([Vector3(bx0, h, bz1), Vector3(bx1, h, bz1), Vector3(bx1, top, bz1), Vector3(bx0, top, bz1)], fsrc, size, [tc.lerp(fc, 0.3), tc.lerp(fc, 0.3), fc, fc])


## 폐허 벽 높이(그림만 — 규칙은 벽 칸 그대로). 방 남쪽 낮은 벽·벽 아닌 칸은 원래 높이.
func _vis_top(c: Vector2i) -> float:
	if not _ruin or not grid.in_bounds(c) or not grid.has_flag(c, "wall") or V.is_low_wall(grid, c):
		return V.cell_top(grid, c)
	return V.wall_base(grid, c) + V.WALL_H * _ruin_f(c)


## 폐허 벽 높이 배율: 3칸 크기로 이어지는 값 잡음 + 가끔 무너진 홈
func _ruin_f(c: Vector2i) -> float:
	var n := (_patch(Vector2(c) * 1.4 + Vector2(13, 7)) - 0.15) / 1.85
	var f := lerpf(RUIN_H.x, RUIN_H.y, clampf(n, 0.0, 1.0))
	if _rand(c, Vector2i(5, 9), 211) < float(RUIN_NOTCH[0]):
		f *= float(RUIN_NOTCH[1])
	return maxf(f, 0.3)


## 폐허 벽 장식: 남쪽이 열린 벽면에 덩굴·이끼·뿌리, 밑동에 잔해·풀 덤불, 윗면에 풀 덤불
## mul: 밀도 배율, wild: 밑동·윗면 풀(폐허는 켬, 실내·동굴은 끔)
func _build_ruin_decor(mul: float = 1.0, wild: bool = true) -> void:
	var dk: RefCounted = DungeonKit.open(DECOR_KIT) if wild else RefCounted.new()
	for c: Vector2i in grid.all_cells():
		if not grid.has_flag(c, "wall") or _veil.has(c):
			continue
		var south := c + Vector2i.DOWN
		var open_south: bool = grid.in_bounds(south) and not grid.has_flag(south, "wall")
		var low: bool = V.is_low_wall(grid, c)
		var top := _vis_top(c)
		var base := V.wall_base(grid, c)
		var tint := V.light_tint(grid, south if open_south else c)
		if open_south and not low:
			if _rand(c, Vector2i(1, 0), 223) < float(RUIN_DECOR["face"]) * mul and top - base > 1.6:
				var id := _pick_weighted(RUIN_FACE_ART, _rand(c, Vector2i(2, 0), 227))
				var vs: PackedStringArray = kit.variants(id)
				if not vs.is_empty():
					var n := _add_prop(id, vs[int(_rand(c, Vector2i(3, 0), 229) * vs.size()) % vs.size()], _prop_pos(c, (_rand(c, Vector2i(4, 0), 233) - 0.5) * 30.0, 0.0), c, {"flip": _rand(c, Vector2i(5, 0), 239) < 0.5})
					Kit3D.tint(n, tint)
			if _rand(c, Vector2i(6, 0), 241) < float(RUIN_DECOR["rubble"]) * mul:
				var rv: PackedStringArray = kit.variants("rubble")
				var pt := Vector2(c.x + 0.2 + _rand(c, Vector2i(7, 0), 251) * 0.6, c.y + 1.12)
				var rn := _add_prop("rubble", rv[int(_rand(c, Vector2i(8, 0), 257) * rv.size()) % rv.size()], Vector3(pt.x, float(grid.height(south)), pt.y), c, {"flip": _rand(c, Vector2i(9, 0), 263) < 0.5})
				Kit3D.tint(rn, tint)
		if not wild or dk.data.is_empty():
			continue
		var tv: PackedStringArray = dk.variants("tuft")
		if open_south and _rand(c, Vector2i(10, 0), 269) < float(RUIN_DECOR["foot_tuft"]):
			for j in 1 + int(_rand(c, Vector2i(11, 0), 271) * 2.5):
				var q := Vector2(c.x + _rand(c, Vector2i(12, j), 277), c.y + 1.06 + _rand(c, Vector2i(13, j), 281) * 0.12)
				var tn: Node3D = Kit3D.make(dk, "tuft", tv[int(_rand(c, Vector2i(14, j), 283) * tv.size()) % tv.size()], {"flip": _rand(c, Vector2i(15, j), 293) < 0.5})
				tn.position = Vector3(q.x, float(grid.height(south)), q.y)
				Kit3D.tint(tn, tint)
				sorted.add_child(tn)
		if _rand(c, Vector2i(16, 0), 307) < float(RUIN_DECOR["top_tuft"]):
			var q2 := Vector2(c.x + 0.15 + _rand(c, Vector2i(17, 0), 311) * 0.7, c.y + 0.2 + _rand(c, Vector2i(18, 0), 313) * 0.6)
			var tn2: Node3D = Kit3D.make(dk, "tuft", tv[int(_rand(c, Vector2i(19, 0), 317) * tv.size()) % tv.size()], {"flip": _rand(c, Vector2i(20, 0), 331) < 0.5})
			tn2.position = Vector3(q2.x, top + CAP_H.y * 0.5, q2.y)
			Kit3D.tint(tn2, V.light_tint(grid, c) if not open_south else tint)
			sorted.add_child(tn2)


## 맵 밖 점의 바닥 높이: 가장 가까운 놀이 영역 점(자연 지형은 그려진 바닥, 벽 칸은 벽이 서는 바닥)
func _edge_height(pt: Vector2) -> float:
	var q := Vector2(clampf(pt.x, _play.position.x + 0.02, _play.end.x - 0.02), clampf(pt.y, _play.position.y + 0.02, _play.end.y - 0.02))
	if natural != null:
		return ground_at(q)
	var c := Vector2i(floori(q.x), floori(q.y))
	return V.wall_base(grid, c) if grid.has_flag(c, "wall") else float(grid.height(c))


## 놀이 영역 경계에서 바깥으로의 거리(칸)
static func _out_dist(pt: Vector2, play: Rect2) -> float:
	var dx := maxf(maxf(play.position.x - pt.x, pt.x - play.end.x), 0.0)
	var dy := maxf(maxf(play.position.y - pt.y, pt.y - play.end.y), 0.0)
	return sqrt(dx * dx + dy * dy)


## 둘레 밝기: 가까운 곳은 그대로, 둘레 끝 쪽(마지막 6칸)만 0.55까지 살짝 어둡게(먼 숲·바위의 깊이감)
## 맵 기본 빛(밝음·어스름·어둠)의 밝기 — 맵 밖 둘레도 맵 안과 같이 어둡게
func _amb_k() -> float:
	var lv: int = {"dark": 0, "dim": 1}.get(String(map.get("light", "bright")), 2)
	return 1.0 - float(V.DARK_ALPHA[lv]) * 0.72  # 맵 안 어둠보다 조금 밝게(돌기둥 윤곽이 보이게)


static func _surround_fade(pt: Vector2, play: Rect2, w: int) -> float:
	return 1.0 - 0.45 * smoothstep(float(w) - 6.0, float(w), _out_dist(pt, play))


## 흩뿌림 밀도 얼룩(칸 평면 점 → 0.15~2.0): 3칸 격자 값 잡음
func _patch(p: Vector2) -> float:
	var q := p / 3.0
	var i := Vector2i(floori(q.x), floori(q.y))
	var f := q - Vector2(i)
	f = f * f * (Vector2(3, 3) - 2.0 * f)
	var a := _rand(i, Vector2i(7, 7), 101)
	var b := _rand(i + Vector2i(1, 0), Vector2i(7, 7), 101)
	var c := _rand(i + Vector2i(0, 1), Vector2i(7, 7), 101)
	var d := _rand(i + Vector2i(1, 1), Vector2i(7, 7), 101)
	var n := lerpf(lerpf(a, b, f.x), lerpf(c, d, f.x), f.y)
	return lerpf(0.15, 2.0, smoothstep(0.25, 0.75, n))


static func _pick_row(rows: Array, r: float) -> Array:
	var total := 0.0
	for e: Array in rows:
		total += float(e[1])
	var acc := 0.0
	for e: Array in rows:
		acc += float(e[1]) / total
		if r < acc:
			return e
	return rows[-1]


static func _pick_weighted(rows: Array, r: float) -> String:
	var total := 0.0
	for e: Array in rows:
		total += float(e[1])
	var acc := 0.0
	for e: Array in rows:
		acc += float(e[1]) / total
		if r < acc:
			return String(e[0])
	return String(rows[-1][0])


func _rand(c: Vector2i, d: Vector2i, salt: int) -> float:
	return float(posmod(hash([c, d, salt]), 10007)) / 10007.0


## 바닥 높이(칸 평면 점). 자연 지형은 언덕 면, 블록 지형은 칸 윗면.
func ground_at(p: Vector2) -> float:
	if natural != null:
		return natural.ground_at(p)
	var c := Vector2i(floori(p.x), floori(p.y))
	return V.cell_top(grid, c) if grid.in_bounds(c) else 0.0


## 소품 발 위치. 옛 2D 배치(칸 가운데 + 아래로 0.3칸 + dx·dy px)를 바닥 위 위치로 옮긴다.
## 벽 칸의 소품(횃불·이끼·거미줄 등)은 벽 남쪽 면 바로 앞에 붙인다(dy px만큼 화면 위아래).
func _prop_pos(cell: Vector2i, dx: float, dy: float) -> Vector3:
	var x := cell.x + 0.5 + dx / V.T
	if grid.in_bounds(cell) and grid.has_flag(cell, "wall"):
		var south := cell + Vector2i.DOWN
		var base: float = maxf(V.wall_base(grid, cell), float(grid.height(south)) if grid.in_bounds(south) and not grid.has_flag(south, "wall") else 0.0)
		# 옛 2D: 발이 벽면 아래 끝에서 (0.2칸 − dy)px 위
		return Vector3(x, base + maxf(0.0, (V.T * 0.2 - dy) / V.STEP_PX), cell.y + 1.02)
	var z := cell.y + 0.8 + dy / V.T
	return Vector3(x, ground_at(Vector2(x, z)) if natural != null else (float(grid.height(cell)) if grid.in_bounds(cell) else 0.0), z)


## 칸 데이터가 바뀌면(표면·재질·빛) 다시 그린다.
func refresh() -> void:
	var key := _make_terrain_key()
	if key != _terrain_key:
		_terrain_key = key
		_build_terrain()
		if art_dots > 0.0:
			_build_lighting()
	_refresh_surfaces()
	for n: Node3D in _prop_cells:
		if is_instance_valid(n):
			Kit3D.tint(n, V.light_tint(grid, _prop_cells[n]))


func _make_height_key() -> String:
	var parts := PackedStringArray()
	for c: Vector2i in grid.all_cells():
		parts.append(str(grid.height(c)))
	return ",".join(parts)


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
	var rtops := MeshBuilder.new()
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
	if natural != null and _make_height_key() != _height_key:
		natural = TerrainNatural.new(grid)  # 높이가 바뀌었다(빛만 바뀌면 그물을 다시 만들지 않는다)
		_height_key = _make_height_key()
	for c: Vector2i in grid.all_cells():
		var x0 := float(c.x)
		var z0 := float(c.y)
		var top_c: float = _vis_top(c)
		var south := c + Vector2i.DOWN
		var has_south: bool = grid.in_bounds(south)
		var top_s: float = _vis_top(south) if has_south else top_c
		# 남쪽 면 밝기: 남쪽이 열린 바닥이면 그 칸(면이 보는 쪽), 아니면 자기 칸
		var k := 1.0 - float(dark.get(south, dark[c]) if has_south and not grid.has_flag(south, "wall") else dark[c])
		if _veil.has(c):
			continue
		if grid.has_flag(c, "wall"):
			var mask := 0
			for bit: Array in [[1, Vector2i.UP], [2, Vector2i.RIGHT], [4, Vector2i.DOWN], [8, Vector2i.LEFT]]:
				var n: Vector2i = c + (bit[1] as Vector2i)
				if not grid.in_bounds(n) or grid.has_flag(n, "wall"):
					mask |= int(bit[0])
			var tsrc := Rect2(float(top_frame[0]) + (mask % 4) * t, float(top_frame[1]) + (mask / 4) * t, t, t)
			if _ruin and not _veil.has(c):
				_ruin_cap(rtops, c, top_c, 1.0 - float(dark[c]))
			else:
				tops.quad(_flat_quad(x0, z0, top_c), tsrc, tsize, _corner_cols(dark, c, Color(TOP_SHADE, TOP_SHADE, TOP_SHADE)))
			if has_south and top_s < top_c:
				var base: float = V.wall_base(grid, c)
				var y0 := maxf(top_s, base)
				var state: String = ["clean", "cracked", "mossy", "damaged"][posmod(c.x * 7 + c.y * 13, 4)]
				var ff: Array = face_info.get("variants", {}).get(state, {"frames": [face_frame]})["frames"][0]
				var px := minf((top_c - y0) * V.STEP_PX, float(ff[3]))
				var src := Rect2(float(ff[0]) + posmod(c.x, 4) * t, float(ff[1]) + float(ff[3]) - px, t, px)
				_face(faces, x0, z0 + 1.0, y0, top_c, src, wsize, FACE_SHADE, k, not grid.has_flag(south, "wall"))
				if natural != null and not grid.has_flag(south, "wall"):
					# 언덕 바닥이 벽 앞에서 기울어도 틈이 없게 벽면을 땅속으로 한 단계 더
					_cliff(faces, cliff_frame, wsize, x0, z0 + 1.0, y0 - 1.0, y0, k, false)
				if top_s < base:
					_cliff(faces, cliff_frame, wsize, x0, z0 + 1.0, top_s, base, k, false)
		elif natural == null:
			var fsrc := _floor_src(c, "a")
			if fsrc.size.x > 0.0:
				# 변형 a·b가 모두 있을 때만 섞는다(하나뿐이면 같은 조각 — 섞임 없음)
				var vs: PackedStringArray = kit.variants(_floor_id(c))
				var fsrc2 := _floor_src(c, "b", Vector2i(2, 2)) if vs.has("a") and vs.has("b") else fsrc
				floors.quad(_flat_quad(x0, z0, top_c), fsrc, fsize, _corner_cols(dark, c, Color.WHITE), fsrc2)
			if has_south and top_s < top_c:
				_cliff(faces, cliff_frame, wsize, x0, z0 + 1.0, top_s, top_c, k, not grid.has_flag(south, "wall"))
			_rims(rims, c, top_c, 1.0 - float(dark[c]))
	if natural != null:
		_rim_mi.mesh = ArrayMesh.new()  # 둥근 턱·음영이 테두리를 대신한다
		_floor_mi.mesh = natural.build_floor(func(p: Vector2) -> float: return _dark_point(dark, p))
	else:
		_rim_mi.mesh = rims.mesh()
		_floor_mi.mesh = floors.mesh()
	_build_cell_textures()
	_top_mi.mesh = tops.mesh()
	if _ruin:
		if _ruin_top_mi == null:
			var rm: ShaderMaterial = (_mats["wall_tops"] as ShaderMaterial).duplicate()
			rm.set_shader_parameter("tex", load(RUIN_TOP_TEX))
			_mats["ruin_tops"] = rm
			_ruin_top_mi = MeshInstance3D.new()
			_ruin_top_mi.material_override = rm
			_ruin_top_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(_ruin_top_mi)
		_ruin_top_mi.mesh = rtops.mesh()
	_face_mi.mesh = faces.mesh()


## 점의 어둠: 칸 모서리 값(둘레 네 칸 평균)을 쌍선형으로
func _dark_point(dark: Dictionary, p: Vector2) -> float:
	var q := Vector2i(floori(p.x), floori(p.y))
	var u := p.x - q.x
	var v := p.y - q.y
	var d00 := _corner_dark(dark, q, Vector2i(0, 0))
	var d10 := _corner_dark(dark, q, Vector2i(1, 0))
	var d01 := _corner_dark(dark, q, Vector2i(0, 1))
	var d11 := _corner_dark(dark, q, Vector2i(1, 1))
	return lerpf(lerpf(d00, d10, u), lerpf(d01, d11, u), v)


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
	# 자연 지형은 언덕(높이 차 1)을 넘어서도 바닥 종류를 섞는다
	fm.set_shader_parameter("blend_dh", 1.0 if natural != null else 0.0)
	fm.set_shader_parameter("shade_gain", 1.0 / TerrainNatural.FLOOR_BASE if natural != null else 1.0)
	fm.set_shader_parameter("dot_px", art_dots)
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
	var refl_hs := {}  # 반사 표면 칸 바닥 높이 → 칸 수
	var refl_cells := {}
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
				if SURFACE_REFLECT.has(sid):
					refl_cells[c] = true
					var gh := snappedf(ground_at(Vector2(c) + Vector2(0.5, 0.5)), 0.25)
					refl_hs[gh] = int(refl_hs.get(gh, 0)) + 1
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
				node.position.y = ground_at(Vector2(node.position.x, node.position.z)) + (0.004 if node.rotation.x != 0.0 else 0.0)
				_lay_on_ground(node)
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
			on.position.y = ground_at(Vector2(on.position.x, on.position.z))
			Kit3D.tint(on, tint)
			sorted.add_child(on)
			_surface_nodes.append(on)
	var dark := {}
	for c: Vector2i in grid.all_cells():
		dark[c] = V.DARK_ALPHA[grid.light_at(c)]
	for c: Vector2i in water_cells:
		# 어둠은 바닥과 같게 모서리마다 이웃 평균(칸 경계에 어두운 네모가 생기지 않게)
		if natural == null:
			water.quad(_flat_quad(c.x, c.y, float(grid.height(c)) + V.LIFT), Rect2(0, 0, 1, 1), fsize, _corner_cols(dark, c, Color.WHITE))
			continue
		# 자연 지형: 4×4 조각으로 언덕 면을 따라 깐다
		const N := 4
		for qz in N:
			for qx in N:
				var ps := []
				var cs := []
				for o: Vector2 in [Vector2(qx, qz), Vector2(qx + 1, qz), Vector2(qx + 1, qz + 1), Vector2(qx, qz + 1)]:
					var pt := Vector2(c) + o / N
					ps.append(Vector3(pt.x, ground_at(pt) + V.LIFT * 2.0, pt.y))
					var k := 1.0 - _dark_point(dark, pt)
					cs.append(Color(k, k, k))
				water.quad(ps, Rect2(0, 0, 1, 1), fsize, cs)
	_water_mi.mesh = water.mesh()
	_surf_tex = ImageTexture.create_from_image(surf)
	var tints := PackedVector4Array()
	for i in 8:
		var tc: Color = SURFACE_TINT.get(palette[i], Color(1, 1, 1, 0.92)) if i < palette.size() else Color.WHITE
		tints.append(Vector4(tc.r, tc.g, tc.b, tc.a))
	var om: ShaderMaterial = _mats["floors_overlay"]
	om.set_shader_parameter("surf", _surf_tex)
	om.set_shader_parameter("tints", tints)
	var refl := PackedFloat32Array()
	for i in 8:
		refl.append(float(SURFACE_REFLECT.get(palette[i], 0.0)) if i < palette.size() else 0.0)
	om.set_shader_parameter("reflect", refl)
	var looks := PackedFloat32Array()
	var lcols := PackedVector4Array()
	for i in 8:
		var lk: Array = SURFACE_LOOK.get(palette[i], [0, Color.WHITE, 0]) if i < palette.size() and art_dots > 0.0 else [0, Color.WHITE, 0]
		looks.append(float(lk[0]))
		var lc: Color = lk[1]
		lcols.append(Vector4(lc.r, lc.g, lc.b, float(lk[2])))
	om.set_shader_parameter("look", looks)
	om.set_shader_parameter("look_col", lcols)
	# 숲 맵: 아무것도 안 비친 자리도 둘레 숲이 비친 짙은 청록 얼룩(하늘 대신)
	if not refl_cells.is_empty() and _sky_leafy < 0.0:
		_sky_leafy = 1.0 if String(art().get("surround", {}).get("biome", _surround_biome()) if art().get("surround") is Dictionary else _surround_biome()) == "forest" else 0.0
	om.set_shader_parameter("sky_leafy", maxf(_sky_leafy, 0.0))
	om.set_shader_parameter("dot_px", art_dots)
	var best_h := 0.0
	var best_n := 0
	for gh: float in refl_hs:
		if int(refl_hs[gh]) > best_n:
			best_n = int(refl_hs[gh])
			best_h = gh
	if (best_n > 0) != reflect_on or (best_n > 0 and best_h != reflect_h):
		reflect_on = best_n > 0
		reflect_h = best_h
		reflect_version += 1
	_build_refl_doubles(refl_cells)


## 물 반사 짝: 서 있는 키트 판은 그림 아래쪽 바닥 자국(발 아래 줄)만큼 들려 남쪽으로 밀려 있다(Kit3D.footprint_shift — 화면 위치는 같다).
## 거울은 그 들린 높이만큼 비친 그림을 아래로 떼어 놓으니, 물가 소품마다 발을 바닥에 내린 짝을 거울 카메라 전용 층에 두고
## 원본은 도트 카메라 전용 층으로 옮긴다(규칙 밖 그림만). 반사 칸이 바뀔 때만 다시 만든다.
func _build_refl_doubles(refl_cells: Dictionary) -> void:
	var on := reflect_doubles and art_dots > 0 and not refl_cells.is_empty()
	var key := str(refl_cells.keys()) if on else ""
	if key == _refl_key:
		return
	_refl_key = key
	for n in _refl_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_refl_nodes.clear()
	for n: Node in sorted.get_children():
		var sp := n.get_node_or_null("Sprite") as SpriteBase3D
		if sp == null or not sp.has_meta("foot_lift"):
			continue
		if sp.layers == PixelView.MAIN_ONLY_LAYER:
			sp.layers = 1
		if not on or not (n is Node3D) or n.has_meta("refl_double"):
			continue
		var p: Vector3 = (n as Node3D).position
		var near := false
		for dz in range(0, REFL_REACH + 1):
			for dx in range(-3, 4):
				if refl_cells.has(Vector2i(int(floor(p.x)) + dx, int(floor(p.z)) + dz)):
					near = true
					break
			if near:
				break
		var lift: Vector3 = sp.get_meta("foot_lift")
		if not near or lift.is_zero_approx():
			continue
		var d := n.duplicate() as Node3D
		d.set_meta("refl_double", true)
		var dsp := d.get_node("Sprite") as SpriteBase3D
		dsp.position -= lift
		dsp.layers = PixelView.REFL_LAYER
		if dsp is AnimatedSprite3D:
			(dsp as AnimatedSprite3D).play((sp as AnimatedSprite3D).animation)
		sp.layers = PixelView.MAIN_ONLY_LAYER
		sorted.add_child(d)
		_refl_nodes.append(d)


## 캐릭터를 가리는 앞쪽 벽·절벽은 셰이더가 비춘다(발 위치·크기 배율 목록). 큰 소품은 반투명.
## actors: [[발 위치 Vector3, 크기 배율 float], ...]
func update_occlusion(actors: Array) -> void:
	var arr := PackedVector4Array()
	for a: Array in actors.slice(0, 24):
		var p: Vector3 = a[0]
		arr.append(Vector4(p.x, p.y, p.z, float(a[1])))
	var count := arr.size()
	arr.resize(24)
	for key: String in ["wall_tops", "wall_faces", "floors", "ruin_tops"]:
		if not _mats.has(key):
			continue
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
