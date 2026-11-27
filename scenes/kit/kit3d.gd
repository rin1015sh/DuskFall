extends RefCounted
## 던전 에셋 키트 그림을 3D 공간에 놓는 창구(표현 계층). DungeonKit(dungeon_kit.gd)의 그림 표를 그대로 쓴다.
##   var n := Kit3D.make(kit, "brazier", "lit")   # 발 = 노드 위치. 서 있는 물건은 세운 판, 바닥 무늬(decal)는 눕힌 판.
## 서 있는 판은 세로를 View3D.UPRIGHT배 늘려(부모 노드 scale) 화면 크기가 옛 2D 그림과 같다.
## 노드 안 좌표: 그림 1px = 1/px 유닛(가로·화면 세로 모두).

const V := preload("res://scenes/battle/view3d.gd")
const SWAY_SHADER := preload("res://scenes/kit/sway.gdshader")
## 바람에 흔들리는 그림(키트 id → 판 위 끝 흔들림 도트, 1도트 = 그림 2px). 나무는 살짝, 풀은 크게.
const SWAY := {"tree_broadleaf": 1.6, "tree_pine": 1.2, "tree_thorn": 1.4, "tree_giant": 1.8, "bush": 1.2,
	"grass_tall": 1.6, "flowers": 1.4, "reed_thorn": 1.6, "cattail": 1.8, "weeds": 1.4,
	"tuft": 1.3, }
## 잎 반짝임(sway.gdshader leaf)을 켤 그림
const LEAFY := {"tree_broadleaf": true, "tree_thorn": true, "tree_giant": true, "bush": true}
## 깊이 외곽선을 붙이지 않을 잔장식(깊이를 쓰지 않는 판 — 작은 풀·꽃·돌이 검은 가시처럼 보이지 않게)
const NO_OUTLINE := {"tuft": true, "flowers": true, "pebble": true}
static var _sway_shader_nodepth: Shader
## 바람 켜기(도트 화면이 켜질 때 battle_scene이 정한다)
static var wind := false
static var _sway_mats: Dictionary = {}


## opts: flip(false) · up(벽을 따라 올릴 칸 — 옛 make와 같다) · flat(층과 상관없이 눕힘) · playing(true) · scale(1.0)
##       sway(흔들림 도트 — 없으면 SWAY 표, wind가 꺼져 있으면 흔들지 않음)
static func make(kit: RefCounted, id: String, variant: String = "", opts: Dictionary = {}) -> Node3D:
	var holder := Node3D.new()
	holder.name = id
	var a: Dictionary = kit.info(id)
	if a.is_empty():
		return holder
	var vname: String = kit._variant_name(id, variant)
	var layer := String(a.get("layer", "stand"))
	var flat: bool = bool(opts.get("flat", layer == "decal"))
	holder.set_meta("kit_id", id)
	holder.set_meta("kit_variant", vname)
	holder.set_meta("kit_layer", layer)
	var flip := bool(opts.get("flip", false))
	var ps := 1.0 / float(kit.px)
	var fr: Array = kit._frames(id, vname)
	var sprite: SpriteBase3D
	var w := 0.0
	var h := 0.0
	var o := Vector2.ZERO
	if fr.size() > 1:
		var left := 0.0
		var top := 0.0
		var right := 0.0
		var bottom := 0.0
		for f: Array in fr:
			left = maxf(left, float(f[4]))
			top = maxf(top, float(f[5]))
			right = maxf(right, float(f[2]) - float(f[4]))
			bottom = maxf(bottom, float(f[3]) - float(f[5]))
		var frames := SpriteFrames.new()
		frames.set_animation_speed(&"default", float(kit._variants(id)[vname].get("fps", 8)))
		frames.set_animation_loop(&"default", true)
		for i in fr.size():
			var f: Array = fr[i]
			var t := kit.texture(id, vname, i).duplicate() as AtlasTexture
			t.margin = Rect2(left - float(f[4]), top - float(f[5]), left + right - float(f[2]), top + bottom - float(f[3]))
			frames.add_frame(&"default", t)
		var an := AnimatedSprite3D.new()
		an.sprite_frames = frames
		if bool(opts.get("playing", true)):
			an.play(&"default")
			# 같은 물건이 한꺼번에 일렁이지 않게 시작 프레임을 흩는다
			an.frame = randi() % fr.size()
		sprite = an
		w = left + right
		h = top + bottom
		o = Vector2(left, top)
	elif fr.size() == 1:
		var sp := Sprite3D.new()
		sp.texture = kit.texture(id, vname)
		sprite = sp
		w = float(fr[0][2])
		h = float(fr[0][3])
		o = kit.origin(id, vname)
	else:
		return holder
	setup_sprite(sprite, ps, flat)
	sprite.flip_h = flip
	var no_line := NO_OUTLINE.has(id)
	if no_line and not flat:
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD  # 깊이 미리 쓰기 없이(외곽선이 붙지 않게)
	var sway := float(opts.get("sway", SWAY.get(id, 0.0)))
	if wind and sway > 0.0 and not flat and sprite is Sprite3D:
		_add_sway(sprite as Sprite3D, sway * 2.0 * ps, 1.0 if LEAFY.has(id) else 0.0, no_line)
	# 가운데 정렬한 판을 옮겨 원점(발) 픽셀이 노드 위치에 오게 한다
	var cx := (o.x - w * 0.5) if flip else (w * 0.5 - o.x)
	sprite.position = Vector3(cx, o.y - h * 0.5 + float(opts.get("up", 0.0)) * kit.px, 0.0) * ps
	if not flat:
		sprite.position += footprint_shift(h - o.y) * ps
	sprite.name = "Sprite"
	holder.add_child(sprite)
	holder.set_meta("sprite", sprite)
	var k := float(opts.get("scale", 1.0))
	if flat:
		holder.rotation.x = -PI / 2.0
		holder.scale = Vector3(k, k, k)
	else:
		holder.scale = Vector3(k, k * V.UPRIGHT, k)
	return holder


