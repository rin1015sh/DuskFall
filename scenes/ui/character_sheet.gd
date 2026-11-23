extends Control
## 캐릭터·소지품 창(BG3 인벤토리 화면 배치, 표현 계층): 위 파티 탭 | 왼쪽 능력치·상태·특성 | 가운데 장비 칸(머리·망토·갑옷·장갑·신발 /
## 목걸이·반지 2 / 근접·원거리 주·보조)과 전신 | 오른쪽 캐릭터 소지품 칸·금화·무게(캠프에서는 캠프 보관함).
## 소지품 칸을 누르면 메뉴(장착·사용·넘기기·캠프로 보내기), 장비 칸을 누르면 벗기. 끌어다 놓기: 소지품 → 장비 칸(장착),
## 장비 칸 → 소지품(벗기), 소지품 → 파티 탭(넘기기). 규칙은 equipment.gd·interact.gd가 정하고 이 창은 결과를 그린다.

signal changed
signal select_requested(c: Node)

const S := preload("res://scenes/ui/ui_style.gd")
const UiText := preload("res://scenes/ui/ui_text.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Equipment := preload("res://scripts/rules/equipment.gd")
const Interact := preload("res://scripts/rules/interact.gd")
const Actions := preload("res://scripts/rules/actions.gd")
const ABIL := ["str", "dex", "con", "int", "wis", "cha"]
const ABIL_KO := {"str": "근력", "dex": "민첩", "con": "건강", "int": "지능", "wis": "지혜", "cha": "매력"}
const ABIL_EN := {"str": "STR", "dex": "DEX", "con": "CON", "int": "INT", "wis": "WIS", "cha": "CHA"}
const RARITY_COLOR := {"common": Color(0.30, 0.23, 0.14), "uncommon": Color("4d6e43"), "rare": Color("3f5f86"),
	"very_rare": Color("6b4a86"), "legendary": Color("8a6a2a")}

var frame: Control
var root_box: VBoxContainer
var tabs: HBoxContainer
var body: HBoxContainer
var note: Label
var menu: PopupMenu
var world: Dictionary = {}
var creature: Node
var show_stash := false
var _menu_actions: Array = []


func _ready() -> void:
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -490
	offset_right = 490
	offset_top = -300
	offset_bottom = 260
	frame = S.OrnateFrame.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.radius = 18
	frame.fill = S.BG_DEEP
	add_child(frame)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	root_box = VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 8)
	margin.add_child(root_box)
	tabs = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	root_box.add_child(tabs)
	body = HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(body)
	note = Label.new()
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color(0.9, 0.5, 0.4))
	root_box.add_child(note)
	menu = PopupMenu.new()
	menu.id_pressed.connect(_on_menu)
	add_child(menu)
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


func show_for(w: Dictionary, c: Node, message: String = "") -> void:
	world = w
	creature = c
	for ch in body.get_children():
		ch.queue_free()
	for ch in tabs.get_children():
		ch.queue_free()
	if c == null:
		return
	if not world.get("at_camp", false):
		show_stash = false
	_build_tabs()
	body.add_child(_left(c))
	body.add_child(_center(c))
	body.add_child(_right(c))
	note.text = message
	visible = true


func _refresh(message: String = "") -> void:
	show_for(world, creature, message)
	changed.emit()


## 위 파티 탭(BG3 초상 줄): 누르면 그 캐릭터로, 소지품을 끌어다 놓으면 넘기기.
func _build_tabs() -> void:
	for p: Node in Interact.party_members(world):
		var t := ItemSlot.new()
		t.sheet = self
		t.kind = "member"
		t.member = p
		t.custom_minimum_size = Vector2(44, 44)
		t.add_theme_stylebox_override("panel", S.slot(S.GOLD if p == creature else S.BRONZE_DARK, p == creature))
		var tr := TextureRect.new()
		tr.texture = S.portrait_tex(p)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.add_child(tr)
		t.tooltip_text = p.label()
		tabs.add_child(t)


