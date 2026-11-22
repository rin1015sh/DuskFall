extends RefCounted
## 화면 공통 스타일(표현 계층). BG3 화면의 '어두운 갈색 바탕 + 청동·금 테두리 + 둥근 장식 틀' 느낌을
## 채도를 낮춘 색과 둥근 모서리로 만든다. 그림 에셋 없이 StyleBoxFlat과 _draw로 그린다.

## 색(채도 낮춤)
const BG := Color(0.075, 0.062, 0.052, 0.94)
const BG_DEEP := Color(0.045, 0.037, 0.032, 0.97)
const BG_SLOT := Color(0.11, 0.095, 0.08, 1.0)
const BRONZE := Color(0.50, 0.39, 0.24)
const BRONZE_DARK := Color(0.30, 0.23, 0.14)
const GOLD := Color(0.78, 0.64, 0.38)
const GOLD_SOFT := Color(0.66, 0.55, 0.36)
const TEXT := Color(0.86, 0.80, 0.68)
const TEXT_DIM := Color(0.60, 0.55, 0.46)
const HP := Color(0.55, 0.16, 0.13)
const HP_ENEMY := Color(0.55, 0.16, 0.13)
const HP_ALLY := Color(0.30, 0.48, 0.27)
const DIVIDER := Color(0.48, 0.12, 0.10)
## 턴 자원(BG3: 행동 초록 원, 보너스 주황 삼각, 반응 보라 마름모, 이동 노랑)
const ACTION := Color(0.36, 0.55, 0.30)
const BONUS := Color(0.72, 0.47, 0.20)
const REACTION := Color(0.50, 0.36, 0.62)
const MOVE := Color(0.72, 0.60, 0.28)
const FREE := Color(0.52, 0.52, 0.50)

const FONT_BODY := "res://assets/fonts/NotoSansKR-Regular.otf"
const FONT_TITLE := "res://assets/fonts/SongMyung-Regular.ttf"

static var _theme: Theme = null


static func cost_color(cost: String) -> Color:
	return {"action": ACTION, "bonus": BONUS, "reaction": REACTION, "free": FREE}.get(cost, FREE)


static func title_font() -> Font:
	return load(FONT_TITLE) if ResourceLoader.exists(FONT_TITLE) else ThemeDB.fallback_font


## 둥근 판(창·막대 바탕). radius가 크면 BG3처럼 둥근 틀.
static func panel(radius: int = 14, border: Color = BRONZE, bg: Color = BG, width: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(10)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 6
	sb.anti_aliasing = true
	return sb


## 아이콘 칸: 어두운 바탕, 가는 청동 테두리, 살짝 둥근 모서리.
static func slot(border: Color = BRONZE_DARK, selected: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_SLOT
	sb.border_color = GOLD if selected else border
	sb.set_border_width_all(2 if selected else 1)
	sb.set_corner_radius_all(5)
	sb.anti_aliasing = true
	if selected:
		sb.shadow_color = Color(GOLD, 0.45)
		sb.shadow_size = 4
	return sb


## 알약 모양 탭·버튼
static func pill(active: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.20, 0.15, 0.11) if active else Color(0.10, 0.085, 0.07)
	sb.border_color = GOLD_SOFT if active else BRONZE_DARK
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	sb.anti_aliasing = true
	return sb


static func bar_fill(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(3)
	return sb


static func bar_bg() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.04, 0.035)
	sb.border_color = BRONZE_DARK
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	return sb


## 진행 막대(HP·이동·무게) 하나 만들기
static func bar(color: Color, size: Vector2) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = size
	b.show_percentage = false
	b.add_theme_stylebox_override("fill", bar_fill(color))
	b.add_theme_stylebox_override("background", bar_bg())
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


static func title(text: String, size: int = 18) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", title_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", GOLD)
	return l


## 화면 전체에 쓰는 테마: 글꼴·글자색·버튼·툴팁·스크롤 막대.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	if ResourceLoader.exists(FONT_BODY):
		t.default_font = load(FONT_BODY)
	t.default_font_size = 14
	for cls: String in ["Label", "Button", "CheckBox", "RichTextLabel"]:
		t.set_color("font_color", cls, TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 0.93, 0.78))
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", TEXT_DIM)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_stylebox("normal", "Button", pill(false))
	t.set_stylebox("hover", "Button", pill(true))
	t.set_stylebox("pressed", "Button", pill(true))
	t.set_stylebox("disabled", "Button", pill(false))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("panel", "PanelContainer", panel())
	var tip := panel(10, BRONZE, BG_DEEP, 1)
	tip.set_content_margin_all(8)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 13)
	var grab := StyleBoxFlat.new()
	grab.bg_color = BRONZE
	grab.set_corner_radius_all(3)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab)
	var sc := StyleBoxFlat.new()
	sc.bg_color = Color(0, 0, 0, 0.3)
	sc.set_corner_radius_all(3)
	t.set_stylebox("scroll", "VScrollBar", sc)
	_theme = t
	return t