## 3/4 그림은 발(원점) 아래에도 밑면이 그려져 있다. 세운 판이면 그 부분이 바닥 밑에 묻히므로
## 판을 below px만큼 올리고 같은 화면 거리만큼 남쪽(카메라 쪽)으로 옮긴다 — 화면 위치는 그대로(그림 px 단위로 돌려줌).
static func footprint_shift(below: float) -> Vector3:
	if below <= 0.0:
		return Vector3.ZERO
	return Vector3(0.0, below, below / V.SIN_P)


## 판 공통 설정: 그림자 없음(그림에 그려져 있다), 양면, 서 있는 판은 불투명 부분 깊이 쓰기.
static func setup_sprite(s: SpriteBase3D, pixel_size: float, flat: bool = false) -> void:
	s.pixel_size = pixel_size
	s.centered = true
	s.shaded = false
	s.double_sided = true
	s.texture_filter = V.TEX_FILTER
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED if flat else SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if flat:
		s.render_priority = 1


## 흔들림 재질(그림 시트·세기마다 하나씩 나눠 쓴다). 판의 그림은 시트 좌표 UV 그대로 쓴다.
static func _add_sway(sp: Sprite3D, amp: float, leaf: float = 0.0, no_line: bool = false) -> void:
	var tex: Texture2D = sp.texture
	if tex is AtlasTexture:
		tex = (tex as AtlasTexture).atlas
	if tex == null:
		return
	var key := "%d:%.4f:%.1f:%s" % [tex.get_rid().get_id(), amp, leaf, no_line]
	if not _sway_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = SWAY_SHADER
		if no_line:
			if _sway_shader_nodepth == null:
				_sway_shader_nodepth = Shader.new()
				_sway_shader_nodepth.code = SWAY_SHADER.code.replace("depth_prepass_alpha", "depth_draw_never")
			m.shader = _sway_shader_nodepth
		m.set_shader_parameter("texture_albedo", tex)
		m.set_shader_parameter("amp", amp)
		m.set_shader_parameter("leaf", leaf)
		_sway_mats[key] = m
	sp.material_override = _sway_mats[key]


## 빛 단계 어둠·색 입히기(그림 판에)
static func tint(holder: Node3D, col: Color) -> void:
	var s: Variant = holder.get_meta("sprite", null)
	if s is SpriteBase3D:
		(s as SpriteBase3D).modulate = col
