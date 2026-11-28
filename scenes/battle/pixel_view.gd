class_name PixelView
extends Node
## 도트 화면(표현 계층만): 3D 세계를 작은 SubViewport에 그린 뒤 가장 가까운 점으로 확대해 띄운다.
## - 저해상도: 화면(캔버스 단위)의 1/scale_px 크기 격자. 에셋 그림을 바꾸지 않고 화면 전체를 도트처럼 보이게 한다.
##   ss(초표본)배 크게 그린 뒤 ss×ss를 평균해 한 도트로(64px 그림을 작게 줄일 때 점이 튀지 않게).
## - 카메라 픽셀 맞춤: 도트 카메라를 저해상도 1칸 단위로 맞춰 움직이고, 남은 끝수만큼 화면 그림을 밀어
##   카메라를 옮겨도 바닥·벽 도트가 떨리지 않는다(직교·회전 없음이라 오른쪽·위 두 축만 맞추면 된다).
## - 외곽선: 깊이 차이로 1도트 선(pixel_outline.gdshader — 서 있는 판은 불투명 사전 패스라 깊이를 쓴다).
## - 색 줄이기·Bayer 디더링: pixel_post.gdshader. 팔레트 assets/pixel/palette.png(가로 1줄, 최대 128색)는 게임 화면·에셋에서
##   뽑은 색(k-평균) + 어두운 회색 단계 + 강조 색상환(주문·표시용)으로 만들었다. 디더 무늬는 세계에 붙어 미끄러지지 않는다.
## 원래 카메라(battle_scene.camera)는 그대로 두고 광선 고르기·화면 투영(HP 막대 등)에 쓴다. 본 화면의 3D 그리기만 끈다.
## UI(CanvasLayer)는 원래 해상도 그대로.

const OUTLINE_LAYER := 1 << 19  # 외곽선 판의 그림 층(도트 카메라만 본다)
const REFL_LAYER := 1 << 18  # 거울 카메라만 보는 그림 층(거울 카메라의 빛 판, 물가 소품의 반사 짝)
const WATER_LAYER := 1 << 17  # 물 표면 그물(거울 카메라는 보지 않는다 — map_view)
const MAIN_ONLY_LAYER := 1 << 16  # 도트 카메라만 보는 그림(물가 소품 원본 — 거울 카메라는 발을 바닥에 내린 짝을 본다)
const MAIN_MASK := 0xFFFFF & ~REFL_LAYER
const REFL_MASK := 0xFFFFF & ~OUTLINE_LAYER & ~WATER_LAYER & ~MAIN_ONLY_LAYER
const V_T := 64.0  # 확대 1에서 세계 1유닛 = 64px(view3d.T)
const ART_DOT := 1.0 / 32.0  # 그림 1도트 = 세계 1/32유닛(키트 64px 그림의 2×2화소)
const DOTS_PX := 2.0  # 확대 1에서 그림 1도트 = 캔버스 2px
## 도트 화면 확대 단계: 그림 1도트가 화면 정수 칸(1·2·3·4px)이 되게 끊는다(굵고 얇은 도트가 섞이지 않게)
const ZOOM_STEPS := [0.5, 1.0, 1.5, 2.0]


## 연속 확대 → 가장 가까운 단계(로그 거리)
static func snap_zoom(z: float) -> float:
	var best: float = ZOOM_STEPS[0]
	for s: float in ZOOM_STEPS:
		if absf(log(z / s)) < absf(log(z / best)):
			best = s
	return best

## 도트 화면 켜기(0이면 끔). 확대 1에서 그림 1도트 = 캔버스 scale_px(=2)px — 실제 크기는 확대 단계를 따른다(sync).
var scale_px := 2
## 초표본 배수(1 = 저해상도에 바로 그림)
var ss := 1
## 팔레트로 색 줄이기
var palette := false
## 디더 세기(밝기 흔들림 폭, Oklab L)
var dither := 0.06
const PALETTE_PATH := "res://assets/pixel/palette.png"
const PAL_MAX := 128
## 외곽선 켜기
var outline := true
## 화면에 씌우는 빛과 그림자(pixel_light.gdshader — 곱하기 판 + 더하기 판, 빛 지도는 map_view._build_lighting)
var lighting := true
var _light_mats: Array[ShaderMaterial] = []
## 물 반사(거울 카메라): 물 높이 거울 아래에서 올려다본 세계를 그림 도트 해상도로 그려 물 셰이더(overlay.gdshader)가 찾는다.
## 곱하기 빛 판을 거울 카메라에도 붙여 비친 세계에도 빛 색과 그림자가 입혀진다. 반사 표면이 없는 맵은 그리지 않는다.
var reflection := true
var rvp: SubViewport
var rcam: Camera3D
var _refl_on := false
var _refl_h := 0.0
var _water_mats: Array[ShaderMaterial] = []