## 걷기 시트 앞모습에서 얼굴·상반신을 잘라 초상으로 쓴다(전용 초상 그림이 없어서).
static func portrait_tex(c: Node, region: Rect2 = Rect2(144 + 14, 6, 44, 44)) -> Texture2D:
	var art: Dictionary = c.get_meta("art", {})
	if art.has("sheet") and ResourceLoader.exists(art["sheet"]):
		var at := AtlasTexture.new()
		at.atlas = load(art["sheet"])
		at.region = region
		return at
	if art.has("image") and ResourceLoader.exists(art["image"]):
		return load(art["image"])
	return null


## 장식 틀: 둥근 바탕 + 바깥 청동선 + 안쪽 가는 금선 + 위·아래 가운데 마름모 장식.
class OrnateFrame extends Control:
	var radius := 16.0
	var fill := BG
	var ornaments := true

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var sb := StyleBoxFlat.new()
		sb.bg_color = fill
		sb.border_color = BRONZE
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(int(radius))
		sb.shadow_color = Color(0, 0, 0, 0.5)
		sb.shadow_size = 8
		sb.anti_aliasing = true
		draw_style_box(sb, r)
		var inner := StyleBoxFlat.new()
		inner.draw_center = false
		inner.border_color = Color(GOLD, 0.35)
		inner.set_border_width_all(1)
		inner.set_corner_radius_all(int(maxf(radius - 5, 2)))
		inner.anti_aliasing = true
		draw_style_box(inner, r.grow(-5))
		if ornaments:
			for y: float in [0.0, size.y]:
				var c := Vector2(size.x / 2, y)
				var pts := PackedVector2Array([c + Vector2(0, -7), c + Vector2(9, 0), c + Vector2(0, 7), c + Vector2(-9, 0)])
				draw_colored_polygon(pts, BRONZE_DARK)
				draw_polyline(pts + PackedVector2Array([pts[0]]), GOLD_SOFT, 1.5, true)


## 원형 초상: 원 안에 그림, 청동 고리 두 겹, 아래에 HP 글자.
class CirclePortrait extends Control:
	var texture: Texture2D
	var ring := BRONZE
	var hp_text := ""
	var hp_ratio := 1.0

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0 - 4
		draw_circle(c, r + 3, Color(0, 0, 0, 0.6))
		draw_circle(c, r, BG_SLOT)
		if texture != null:
			_draw_circle_texture(c, r - 1)
		# HP 고리(아래 반원에서 빨간 호)
		draw_arc(c, r - 1, deg_to_rad(90 - 180 * hp_ratio), deg_to_rad(90 + 180 * hp_ratio), 48, Color(HP, 0.9), 4.0, true)
		draw_arc(c, r + 1, 0, TAU, 64, ring, 3.0, true)
		draw_arc(c, r + 5, 0, TAU, 64, Color(GOLD, 0.5), 1.5, true)
		if hp_text != "":
			var f: Font = ThemeDB.fallback_font
			var w := 70.0
			var box := Rect2(Vector2(c.x - w / 2, size.y - 20), Vector2(w, 18))
			var sb := StyleBoxFlat.new()
			sb.bg_color = BG_DEEP
			sb.border_color = BRONZE
			sb.set_border_width_all(1)
			sb.set_corner_radius_all(9)
			draw_style_box(sb, box)
			draw_string(f, Vector2(box.position.x, box.position.y + 14), hp_text, HORIZONTAL_ALIGNMENT_CENTER, w, 13, TEXT)

	## 원 모양 다각형에 그림을 입힌다(아틀라스면 그 영역의 UV로).
	func _draw_circle_texture(c: Vector2, r: float) -> void:
		var tex: Texture2D = texture
		var uv_rect := Rect2(0, 0, 1, 1)
		if texture is AtlasTexture:
			var at := texture as AtlasTexture
			tex = at.atlas
			var full := Vector2(tex.get_size())
			uv_rect = Rect2(at.region.position / full, at.region.size / full)
		var pts := PackedVector2Array()
		var uvs := PackedVector2Array()
		for i in 48:
			var a := TAU * i / 48.0
			var d := Vector2(cos(a), sin(a))
			pts.append(c + d * r)
			uvs.append(uv_rect.position + (d * 0.5 + Vector2(0.5, 0.5)) * uv_rect.size)
		draw_polygon(pts, PackedColorArray([Color.WHITE]), uvs, tex)


## 아이콘을 차분하게(채도를 낮추고 따뜻한 색을 조금 섞음). dim = 쓸 수 없을 때 더 어둡게.
static func icon_material(dim: bool = false) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float sat = 0.55;
uniform float bright = 0.95;
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 m = mix(vec3(g), c.rgb, sat) * vec3(1.0, 0.95, 0.86) * bright;
	COLOR = vec4(m, c.a);
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("sat", 0.15 if dim else 0.55)
	m.set_shader_parameter("bright", 0.45 if dim else 0.95)
	return m