func _left(c: Node) -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(230, 0)
	v.add_theme_constant_override("separation", 6)
	var cls := RulesDB.get_entry("class", c.class_id)
	var sp := RulesDB.get_entry("species", c.species_id)
	v.add_child(S.title(c.label(), 22))
	var sub := Label.new()
	var cls_text := UiText.name_of(cls.get("name", {"ko": "", "en": ""}))
	if c.class_levels.size() > 1:
		var parts: Array = []
		for k: String in c.class_levels:
			parts.append("%s %d" % [UiText.name_of(RulesDB.get_entry("class", k).get("name", {"ko": k, "en": k})), int(c.class_levels[k])])
		cls_text = " / ".join(parts)  # 멀티클래스: 전사 3 / 로그 2
	sub.text = "%d%s %s · %s" % [c.level, UiText.t("lv"), cls_text, UiText.name_of(sp.get("name", {"ko": "", "en": ""}))]
	sub.add_theme_color_override("font_color", S.TEXT_DIM)
	v.add_child(sub)
	v.add_child(_rule())
	var g := GridContainer.new()
	g.columns = 6
	g.add_theme_constant_override("h_separation", 6)
	for a: String in ABIL:
		var l := Label.new()
		l.text = ABIL_KO[a] if UiText.lang == "ko" else ABIL_EN[a]
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", S.TEXT_DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		g.add_child(l)
	for a: String in ABIL:
		var l := Label.new()
		l.text = str(int(c.abilities[a]))
		l.add_theme_font_override("font", S.title_font())
		l.add_theme_font_size_override("font_size", 20)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.tooltip_text = "%+d" % c.ability_mod(a)
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		g.add_child(l)
	v.add_child(g)
	v.add_child(_rule())
	v.add_child(S.title(UiText.t("conditions"), 15))
	var conds := Label.new()
	conds.text = ", ".join(c.conditions.map(func(i: Dictionary) -> String: return i["id"])) if not c.conditions.is_empty() else UiText.t("none")
	conds.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(conds)
	v.add_child(S.title(UiText.t("features"), 15))
	var feats := Label.new()
	var names: Array = []
	for fid: String in c.feature_data:
		names.append(UiText.name_of(c.feature_data[fid].get("name", {"ko": fid, "en": fid})))
	feats.text = " · ".join(names.slice(0, 12))
	feats.autowrap_mode = TextServer.AUTOWRAP_WORD
	feats.add_theme_font_size_override("font_size", 12)
	feats.add_theme_color_override("font_color", S.TEXT_DIM)
	v.add_child(feats)
	return v


func _center(c: Node) -> Control:
	# BG3 배치: 왼쪽 열 머리·망토·갑옷·장갑·신발, 가운데 전신, 오른쪽 열 목걸이·반지 2, 아래 근접 주/보조 · 방어도 · 원거리 주/보조
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(300, 0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 8)
	var mid := HBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 6)
	v.add_child(mid)
	var lcol := VBoxContainer.new()
	lcol.add_theme_constant_override("separation", 4)
	for slot: String in ["head", "cloak", "armor", "hands", "feet"]:
		lcol.add_child(_equip_slot(c, slot))
	mid.add_child(lcol)
	var fig := TextureRect.new()
	fig.texture = S.portrait_tex(c, Rect2(144, 0, 72, 108))
	fig.custom_minimum_size = Vector2(170, 270)
	fig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fig.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mid.add_child(fig)
	var rcol := VBoxContainer.new()
	rcol.add_theme_constant_override("separation", 4)
	for slot: String in ["amulet", "ring1", "ring2"]:
		rcol.add_child(_equip_slot(c, slot))
	mid.add_child(rcol)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	row.add_child(_equip_slot(c, "melee_main"))
	row.add_child(_equip_slot(c, "melee_off"))
	var ac := ACBadge.new()
	ac.value = c.ac()
	ac.custom_minimum_size = Vector2(56, 64)
	ac.tooltip_text = UiText.t("armor_class")
	row.add_child(ac)
	row.add_child(_equip_slot(c, "ranged_main"))
	row.add_child(_equip_slot(c, "ranged_off"))
	var atk := Label.new()
	atk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	atk.add_theme_font_size_override("font_size", 12)
	atk.add_theme_color_override("font_color", S.TEXT_DIM)
	var parts: Array = []
	for set_name: String in ["melee", "ranged"]:
		var wid: String = c.weapon_sets.get(set_name, {}).get("main", "")
		if wid != "":
			var a: Dictionary = Combat.build_weapon_attack(c, wid)
			parts.append("%s %+d · %s" % [UiText.t("set_" + set_name), int(a["bonus"]), a["damage"][0]["dice"]])
	atk.text = "   ".join(parts)
	v.add_child(atk)
	return v