var source: Camera3D
var vp: SubViewport
var cam: Camera3D
var rect: TextureRect
var layer: CanvasLayer
var _post: ShaderMaterial
var _line: ShaderMaterial
var _lo := Vector2i.ZERO


func setup(main_camera: Camera3D) -> void:
	source = main_camera
	if scale_px <= 0:
		return
	var main_vp := get_viewport()
	vp = SubViewport.new()
	vp.world_3d = main_vp.find_world_3d()
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(vp)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = source.near
	cam.far = source.far
	vp.add_child(cam)
	cam.make_current()
	if outline:
		_add_outline()
	if lighting:
		_add_lighting()
	if reflection:
		_add_reflection()
	cam.cull_mask = MAIN_MASK
	layer = CanvasLayer.new()
	layer.layer = -1  # 세계 그림은 맨 뒤(HP 막대 0층, UI 위층)
	add_child(layer)
	rect = TextureRect.new()
	rect.texture = vp.get_texture()
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post = ShaderMaterial.new()
	_post.shader = preload("res://scenes/battle/pixel_post.gdshader")
	rect.material = _post
	_post.set_shader_parameter("dither", dither)
	if palette:
		_load_palette()
	layer.add_child(rect)
	main_vp.disable_3d = true  # 본 화면은 3D를 다시 그리지 않는다(도트 화면이 대신)
	sync()


## 카메라 자세를 1도트(step 유닛) 격자에 맞춘다: 카메라 오른쪽·위 축 성분만 반올림(앞뒤 깊이는 그대로).
## → {xform: 맞춘 자세, da·db: 옮긴 거리(오른쪽·위, 유닛), ia·ib: 격자 번호}
static func snap(xf: Transform3D, step: float) -> Dictionary:
	var r := xf.basis.x
	var up := xf.basis.y
	var a := xf.origin.dot(r)
	var b := xf.origin.dot(up)
	var ia := roundf(a / step)
	var ib := roundf(b / step)
	var da := ia * step - a
	var db := ib * step - b
	return {"xform": Transform3D(xf.basis, xf.origin + r * da + up * db), "da": da, "db": db, "ia": int(ia), "ib": int(ib)}


## 팔레트 그림(가로 한 줄) → 셰이더 색 배열(sRGB·Oklab)
func _load_palette() -> void:
	var tex: Texture2D = load(PALETTE_PATH)
	if tex == null:
		return
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	var n := mini(img.get_width(), PAL_MAX)
	var rgb := PackedVector3Array()
	var lab := PackedVector3Array()
	for x in n:
		var c := img.get_pixel(x, 0)
		rgb.append(Vector3(c.r, c.g, c.b))
		lab.append(oklab(c))
	rgb.resize(PAL_MAX)
	lab.resize(PAL_MAX)
	_post.set_shader_parameter("pal_rgb", rgb)
	_post.set_shader_parameter("pal_lab", lab)
	_post.set_shader_parameter("pal_count", n)


## sRGB 색 → Oklab(L, a, b). 셰이더의 oklab()과 같은 식.
static func oklab(c: Color) -> Vector3:
	var l := Vector3(_lin(c.r), _lin(c.g), _lin(c.b))
	var m := Vector3(
		l.dot(Vector3(0.4122214708, 0.5363325363, 0.0514459929)),
		l.dot(Vector3(0.2119034982, 0.6806995451, 0.1073969566)),
		l.dot(Vector3(0.0883024619, 0.2817188376, 0.6299787005)))
	m = Vector3(pow(m.x, 1.0 / 3.0), pow(m.y, 1.0 / 3.0), pow(m.z, 1.0 / 3.0))
	return Vector3(
		m.dot(Vector3(0.2104542553, 0.7936177850, -0.0040720468)),
		m.dot(Vector3(1.9779984951, -2.4285922050, 0.4505937099)),
		m.dot(Vector3(0.0259040371, 0.7827717662, -0.8086757660)))


