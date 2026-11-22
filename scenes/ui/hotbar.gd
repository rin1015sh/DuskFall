extends PanelContainer
## 하단 단축 막대(BG3 구조 참고, 표현 계층): 초상·HP | 턴 자원(행동 ●·보너스 ▲·반응 ◆·이동 막대)·주문 슬롯 |
## 탭(공용·클래스·주문·아이템·탐험) + 아이콘 칸 | 턴 종료(전투) 또는 은신(탐험).
## 규칙은 모른다 — 행동 목록·사용 가능 여부는 scripts/rules/actions.gd가 준다.

signal action_chosen(key: String)
signal end_turn_pressed
signal explore_pressed(id: String)

const Actions := preload("res://scripts/rules/actions.gd")
const UiText := preload("res://scenes/ui/ui_text.gd")
const SLOT := Vector2(52, 52)
const COST_COLOR := {"action": Color("49b35a"), "bonus": Color("e08a2c"), "reaction": Color("a061d8"), "free": Color("9aa3ad")}
const SCHOOL_COLOR := {"evocation": Color("d9542c"), "abjuration": Color("3f8fd2"), "conjuration": Color("c9a23a"),
	"divination": Color("8fc7e8"), "enchantment": Color("d06bb0"), "illusion": Color("8a6be0"),
	"necromancy": Color("5e9e55"), "transmutation": Color("b48a52")}
const TAB_ORDER := ["common", "class", "spells", "items", "explore"]

var tab := "common"
var selected_key := ""
var _creature: Node
var _world: Dictionary
var _explore := false
var _explore_buttons: Array = []

var portrait: TextureRect
var name_label: Label
var hp_bar: ProgressBar
var hp_label: Label
var res_row: HBoxContainer
var move_bar: ProgressBar
var slots_label: Label
var tabs_row: HBoxContainer
var grid: GridContainer
var big_button: Button


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.06, 0.08, 0.94)
	sb.border_color = Color(0.62, 0.5, 0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(8)
	add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	# 초상·HP
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(110, 0)
	row.add_child(left)
	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(96, 72)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	left.add_child(portrait)
	name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 13)
	left.add_child(name_label)
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(100, 12)
	hp_bar.show_percentage = false
	var hb := StyleBoxFlat.new()
	hb.bg_color = Color("b8312f")
	hp_bar.add_theme_stylebox_override("fill", hb)
	left.add_child(hp_bar)
	hp_label = Label.new()
	hp_label.add_theme_font_size_override("font_size", 12)
	left.add_child(hp_label)
	# 가운데: 자원 줄 + 탭 + 칸
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 4)
	row.add_child(mid)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	mid.add_child(top)
	res_row = HBoxContainer.new()
	res_row.add_theme_constant_override("separation", 4)
	top.add_child(res_row)
	move_bar = ProgressBar.new()
	move_bar.custom_minimum_size = Vector2(140, 10)
	move_bar.show_percentage = false
	var mb := StyleBoxFlat.new()
	mb.bg_color = Color("d8b23c")
	move_bar.add_theme_stylebox_override("fill", mb)
	move_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(move_bar)
	slots_label = Label.new()
	slots_label.add_theme_font_size_override("font_size", 13)
	top.add_child(slots_label)
	tabs_row = HBoxContainer.new()
	mid.add_child(tabs_row)
	grid = GridContainer.new()
	grid.columns = 11
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	grid.custom_minimum_size = Vector2(11 * (SLOT.x + 3), SLOT.y * 2 + 3)
	mid.add_child(grid)
	# 오른쪽: 턴 종료(전투) / 은신(탐험)
	big_button = Button.new()
	big_button.custom_minimum_size = Vector2(92, 92)
	big_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.25, 0.18, 0.1)
	bs.border_color = Color(0.85, 0.7, 0.35)
	bs.set_border_width_all(3)
	bs.set_corner_radius_all(46)
	big_button.add_theme_stylebox_override("normal", bs)
	var bh := bs.duplicate()
	bh.bg_color = Color(0.38, 0.27, 0.12)
	big_button.add_theme_stylebox_override("hover", bh)
	big_button.add_theme_stylebox_override("pressed", bh)
	big_button.pressed.connect(func() -> void:
		if _explore:
			explore_pressed.emit("sneak")
		else:
			end_turn_pressed.emit())
	row.add_child(big_button)


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
		tab = "common"
	var art: Dictionary = c.get_meta("art", {})
	if art.has("sheet") and ResourceLoader.exists(art["sheet"]):
		var at := AtlasTexture.new()
		at.atlas = load(art["sheet"])
		at.region = Rect2(144, 0, 72, 60)
		portrait.texture = at
	name_label.text = "%s  %d%s" % [c.label(), c.level, UiText.t("lv")]
	hp_bar.max_value = c.hp_max
	hp_bar.value = c.hp
	hp_label.text = "HP %d/%d%s" % [c.hp, c.hp_max, (" +%d" % c.temp_hp) if c.temp_hp > 0 else ""]
	_draw_resources(c, explore)
	_draw_tabs(world, c, explore)
	_draw_grid(world, c, explore)
	big_button.text = (UiText.t("sneak_on") if c.sneaking else UiText.t("sneak_off")) if explore else UiText.t("end_turn")