## 장비 칸: 비면 칸 이름, 차 있으면 그림. 누르면 벗기, 소지품에서 끌어다 놓으면 장착.
func _equip_slot(c: Node, slot: String) -> Control:
	var id := str(c.equipment.get(slot, ""))
	var p := ItemSlot.new()
	p.sheet = self
	p.kind = "slot"
	p.slot = slot
	p.item = id
	p.custom_minimum_size = Vector2(46, 46)
	p.add_theme_stylebox_override("panel", S.slot(_rarity_color(id) if id != "" else S.BRONZE_DARK))
	if id != "":
		p.add_child(_icon(id))
		p.tooltip_text = "%s\n%s" % [UiText.t("slot_" + slot), _tooltip(id)]
	else:
		var l := Label.new()
		l.text = UiText.t("short_" + slot)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 10)
		l.add_theme_color_override("font_color", Color(S.TEXT_DIM, 0.6))
		p.add_child(l)
		p.tooltip_text = "%s — %s" % [UiText.t("slot_" + slot), UiText.t("empty_slot")]
	return p


func _right(c: Node) -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(330, 0)
	v.add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	head.add_child(S.title(UiText.t("camp_stash") if show_stash else UiText.t("inventory"), 18))
	var gold := Label.new()
	gold.text = "   %s %d" % [UiText.t("gold"), Interact.count(world, "gold", c)]
	gold.add_theme_color_override("font_color", S.GOLD)
	gold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gold)
	if world.get("at_camp", false):
		var sb := Button.new()
		sb.text = UiText.t("inventory") if show_stash else UiText.t("camp_stash")
		sb.focus_mode = Control.FOCUS_NONE
		sb.pressed.connect(func() -> void:
			show_stash = not show_stash
			show_for(world, creature))
		head.add_child(sb)
	v.add_child(head)
	var grid := ItemSlot.new()  # 칸 묶음 전체가 놓을 곳(장비 칸 → 소지품 = 벗기)
	grid.sheet = self
	grid.kind = "inventory"
	grid.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var g := GridContainer.new()
	g.columns = 6
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	grid.add_child(g)
	v.add_child(grid)
	var bag: Dictionary = world.get("stash", {}) if show_stash else c.inventory
	var shown := 0
	var keys: Array = bag.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return _order(a) < _order(b))
	for item: String in keys:
		var n := int(bag[item])
		if n <= 0 or (item == "gold" and not show_stash):
			continue
		g.add_child(_item_slot(item, n, "stash" if show_stash else "inv"))
		shown += 1
	for i in range(shown, 36):
		var empty := PanelContainer.new()
		empty.custom_minimum_size = Vector2(48, 48)
		empty.add_theme_stylebox_override("panel", S.slot())
		empty.mouse_filter = Control.MOUSE_FILTER_PASS
		g.add_child(empty)
	var cap := Interact.capacity_kg(c)
	var kg := Interact.carried_kg(c)
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 8)
	var wl := Label.new()
	wl.text = "%s %.1f / %.0f kg" % [UiText.t("weight"), kg, cap]
	wl.add_theme_font_size_override("font_size", 12)
	if kg > cap:
		wl.add_theme_color_override("font_color", Color(0.9, 0.45, 0.35))  # 짐 매우 무거움
	elif kg > Interact.load_limit_kg(c, "encumbered"):
		wl.add_theme_color_override("font_color", Color(0.9, 0.7, 0.35))  # 짐 무거움
	wl.tooltip_text = "%s > %.0f kg · %s > %.0f kg" % [UiText.name_of(RulesDB.get_entry("condition", "encumbered")["name"]), Interact.load_limit_kg(c, "encumbered"),
		UiText.name_of(RulesDB.get_entry("condition", "heavily_encumbered")["name"]), cap]
	wl.mouse_filter = Control.MOUSE_FILTER_PASS
	wrow.add_child(wl)
	var wb := S.bar(S.GOLD_SOFT, Vector2(150, 8))
	wb.max_value = cap
	wb.value = minf(kg, cap)
	wb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrow.add_child(wb)
	v.add_child(wrow)
	return v


## 소지품 정렬: 장비 → 물약·두루마리 → 나머지(이름순)
func _order(item: String) -> String:
	var k := Equipment.kind_of(item)
	var cat := str(RulesDB.get_entry("item", item).get("category", ""))
	var rank := "0" if k != "" else ("1" if cat in ["potion", "scroll"] else "2")
	return rank + UiText.name_of(Equipment.entry(item).get("name", {"ko": item, "en": item}))