static func _lin(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


## 외곽선 판: 도트 카메라 앞에 붙인 화면 가득 판(정점 셰이더가 화면을 덮는다)
func _add_outline() -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	mi.mesh = q
	_line = ShaderMaterial.new()
	_line.shader = preload("res://scenes/battle/pixel_outline.gdshader")
	_line.render_priority = 127  # 투명 패스 맨 끝
	mi.material_override = _line
	mi.layers = OUTLINE_LAYER
	mi.extra_cull_margin = 16384.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, 0, -2)
	cam.add_child(mi)


## 거울 카메라: 물 높이에 대고 도트 카메라를 뒤집은 자리(아래)에서 위로 올려다본다(회전만 — 그림은 위아래가 뒤집혀 담기고
## 물 셰이더가 거울 위치를 이 카메라 행렬로 찾으니 따로 뒤집지 않는다). 빈 곳은 투명 → 물 셰이더가 하늘 색.
func _add_reflection() -> void:
	rvp = SubViewport.new()
	rvp.world_3d = vp.world_3d
	rvp.transparent_bg = true
	rvp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	rvp.msaa_3d = Viewport.MSAA_DISABLED
	rvp.size = Vector2i(4, 4)
	add_child(rvp)
	rcam = Camera3D.new()
	rcam.projection = Camera3D.PROJECTION_ORTHOGONAL
	rcam.cull_mask = REFL_MASK
	rvp.add_child(rcam)
	rcam.make_current()
	# 곱하기 판만(색 틀기·그림자) — 더하기 판은 알파까지 더해 투명 바탕(하늘 자리)을 메운다. 광원 빛은 물 셰이더의 빛 반짝임 층이 맡는다.
	for i in mini(_light_mats.size(), 1):
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(2, 2)
		mi.mesh = q
		mi.material_override = _light_mats[i]
		mi.layers = REFL_LAYER
		mi.extra_cull_margin = 16384.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(0, 0, -2.1 - i * 0.01)
		rcam.add_child(mi)


## 물 반사 켜기: on(반사 표면 있음)·거울 높이 h·물 셰이더 재질들(map_view의 floors_overlay)
func set_reflection(on: bool, h: float, mats: Array) -> void:
	_refl_on = on and rvp != null
	_refl_h = h
	_water_mats.clear()
	for m: Variant in mats:
		if m is ShaderMaterial:
			_water_mats.append(m)
			(m as ShaderMaterial).set_shader_parameter("refl_on", _refl_on)
			if rvp != null:
				(m as ShaderMaterial).set_shader_parameter("refl_tex", rvp.get_texture())
	if rvp != null:
		rvp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _refl_on else SubViewport.UPDATE_DISABLED


## 도트 카메라 자세를 높이 h 거울에 뒤집은 자세(위치는 거울상, 보는 방향은 위로 — 오른손 좌표 그대로)
static func mirror_xform(xf: Transform3D, h: float) -> Transform3D:
	var x := xf.basis.x
	var z := Vector3(xf.basis.z.x, -xf.basis.z.y, xf.basis.z.z)
	var y := z.cross(x)
	var o := Vector3(xf.origin.x, 2.0 * h - xf.origin.y, xf.origin.z)
	return Transform3D(Basis(x, y, z), o)


## 빛 판 두 장: 곱하기(색 틀기·그림자·가장자리) → 더하기(광원 빛 웅덩이). 외곽선(127)보다 먼저.
func _add_lighting() -> void:
	var sh: Shader = preload("res://scenes/battle/pixel_light.gdshader")
	var add_sh := Shader.new()
	add_sh.code = sh.code.replace("blend_mul", "blend_add")
	for i in 2:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(2, 2)
		mi.mesh = q
		var m := ShaderMaterial.new()
		m.shader = sh if i == 0 else add_sh
		m.set_shader_parameter("mode", i)
		m.render_priority = 125 + i
		mi.material_override = m
		mi.layers = OUTLINE_LAYER
		mi.extra_cull_margin = 16384.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(0, 0, -2.1 - i * 0.01)
		cam.add_child(mi)
		_light_mats.append(m)


