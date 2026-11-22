extends HBoxContainer
## 하단 단축 막대(BG3 배치 참고, 표현 계층):
##   원형 초상(HP 고리) | 무기 세트(근접·원거리) | [턴 자원 표시] [아이콘 칸 — 구역 사이 붉은 구분선] [아래 탭] | 모래시계(턴 종료) · 보조 원 버튼
## 규칙은 모른다 — 행동 목록·사용 가능 여부는 scripts/rules/actions.gd가 준다.

signal action_chosen(key: String)
signal end_turn_pressed
signal explore_pressed(id: String)

const Actions := preload("res://scripts/rules/actions.gd")
const UiText := preload("res://scenes/ui/ui_text.gd")
const S := preload("res://scenes/ui/ui_style.gd")
const SLOT := Vector2(46, 46)
const SCHOOL_COLOR := {"evocation": Color("8a4a33"), "abjuration": Color("3f5f80"), "conjuration": Color("7d6a3a"),
	"divination": Color("4f6f7f"), "enchantment": Color("7a4a6a"), "illusion": Color("5d4f82"),
	"necromancy": Color("4a6648"), "transmutation": Color("7a6146")}
## 탭: all = 모든 구역을 구분선으로 나눠 한 줄에
const TABS := ["all", "common", "class", "spells", "items", "explore"]

var tab := "all"
var selected_key := ""
var _creature: Node
var _world: Dictionary
var _explore := false
var _explore_buttons: Array = []

var portrait: Control
var weapons_box: VBoxContainer
var res_marks: Control
var move_bar: ProgressBar
var slots_label: Label
var sections: HBoxContainer
var tabs_row: HBoxContainer
var end_button: Button
var side_button: Button


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	alignment = BoxContainer.ALIGNMENT_CENTER
	# 원형 초상
	portrait = S.CirclePortrait.new()
	portrait.custom_minimum_size = Vector2(118, 124)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_END
	add_child(portrait)
	# 무기 세트
	var wframe := PanelContainer.new()
	wframe.add_theme_stylebox_override("panel", S.panel(12, S.BRONZE_DARK, S.BG, 1))
	wframe.size_flags_vertical = Control.SIZE_SHRINK_END
	add_child(wframe)
	weapons_box = VBoxContainer.new()
	weapons_box.add_theme_constant_override("separation", 4)
	wframe.add_child(weapons_box)
	# 가운데: 자원 표시 / 칸 / 탭
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 3)
	mid.size_flags_vertical = Control.SIZE_SHRINK_END
	add_child(mid)
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 10)
	mid.add_child(top)
	res_marks = ResourceMarks.new()
	res_marks.custom_minimum_size = Vector2(110, 26)
	top.add_child(res_marks)
	move_bar = S.bar(S.MOVE, Vector2(150, 8))
	move_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	move_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	top.add_child(move_bar)
	slots_label = Label.new()
	slots_label.add_theme_font_size_override("font_size", 13)
	slots_label.add_theme_color_override("font_color", S.GOLD_SOFT)
	top.add_child(slots_label)
	var frame := PanelContainer.new()
	var fsb := S.panel(14, S.BRONZE, S.BG, 2)
	fsb.set_content_margin_all(7)
	frame.add_theme_stylebox_override("panel", fsb)
	mid.add_child(frame)
	sections = HBoxContainer.new()
	sections.add_theme_constant_override("separation", 6)
	sections.custom_minimum_size = Vector2(0, SLOT.y * 2 + 3)
	frame.add_child(sections)
	tabs_row = HBoxContainer.new()
	tabs_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs_row.add_theme_constant_override("separation", 4)
	mid.add_child(tabs_row)
	# 오른쪽: 모래시계(턴 종료)·보조 원 버튼
	end_button = _round_button(104, "hourglass")
	end_button.pressed.connect(func() -> void:
		if _explore:
			explore_pressed.emit("sneak")
		else:
			end_turn_pressed.emit())
	add_child(end_button)
	side_button = _round_button(54, "camp")
	side_button.pressed.connect(func() -> void:
		if _explore:
			explore_pressed.emit("long_rest"))
	add_child(side_button)