func _item_slot(item: String, n: int, where: String) -> Control:
	var p := ItemSlot.new()
	p.sheet = self
	p.kind = where
	p.item = item
	p.custom_minimum_size = Vector2(48, 48)
	p.add_theme_stylebox_override("panel", S.slot(_rarity_color(item)))
	p.add_child(_icon(item))
	if n > 1:
		var l := Label.new()
		l.text = str(n)
		l.add_theme_font_size_override("font_size", 11)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 4)
		l.size_flags_horizontal = Control.SIZE_SHRINK_END
		l.size_flags_vertical = Control.SIZE_SHRINK_END
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(l)
	p.tooltip_text = _tooltip(item) + ("" if n <= 1 else " ×%d" % n)
	return p


## 아이템 그림: 데이터 icon(assets/items/<icon>.webp), 마법 변형은 바탕 그림, 없으면 상자.
func _icon(item: String) -> TextureRect:
	var e := Equipment.entry(item)
	var ic := str(e.get("icon", Equipment.entry(Equipment.base_of(item)).get("icon", "")))
	var path := "res://assets/items/%s.webp" % ic
	var tr := TextureRect.new()
	tr.texture = load(path) if ic != "" and ResourceLoader.exists(path) else load("res://assets/items/ration.webp")
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.material = S.icon_material()
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func _rarity_color(item: String) -> Color:
	return RARITY_COLOR.get(str(Equipment.entry(item).get("rarity", "common")), RARITY_COLOR["common"])


## 툴팁: 이름·희귀도, 무기 피해·갑옷 방어도, 마법 보너스·착용 효과, 무게·값.
func _tooltip(item: String) -> String:
	var e := Equipment.entry(item)
	var lines: Array = [UiText.name_of(e.get("name", {"ko": item, "en": item}))]
	if e.has("rarity") and str(e["rarity"]) != "common":
		lines[0] += "  (%s)" % UiText.t("rarity_" + str(e["rarity"]))
	var base := Equipment.base_of(item)
	var k := Equipment.kind_of(item)
	if k == "weapon":
		var w := RulesDB.get_entry("weapon", base)
		var bonus := int(e.get("bonus", 0))
		lines.append(UiText.t("tip_weapon") % ["%s%s" % [w["damage"], "%+d" % bonus if bonus != 0 else ""], w["damage_type"]])
	elif k in ["armor", "shield"]:
		lines.append(UiText.t("tip_armor") % (int(RulesDB.get_entry("armor", base)["ac_base"]) + int(e.get("bonus", 0))))
	var eq: Dictionary = e.get("equip", {})
	if int(eq.get("ac", 0)) != 0:
		lines.append(UiText.t("tip_ac") % int(eq["ac"]) + (" " + UiText.t("tip_no_armor") if eq.get("requires", {}).get("no_armor", false) else ""))
	if int(eq.get("saves", 0)) != 0:
		lines.append(UiText.t("tip_saves") % int(eq["saves"]))
	for a: String in eq.get("ability_min", {}):
		lines.append(UiText.t("tip_min") % [ABIL_KO[a] if UiText.lang == "ko" else ABIL_EN[a], int(eq["ability_min"][a])])
	for adv: Dictionary in eq.get("advantage", []):
		lines.append(UiText.t("tip_adv") % ", ".join(adv.get("skill", [adv.get("roll", "")])))
	for cap: String in eq.get("caps", []):
		lines.append(UiText.t("tip_cap") % UiText.name_of(RulesDB.get_entry("capability", cap).get("name", {"ko": cap, "en": cap})))
	lines.append(UiText.t("tip_weight") % [float(e.get("weight_kg", 0.0)), int(e.get("price_gp", 0))])
	return "\n".join(lines)


# ---------- 메뉴·끌어다 놓기 ----------