## 빛 지도를 넣는다(map_view.lighting — {glow, info, shadow, origin, size}). 빈 사전이면 끈다.
func set_lighting(d: Dictionary) -> void:
	for m in _light_mats:
		m.set_shader_parameter("on", not d.is_empty())
		if not d.is_empty():
			m.set_shader_parameter("glow_tex", d["glow"])
			m.set_shader_parameter("info_tex", d["info"])
			m.set_shader_parameter("shadow_tex", d["shadow"])
			m.set_shader_parameter("l_origin", d["origin"])
			m.set_shader_parameter("l_size", d["size"])


## 원래 카메라를 따라 도트 카메라를 맞춘다(매 프레임).
func sync() -> void:
	if vp == null or source == null:
		return
	var screen := get_viewport().get_visible_rect().size
	var u := source.size / screen.y  # 캔버스 1px = 세계 몇 유닛
	# 그림 1도트(지형 그림 2×2화소 = 세계 1/32유닛) = 화면 2 × 확대 px. 화면 버퍼 1화소 = 그 절반(몬스터 촘촘한 도트용, 최소 캔버스 1px).
	var zoom := 1.0 / (V_T * u)
	var bpx := maxf(zoom, 1.0)  # 버퍼 1화소 = 캔버스 몇 px
	var blk := int(round(DOTS_PX * zoom / bpx))  # 그림 1도트 = 버퍼 몇 화소(1 또는 2)
	blk = maxi(blk, 1)
	var lo := Vector2i(int(ceil(screen.x / bpx)) + 2 * blk, int(ceil(screen.y / bpx)) + 2 * blk)
	lo += Vector2i(posmod(-lo.x, 2 * blk), posmod(-lo.y, 2 * blk))  # 그림 도트 2개 배수: 가운데가 도트 경계에
	if lo != _lo:
		_lo = lo
		vp.size = lo * ss
	var step := ART_DOT  # 카메라는 그림 도트(세계 1/32유닛) 격자에 맞춘다 — 확대와 상관없이 지형 도트가 늘 같은 자리
	var sn := snap(source.transform, step)
	var da: float = sn["da"]
	var db: float = sn["db"]
	var ia: int = sn["ia"]
	var ib: int = sn["ib"]
	cam.transform = sn["xform"]
	cam.size = lo.y * step / blk
	cam.near = source.near
	cam.far = source.far
	var full := Vector2(lo) * bpx
	rect.size = full
	rect.position = screen / 2.0 - full / 2.0 + Vector2(da, -db) / u
	_post.set_shader_parameter("lo_size", Vector2(lo))
	_post.set_shader_parameter("ss", ss)
	# 디더 무늬를 세계에 붙인다: 화면 왼쪽 위 화소의 세계 화소 번호(아래가 +y)
	_post.set_shader_parameter("origin_px", Vector2i(ia * blk - lo.x / 2, -ib * blk - lo.y / 2))
	if _refl_on:
		# 거울 그림은 그림 도트 해상도(버퍼의 1/blk) — 물결로 흔들리니 충분하다
		var rs := Vector2i(maxi(lo.x / blk, 1), maxi(lo.y / blk, 1))
		if rvp.size != rs:
			rvp.size = rs
		rcam.transform = mirror_xform(cam.transform, _refl_h)
		rcam.size = cam.size
		rcam.near = cam.near
		rcam.far = cam.far
		var vpm := Projection(rcam.get_camera_projection()) * Projection(rcam.transform.affine_inverse())
		for m in _water_mats:
			m.set_shader_parameter("refl_mat", vpm)
			m.set_shader_parameter("refl_h", _refl_h)
	if _line != null:
		_line.set_shader_parameter("ss", float(ss * blk))  # 외곽선 두께 = 그림 1도트
		_line.set_shader_parameter("depth_range", cam.far - cam.near)
