extends RefCounted
## 도트 효과 시트(assets/pixel_fx — tools/bake_pixelfx.py가 pixelfx(patch-gg, MIT)에서 구움)를 3D 세계에 띄우는 창구.
##   효과 1화소 = 그림 1도트(세계 1/32유닛) × scale. 판은 카메라를 정면으로 보고(직교·회전 없음이라 화면 그대로), angle만큼 화면에서 돈다.
##   깊이 시험 없이 맨 위(render_priority 127 — 빛 판 뒤라 빛을 받지 않고 제 밝기 그대로), 깊이를 쓰지 않아 외곽선도 없다.
## 쓰는 쪽(vfx.gd)이 매 프레임 advance()로 장면을 넘기고, 끝나면 지운다.

const DIR := "res://assets/pixel_fx"
const DOT := 1.0 / 32.0
static var _index: Dictionary = {}
static var _tex: Dictionary = {}


static func index() -> Dictionary:
	if _index.is_empty():
		var f := FileAccess.open(DIR.path_join("index.json"), FileAccess.READ)
		if f != null:
			_index = JSON.parse_string(f.get_as_text())
	return _index


static func has(name: String) -> bool:
	return index().has(name) and ResourceLoader.exists(DIR.path_join(name + ".png"))


## 효과 정보: {fps, loop, frames, size[w,h], pivot[x,y], columns}
static func info(name: String) -> Dictionary:
	return index().get(name, {})


## 효과 판 하나. opts: scale(1), flip(false), angle(화면 각도, 라디안), cam_basis(카메라 자세)
static func make(name: String, opts: Dictionary = {}) -> Sprite3D:
	var m := info(name)
	if m.is_empty():
		return null
	if not _tex.has(name):
		_tex[name] = load(DIR.path_join(name + ".png"))
	var sp := Sprite3D.new()
	sp.texture = _tex[name]
	var cols := int(m["columns"])
	sp.hframes = cols
	sp.vframes = int(ceil(float(m["frames"]) / float(cols)))
	var sz: Array = m["size"]
	var pv: Array = m["pivot"]
	var flip := bool(opts.get("flip", false))
	sp.flip_h = flip
	# 기준점(pivot — 발·발사점)이 노드 자리에 오게: 가운데 정렬 판을 그림 px만큼 민다(위가 +y)
	var px := float(sz[0]) - float(pv[0]) if flip else float(pv[0])
	sp.offset = Vector2(float(sz[0]) * 0.5 - px, float(pv[1]) - float(sz[1]) * 0.5)
	sp.pixel_size = DOT * float(opts.get("scale", 1.0))
	sp.centered = true
	sp.shaded = false
	sp.double_sided = true
	sp.no_depth_test = true
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.render_priority = 127
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var b: Basis = opts.get("cam_basis", Basis.IDENTITY)
	sp.basis = b * Basis(Vector3(0, 0, 1), float(opts.get("angle", 0.0)))
	return sp


## 시간 t초의 장 번호(고리 효과는 돈다, 한 번 효과는 마지막 장에서 멈춤). 끝났으면 -1.
static func frame_at(name: String, t: float) -> int:
	var m := info(name)
	var n := int(m.get("frames", 1))
	var i := int(floor(t * float(m.get("fps", 15))))
	if bool(m.get("loop", false)):
		return posmod(i, n)
	return i if i < n else -1


## 한 번 재생 길이(초)
static func duration(name: String) -> float:
	var m := info(name)
	return float(m.get("frames", 1)) / float(m.get("fps", 15))