## 칸을 눌렀을 때 메뉴를 연다.
func open_menu(src: ItemSlot) -> void:
	menu.clear()
	_menu_actions.clear()
	var c := creature
	if src.kind == "slot":
		if src.item == "":
			return
		_add_menu(UiText.t("unequip"), func() -> Dictionary: return Equipment.unequip(world, c, src.slot))
	elif src.kind == "inv":
		if Equipment.kind_of(src.item) != "":
			_add_menu(UiText.t("equip"), func() -> Dictionary: return Equipment.equip(world, c, src.item))
		for key: String in Actions.list_for(world, c, true)["items"]:
			if key.ends_with(":" + src.item) and (key.begins_with("drink:") or key.begins_with("read_scroll:")):
				_add_menu(UiText.t("use_item"), func() -> Dictionary:
					return Actions.execute(world, c, key, world["grid"].cell_of(c)) if world.has("grid") else {"ok": false})
				break
		for p: Node in Interact.party_members(world):
			if p != c:
				_add_menu(UiText.t("give_to") % p.label(), func() -> Dictionary:
					return {"ok": Interact.transfer(world, c, p, src.item)})
		_add_menu(UiText.t("send_camp"), func() -> Dictionary: return {"ok": Interact.send_to_stash(world, c, src.item)})
	elif src.kind == "stash":
		_add_menu(UiText.t("take_out"), func() -> Dictionary: return {"ok": Interact.take_from_stash(world, c, src.item)})
	if _menu_actions.is_empty():
		return
	menu.position = Vector2i(get_global_mouse_position()) + Vector2i(get_window().position)
	menu.popup()


func _add_menu(label: String, f: Callable) -> void:
	menu.add_item(label, _menu_actions.size())
	_menu_actions.append(f)


func _on_menu(id: int) -> void:
	if id >= 0 and id < _menu_actions.size():
		_apply(_menu_actions[id].call())


func _apply(r: Dictionary) -> void:
	_refresh("" if r.get("ok", false) else UiText.reason(str(r.get("reason", ""))))


## 끌어다 놓기 결과.
func drop(src: Dictionary, dst: ItemSlot) -> void:
	var c := creature
	match dst.kind:
		"slot":
			if src["kind"] == "inv":
				_apply(Equipment.equip(world, c, src["item"], dst.slot))
		"inventory", "inv":
			if src["kind"] == "slot":
				_apply(Equipment.unequip(world, c, src["slot"]))
			elif src["kind"] == "stash":
				_apply({"ok": Interact.take_from_stash(world, c, src["item"])})
		"member":
			if src["kind"] == "inv" and dst.member != c:
				_apply({"ok": Interact.transfer(world, c, dst.member, src["item"])})


func _rule() -> Control:
	var r := ColorRect.new()
	r.color = Color(S.BRONZE, 0.5)
	r.custom_minimum_size = Vector2(0, 1)
	return r


## 칸 하나(소지품·장비·파티 탭·소지품 묶음): 누르면 메뉴, 끌기·놓기를 창에 넘긴다.
class ItemSlot extends PanelContainer:
	var sheet: Control
	var kind := ""  # inv · stash · slot · member · inventory
	var item := ""
	var slot := ""
	var member: Node

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			if kind == "member":
				sheet.select_requested.emit(member)
				sheet.show_for(sheet.world, member)
			elif kind in ["inv", "stash", "slot"]:
				sheet.open_menu(self)
			accept_event()

	func _get_drag_data(_at: Vector2) -> Variant:
		if not kind in ["inv", "stash", "slot"] or item == "":
			return null
		var prev := TextureRect.new()
		prev.texture = get_child(0).texture if get_child_count() > 0 and get_child(0) is TextureRect else null
		prev.custom_minimum_size = Vector2(40, 40)
		prev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		set_drag_preview(prev)
		return {"kind": kind, "item": item, "slot": slot}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		if not data is Dictionary:
			return false
		match kind:
			"slot":
				return data["kind"] == "inv" and slot in sheet.Equipment.slots_for(data["item"])
			"inventory", "inv":
				return data["kind"] in ["slot", "stash"]
			"member":
				return data["kind"] == "inv"
		return false

	func _drop_data(_at: Vector2, data: Variant) -> void:
		sheet.drop(data, self)


## 방어도 방패 배지
class ACBadge extends Control:
	var value := 10

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var pts := PackedVector2Array([Vector2(w * 0.5, 2), Vector2(w - 4, h * 0.18), Vector2(w - 8, h * 0.62),
			Vector2(w * 0.5, h - 2), Vector2(8, h * 0.62), Vector2(4, h * 0.18)])
		draw_colored_polygon(pts, S.BG_SLOT)
		draw_polyline(pts + PackedVector2Array([pts[0]]), S.GOLD_SOFT, 2.0, true)
		draw_string(S.title_font(), Vector2(0, h * 0.58), str(value), HORIZONTAL_ALIGNMENT_CENTER, w, 26, S.TEXT)