func _round_button(d: int, glyph: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(d, d)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE
	var st := S.panel(d / 2, S.BRONZE, S.BG_DEEP, 3)
	b.add_theme_stylebox_override("normal", st)
	var hv: StyleBoxFlat = st.duplicate()
	hv.border_color = S.GOLD
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", hv)
	b.add_theme_stylebox_override("disabled", st)
	var g := RoundGlyph.new()
	g.kind = glyph
	g.set_anchors_preset(Control.PRESET_FULL_RECT)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.name = "Glyph"
	b.add_child(g)
	return b


## 선택한 캐릭터로 다시 그린다. explore_buttons: 탐험 탭의 [{id, text, pressed?}]
func show_for(world: Dictionary, c: Node, explore: bool, explore_buttons: Array = []) -> void:
	_world = world
	_creature = c
	_explore = explore
	_explore_buttons = explore_buttons
	if c == null:
		visible = false
		return
	visible = true
	if not explore and tab == "explore":
		tab = "all"
	portrait.texture = S.portrait_tex(c)
	portrait.hp_text = "%d/%d" % [c.hp, c.hp_max]
	portrait.hp_ratio = clampf(float(c.hp) / maxf(c.hp_max, 1), 0.0, 1.0)
	portrait.tooltip_text = "%s · %d%s" % [c.label(), c.level, UiText.t("lv")]
	portrait.queue_redraw()
	_draw_weapons(c)
	_draw_resources(c, explore)
	_draw_tabs(world, c, explore)
	_draw_sections(world, c, explore)
	var eg: Control = end_button.get_node("Glyph")
	eg.kind = ("eye_open" if c.sneaking else "eye") if explore else "hourglass"
	eg.queue_redraw()
	end_button.tooltip_text = (UiText.t("sneak_on") if c.sneaking else UiText.t("sneak_off")) if explore else UiText.t("end_turn")
	side_button.visible = explore
	side_button.tooltip_text = UiText.t("camp")


func _draw_weapons(c: Node) -> void:
	for ch in weapons_box.get_children():
		ch.queue_free()
	for set_name: String in ["melee", "ranged"]:
		var wid: String = c.weapon_sets.get(set_name, {}).get("main", "")
		var b := Button.new()
		b.custom_minimum_size = Vector2(44, 44)
		b.focus_mode = Control.FOCUS_NONE
		var active: bool = c.active_set == set_name
		b.add_theme_stylebox_override("normal", S.slot(S.BRONZE_DARK, active))
		b.add_theme_stylebox_override("hover", S.slot(S.GOLD_SOFT, active))
		b.add_theme_stylebox_override("pressed", S.slot(S.GOLD_SOFT, true))
		var tr := TextureRect.new()
		tr.texture = load(_weapon_icon(wid, set_name))
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.offset_left = 4
		tr.offset_top = 4
		tr.offset_right = -4
		tr.offset_bottom = -4
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.material = S.icon_material(not active)
		b.add_child(tr)
		var w := RulesDB.get_entry("weapon", wid)
		b.tooltip_text = "%s: %s" % [UiText.t("set_" + set_name), UiText.name_of(w.get("name", {"ko": "-", "en": "-"}))]
		b.pressed.connect(func() -> void:
			if c.active_set != set_name:
				action_chosen.emit("switch_weapons"))
		weapons_box.add_child(b)


static func _weapon_icon(wid: String, set_name: String) -> String:
	var map := {"longsword": "items/fortress_knight_sword.webp", "shortsword": "items/mithril_sword.webp",
		"dagger": "items/beast_bone_dagger.webp", "mace": "items/beast_bone_mace.webp", "quarterstaff": "items/artene_staff.webp",
		"greatsword": "items/mithril_greatsword.webp", "shortbow": "items/hunting_bow.webp", "longbow": "items/ironwood_bow.webp",
		"light_crossbow": "items/ironwood_crossbow.webp", "javelin": "items/airilje_spear.webp"}
	var p: String = "res://assets/" + map.get(wid, "items/hunting_bow.webp" if set_name == "ranged" else "items/fortress_knight_sword.webp")
	return p if ResourceLoader.exists(p) else "res://assets/items/fortress_knight_sword.webp"


func _draw_resources(c: Node, explore: bool) -> void:
	var t: Dictionary = c.turn
	res_marks.have = [explore or int(t.get("action", 0)) > 0, explore or int(t.get("bonus", 0)) > 0, explore or int(t.get("reaction", 0)) > 0]
	res_marks.tooltip_text = "%s · %s · %s" % [UiText.t("res_action"), UiText.t("res_bonus"), UiText.t("res_reaction")]
	res_marks.queue_redraw()
	move_bar.max_value = maxi(c.speed(), 1)
	move_bar.value = c.speed() if explore else int(t.get("movement", 0))
	move_bar.tooltip_text = UiText.t("res_move") % [move_bar.value * 1.5, c.speed() * 1.5]
	var pips := PackedStringArray()
	for lv in range(1, 10):
		var r: Dictionary = c.resources.get("spell_slot_%d" % lv, {})
		if r.is_empty():
			continue
		pips.append("%s %s" % [["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX"][lv],
			"◆".repeat(int(r["current"])) + "◇".repeat(int(r["max"]) - int(r["current"]))])
	slots_label.text = "   ".join(pips)


func _draw_tabs(world: Dictionary, c: Node, explore: bool) -> void:
	for ch in tabs_row.get_children():
		ch.queue_free()
	var lists: Dictionary = Actions.list_for(world, c, explore)
	for id: String in TABS:
		if id == "explore" and not explore:
			continue
		if id != "explore" and id != "all" and lists.get(id, []).is_empty():
			continue
		var b := Button.new()
		b.text = UiText.t("tab_" + id) if id != "class" else UiText.name_of(RulesDB.get_entry("class", c.class_id).get("name", {"ko": UiText.t("tab_class"), "en": UiText.t("tab_class")}))
		b.add_theme_font_size_override("font_size", 13)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", S.pill(id == tab))
		b.add_theme_stylebox_override("hover", S.pill(true))
		b.add_theme_stylebox_override("pressed", S.pill(true))
		b.pressed.connect(func() -> void:
			tab = id
			show_for(_world, _creature, _explore, _explore_buttons))
		tabs_row.add_child(b)


func _draw_sections(world: Dictionary, c: Node, explore: bool) -> void:
	for ch in sections.get_children():
		ch.queue_free()
	if tab == "explore":
		var g := GridContainer.new()
		g.columns = 4
		g.add_theme_constant_override("h_separation", 4)
		g.add_theme_constant_override("v_separation", 4)
		for e: Dictionary in _explore_buttons:
			var b := Button.new()
			b.text = e["text"]
			b.custom_minimum_size = Vector2(120, SLOT.y - 4)
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_font_size_override("font_size", 12)
			b.add_theme_stylebox_override("normal", S.pill(e.get("pressed", false)))
			b.disabled = e.get("disabled", false)
			b.tooltip_text = e.get("tip", "")
			b.pressed.connect(explore_pressed.emit.bind(e["id"]))
			g.add_child(b)
		sections.add_child(g)
		return
	var lists: Dictionary = Actions.list_for(world, c, explore)
	var order: Array = ["common", "class", "spells", "items"] if tab == "all" else [tab]
	var first := true
	for sec: String in order:
		var keys: Array = lists.get(sec, [])
		if tab == "all" and sec == "items":
			keys = keys.filter(func(k: String) -> bool: return k.begins_with("drink:"))  # 전체 보기에는 마시기만
		if keys.is_empty():
			continue
		if not first:
			var div := ColorRect.new()
			div.color = S.DIVIDER
			div.custom_minimum_size = Vector2(4, SLOT.y * 2 + 3)
			sections.add_child(div)
		first = false
		var g := GridContainer.new()
		g.columns = maxi(1, ceili(keys.size() / 2.0))
		g.add_theme_constant_override("h_separation", 3)
		g.add_theme_constant_override("v_separation", 3)
		for key: String in keys:
			g.add_child(_slot(world, c, key, explore))
		sections.add_child(g)


func _slot(world: Dictionary, c: Node, key: String, explore: bool) -> Control:
	var d := Actions.def_of(key)
	var why := Actions.unavailable(world, c, key, explore)
	var b := Button.new()
	b.custom_minimum_size = SLOT
	b.focus_mode = Control.FOCUS_NONE
	var sel := key == selected_key
	b.add_theme_stylebox_override("normal", S.slot(S.BRONZE_DARK, sel))
	b.add_theme_stylebox_override("hover", S.slot(S.GOLD_SOFT, sel))
	b.add_theme_stylebox_override("pressed", S.slot(S.GOLD, true))
	b.add_theme_stylebox_override("disabled", S.slot())
	var icon := _icon_for(key, d, why != "")
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 3
	icon.offset_top = 3
	icon.offset_right = -3
	icon.offset_bottom = -3
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(icon)
	# 비용 표시(왼쪽 위 작은 점 — 행동 초록·보너스 주황·반응 보라)
	var dot := CostDot.new()
	dot.color = S.cost_color(str(d.get("cost", "action")))
	dot.position = Vector2(3, 3)
	dot.size = Vector2(8, 8)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(dot)
	var count := -1
	if d.has("item"):
		count = int(world.get("inventory", {}).get(d["item"], 0))
	elif d.get("resource", "") != "":
		count = c.resource(d["resource"])
	if count >= 0:
		var cl := Label.new()
		cl.text = str(count)
		cl.add_theme_font_size_override("font_size", 12)
		cl.add_theme_color_override("font_color", S.TEXT)
		cl.add_theme_color_override("font_outline_color", Color.BLACK)
		cl.add_theme_constant_override("outline_size", 4)
		cl.position = Vector2(SLOT.x - 13, SLOT.y - 19)
		cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(cl)
	var tip := "%s\n%s · %s" % [UiText.name_of(d.get("name", {})), UiText.t("cost_" + str(d.get("cost", "action"))),
		UiText.t("target_" + str(d.get("target", "self")))]
	var desc := UiText.name_of(d.get("desc", {}))
	if desc != "":
		tip += "\n" + desc
	if why != "":
		tip += "\n— " + why
	b.tooltip_text = tip
	b.pressed.connect(func() -> void: action_chosen.emit(key))
	return b


## 행동 아이콘: 그림이 있으면 차분하게 바꾼 그림, 주문은 학파 색 원 + 첫 글자.
func _icon_for(key: String, d: Dictionary, dim: bool) -> Control:
	var path: String = d.get("icon", "")
	if path != "" and ResourceLoader.exists(path):
		var tr := TextureRect.new()
		tr.texture = load(path)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.material = S.icon_material(dim)
		return tr
	var g := Glyph.new()
	var sp: Dictionary = d.get("spell", {})
	g.color = SCHOOL_COLOR.get(sp.get("school", ""), Color("5a5f66"))
	if dim:
		g.color = g.color.darkened(0.5)
	g.text = UiText.name_of(d.get("name", {})).left(1)
	g.level = int(sp.get("level", -1))
	return g


## 주문 아이콘(그림이 없어서): 어두운 원 + 학파 색 + 금빛 테 + 첫 글자.
class Glyph extends Control:
	var color := Color.GRAY
	var text := ""
	var level := -1

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0 - 1
		draw_circle(c, r, Color(0.06, 0.05, 0.045))
		draw_circle(c, r - 3, color)
		draw_arc(c, r - 3, 0, TAU, 40, Color(S.GOLD_SOFT, 0.7), 1.2, true)
		draw_string(S.title_font(), Vector2(0, c.y + 7), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 19, Color(0.95, 0.9, 0.8))
		if level > 0:
			draw_string(ThemeDB.fallback_font, Vector2(size.x - 11, 11), str(level), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, S.GOLD)


class CostDot extends Control:
	var color := Color.GRAY

	func _draw() -> void:
		draw_circle(size / 2, 3.5, Color(0, 0, 0, 0.7))
		draw_circle(size / 2, 2.6, color)


## 턴 자원 표시: 행동 ●(초록) · 보너스 ▲(주황) · 반응 ◆(보라). 쓴 것은 어둡게.
class ResourceMarks extends Control:
	var have := [true, true, true]

	func _draw() -> void:
		var cols := [S.ACTION, S.BONUS, S.REACTION]
		for i in 3:
			var c := Vector2(18 + i * 36, size.y / 2)
			var col: Color = cols[i] if have[i] else Color(0.22, 0.2, 0.18)
			var ring := S.GOLD_SOFT if have[i] else S.BRONZE_DARK
			draw_circle(c, 12, Color(0.05, 0.04, 0.035))
			draw_arc(c, 12, 0, TAU, 32, ring, 1.2, true)
			match i:
				0:
					draw_circle(c, 6.5, col)
				1:
					draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7), c + Vector2(7, 5.5), c + Vector2(-7, 5.5)]), col)
				2:
					draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7.5), c + Vector2(6, 0), c + Vector2(0, 7.5), c + Vector2(-6, 0)]), col)