func _draw_resources(c: Node, explore: bool) -> void:
	for ch in res_row.get_children():
		ch.queue_free()
	var t: Dictionary = c.turn
	for spec: Array in [["action", "●"], ["bonus", "▲"], ["reaction", "◆"]]:
		var l := Label.new()
		l.text = spec[1]
		l.add_theme_font_size_override("font_size", 22)
		var have: bool = explore or int(t.get(spec[0], 0)) > 0
		l.add_theme_color_override("font_color", COST_COLOR[spec[0]] if have else Color(0.3, 0.3, 0.3))
		l.tooltip_text = UiText.t("res_" + spec[0])
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		res_row.add_child(l)
	move_bar.max_value = maxi(c.speed(), 1)
	move_bar.value = c.speed() if explore else int(t.get("movement", 0))
	move_bar.tooltip_text = UiText.t("res_move") % [int(move_bar.value) * 1.5, c.speed() * 1.5]
	var pips := PackedStringArray()
	for lv in range(1, 10):
		var r: Dictionary = c.resources.get("spell_slot_%d" % lv, {})
		if r.is_empty():
			continue
		pips.append("%s %s" % [["", "Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ", "Ⅴ", "Ⅵ", "Ⅶ", "Ⅷ", "Ⅸ"][lv],
			"●".repeat(int(r["current"])) + "○".repeat(int(r["max"]) - int(r["current"]))])
	slots_label.text = "  ".join(pips)


func _draw_tabs(world: Dictionary, c: Node, explore: bool) -> void:
	for ch in tabs_row.get_children():
		ch.queue_free()
	var lists: Dictionary = Actions.list_for(world, c, explore)
	for id: String in TAB_ORDER:
		if id == "explore" and not explore:
			continue
		if id != "explore" and lists.get(id, []).is_empty():
			continue
		var b := Button.new()
		b.text = UiText.t("tab_" + id)
		b.toggle_mode = true
		b.button_pressed = id == tab
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func() -> void:
			tab = id
			show_for(_world, _creature, _explore, _explore_buttons))
		tabs_row.add_child(b)


func _draw_grid(world: Dictionary, c: Node, explore: bool) -> void:
	for ch in grid.get_children():
		ch.queue_free()
	if tab == "explore":
		for e: Dictionary in _explore_buttons:
			var b := Button.new()
			b.text = e["text"]
			b.custom_minimum_size = Vector2(SLOT.x * 2 + 3, SLOT.y)
			b.toggle_mode = e.has("pressed")
			b.button_pressed = e.get("pressed", false)
			b.disabled = e.get("disabled", false)
			b.add_theme_font_size_override("font_size", 12)
			b.tooltip_text = e.get("tip", "")
			b.pressed.connect(explore_pressed.emit.bind(e["id"]))
			grid.add_child(b)
		return
	var lists: Dictionary = Actions.list_for(world, c, explore)
	for key: String in lists.get(tab, []):
		grid.add_child(_slot(world, c, key, explore))


func _slot(world: Dictionary, c: Node, key: String, explore: bool) -> Control:
	var d := Actions.def_of(key)
	var why := Actions.unavailable(world, c, key, explore)
	var b := Button.new()
	b.custom_minimum_size = SLOT
	b.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.12, 0.14)
	sb.border_color = Color(1, 0.85, 0.3) if key == selected_key else COST_COLOR.get(d.get("cost", "action"), Color.GRAY)
	sb.set_border_width_all(3 if key == selected_key else 2)
	sb.set_corner_radius_all(4)
	b.add_theme_stylebox_override("normal", sb)
	var hov := sb.duplicate()
	hov.bg_color = Color(0.24, 0.22, 0.2)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", hov)
	b.add_theme_stylebox_override("disabled", sb)
	var icon := _icon_for(key, d)
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 4
	icon.offset_top = 4
	icon.offset_right = -4
	icon.offset_bottom = -4
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if why != "":
		icon.modulate = Color(0.35, 0.35, 0.35)
	b.add_child(icon)
	# 남은 횟수(아이템 개수·기능 사용 횟수)
	var count := -1
	if d.has("item"):
		count = int(world.get("inventory", {}).get(d["item"], 0))
	elif d.get("resource", "") != "":
		count = c.resource(d["resource"])
	if count >= 0:
		var cl := Label.new()
		cl.text = str(count)
		cl.add_theme_font_size_override("font_size", 12)
		cl.add_theme_color_override("font_outline_color", Color.BLACK)
		cl.add_theme_constant_override("outline_size", 4)
		cl.position = Vector2(SLOT.x - 14, SLOT.y - 18)
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


## 행동 아이콘: 그림이 있으면 그림, 주문은 학파 색 원 + 글자(그림 없음).
func _icon_for(key: String, d: Dictionary) -> Control:
	var path: String = d.get("icon", "")
	if path != "" and ResourceLoader.exists(path):
		var tr := TextureRect.new()
		tr.texture = load(path)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		return tr
	var g := Glyph.new()
	var sp: Dictionary = d.get("spell", {})
	g.color = SCHOOL_COLOR.get(sp.get("school", ""), Color("6b7a8f"))
	g.text = UiText.name_of(d.get("name", {})).left(1)
	g.level = int(sp.get("level", -1))
	return g


class Glyph extends Control:
	var color := Color.GRAY
	var text := ""
	var level := -1

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		draw_circle(c, r, color.darkened(0.45))
		draw_circle(c, r - 3, color)
		var f := ThemeDB.fallback_font
		draw_string(f, Vector2(0, c.y + 8), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color.WHITE)
		if level > 0:
			draw_string(f, Vector2(2, 12), str(level), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.9))
