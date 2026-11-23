extends Control
## 주문 준비 창(표현 계층, BG3 주문서 탭 참고): 준비 수·교체 창 상태, 레벨별 주문 칸(누르면 준비/빼기),
## 항상 준비·소마법(보기만), 주문서형이면 두루마리에서 배우기(두루마리 소모 + 레벨 × 50gp).
## 규칙은 spell_prep.gd가 정하고 이 창은 결과만 그린다. K 키 또는 캐릭터 창의 버튼으로 연다.

const S := preload("res://scenes/ui/ui_style.gd")
const UiText := preload("res://scenes/ui/ui_text.gd")
const ActionIcons := preload("res://scenes/ui/action_icons.gd")
const SpellPrep := preload("res://scripts/rules/spell_prep.gd")

signal changed

var world: Dictionary = {}
var creature: Node
var body: VBoxContainer
var status: Label


func _ready() -> void:
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -400
	offset_right = 400
	offset_top = -280
	offset_bottom = 240
	var frame := S.OrnateFrame.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.radius = 18
	frame.fill = S.BG_DEEP
	add_child(frame)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	var close := Button.new()
	close.text = "✕"
	close.anchor_left = 1.0
	close.anchor_right = 1.0
	close.offset_left = -46
	close.offset_top = 12
	close.custom_minimum_size = Vector2(30, 30)
	close.pressed.connect(func() -> void: visible = false)
	add_child(close)
	visible = false


func show_for(w: Dictionary, c: Node) -> void:
	world = w
	creature = c
	_rebuild()
	visible = c != null


func _rebuild(note: String = "") -> void:
	for ch in body.get_children():
		ch.queue_free()
	var c := creature
	if c == null:
		return
	var cls := RulesDB.get_entry("class", c.class_id)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	head.add_child(S.title(UiText.t("spells_window"), 22))
	var who := Label.new()
	who.text = "%s · %s" % [c.label(), UiText.name_of(cls.get("name", {"ko": "", "en": ""}))]
	who.add_theme_color_override("font_color", S.TEXT_DIM)
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(who)
	body.add_child(head)
	status = Label.new()
	status.add_theme_font_size_override("font_size", 13)
	body.add_child(status)
	var t := SpellPrep.prep_type(c)
	if t == "":
		status.text = UiText.t("swap_none")
	else:
		var line := UiText.t("prepared_n") % [c.prepared.size(), SpellPrep.max_prepared(c)]
		var why := SpellPrep.change_blocked(world, c)
		if why == "":
			var left := SpellPrep.swaps_left(c)
			line += "  ·  " + (UiText.t("swap_all") if left < 0 else UiText.t("swap_left") % left)
		else:
			line += "  ·  " + UiText.reason(why)
		status.text = line + ("\n" + note if note != "" else "")
	status.add_theme_color_override("font_color", S.GOLD_SOFT if note == "" else Color(0.9, 0.5, 0.4))
	# 소마법·항상 준비(보기만)
	var cantrips: Array = c.spells.filter(func(s: String) -> bool: return int(RulesDB.get_entry("spell", s).get("level", 0)) == 0)
	if not cantrips.is_empty():
		_row(UiText.t("cantrips"), cantrips, false)
	var fixed := SpellPrep.fixed_spells(c)
	if not fixed.is_empty():
		_row(UiText.t("always_prepared"), fixed, false)
	# 준비할 수 있는 주문(레벨별)
	var pool := SpellPrep.pool(c)
	for sid: String in c.prepared:
		if not sid in pool:
			pool.append(sid)
	var by_level := {}
	for sid: String in pool:
		var lv := int(RulesDB.get_entry("spell", sid).get("level", 1))
		if not by_level.has(lv):
			by_level[lv] = []
		by_level[lv].append(sid)
	var levels: Array = by_level.keys()
	levels.sort()
	for lv: int in levels:
		var ids: Array = by_level[lv]
		ids.sort_custom(func(a: String, b: String) -> bool: return UiText.name_of(RulesDB.get_entry("spell", a)["name"]) < UiText.name_of(RulesDB.get_entry("spell", b)["name"]))
		_row(UiText.t("spell_level_n") % lv, ids, true)
	if t == "spellbook":
		_scrolls()


func _row(title: String, ids: Array, toggles: bool) -> void:
	var l := S.title(title, 15)
	body.add_child(l)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	body.add_child(flow)
	for sid: String in ids:
		flow.add_child(_slot(sid, toggles))


func _slot(sid: String, toggles: bool) -> Control:
	var c := creature
	var sp := RulesDB.get_entry("spell", sid)
	var on: bool = c.spells.has(sid)
	var p := Button.new()
	p.custom_minimum_size = Vector2(52, 52)
	p.focus_mode = Control.FOCUS_NONE
	var sb := S.slot(S.GOLD if on else S.BRONZE_DARK, on)
	for k: String in ["normal", "hover", "pressed", "disabled"]:
		p.add_theme_stylebox_override(k, sb)
	var ic: Control = ActionIcons.new()
	ic.kind = "spell:" + sid
	ic.dim = not on
	ic.set_anchors_preset(Control.PRESET_FULL_RECT)
	ic.offset_left = 4
	ic.offset_top = 4
	ic.offset_right = -4
	ic.offset_bottom = -4
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(ic)
	var tip := "%s\n%s" % [UiText.name_of(sp.get("name", {"ko": sid, "en": sid})), UiText.t("spell_level_n") % int(sp.get("level", 0)) if int(sp.get("level", 0)) > 0 else UiText.t("cantrips")]
	if bool(sp.get("cast", {}).get("ritual", false)):
		tip += " · " + UiText.t("ritual")
	p.tooltip_text = tip
	if toggles:
		p.pressed.connect(func() -> void:
			var r: Dictionary = SpellPrep.toggle(world, c, sid)
			_rebuild("" if r.get("ok", false) else UiText.reason(str(r.get("reason", ""))))
			changed.emit())
	return p


func _scrolls() -> void:
	body.add_child(S.title(UiText.t("learn_scrolls"), 15))
	var any := false
	for item: String in creature.inventory:
		var e := RulesDB.get_entry("item", item)
		if e.get("category", "") != "scroll" or int(creature.inventory[item]) <= 0:
			continue
		var sid := str(e.get("spell", ""))
		var sp := RulesDB.get_entry("spell", sid)
		if sp.is_empty() or int(sp.get("level", 0)) < 1:
			continue
		any = true
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.text = UiText.t("learn_btn") % [UiText.name_of(sp["name"]), SpellPrep.learn_cost(sid)]
		var why := SpellPrep.learn_blocked(world, creature, item)
		b.disabled = why != ""
		b.tooltip_text = UiText.reason(why)
		b.pressed.connect(func() -> void:
			var r: Dictionary = SpellPrep.learn_from_scroll(world, creature, item)
			_rebuild("" if r.get("ok", false) else UiText.reason(str(r.get("reason", ""))))
			changed.emit())
		body.add_child(b)
	if not any:
		var l := Label.new()
		l.text = UiText.t("no_scrolls")
		l.add_theme_color_override("font_color", S.TEXT_DIM)
		body.add_child(l)