## 원 버튼 안 그림: 모래시계(턴 종료)·눈(은신)·모닥불(캠프).
class RoundGlyph extends Control:
	var kind := "hourglass"

	func _draw() -> void:
		var c := size / 2.0
		var k := minf(size.x, size.y) / 100.0
		var col := S.GOLD
		match kind:
			"hourglass":
				draw_arc(c, 40 * k, 0, TAU, 48, Color(S.BRONZE, 0.8), 2.0, true)
				var top := PackedVector2Array([c + Vector2(-14, -22) * k, c + Vector2(14, -22) * k, c + Vector2(0, 0)])
				var bot := PackedVector2Array([c + Vector2(0, 0), c + Vector2(14, 22) * k, c + Vector2(-14, 22) * k])
				draw_colored_polygon(top, Color(col, 0.25))
				draw_colored_polygon(bot, Color(col, 0.6))
				draw_polyline(top + PackedVector2Array([top[0]]), col, 2.0, true)
				draw_polyline(bot + PackedVector2Array([bot[0]]), col, 2.0, true)
				draw_line(c + Vector2(-18, -24) * k, c + Vector2(18, -24) * k, col, 3.0, true)
				draw_line(c + Vector2(-18, 24) * k, c + Vector2(18, 24) * k, col, 3.0, true)
			"eye", "eye_open":
				var w := 26 * k
				var pts := PackedVector2Array()
				for i in 17:
					var tt := i / 16.0
					pts.append(c + Vector2(lerpf(-w, w, tt), -sin(tt * PI) * 13 * k))
				for i in 17:
					var tt := 1.0 - i / 16.0
					pts.append(c + Vector2(lerpf(-w, w, tt), sin(tt * PI) * 13 * k))
				draw_polyline(pts, col, 2.0, true)
				draw_circle(c, 7 * k, col if kind == "eye_open" else Color(col, 0.35))
				if kind == "eye":
					draw_line(c + Vector2(-w, 14 * k), c + Vector2(w, -14 * k), Color(col, 0.8), 2.0, true)
			"camp":
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -16) * k * 2, c + Vector2(9, 8) * k * 2, c + Vector2(-9, 8) * k * 2]), Color(S.BONUS, 0.9))
				draw_line(c + Vector2(-12, 10) * k * 2, c + Vector2(12, 14) * k * 2, S.BRONZE, 3.0, true)
				draw_line(c + Vector2(12, 10) * k * 2, c + Vector2(-12, 14) * k * 2, S.BRONZE, 3.0, true)
