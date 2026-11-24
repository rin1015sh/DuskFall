extends Control
## 캐릭터·소지품 창(BG3 인벤토리 화면 배치, 표현 계층): 위 파티 탭 | 왼쪽 능력치·상태·특성 | 가운데 장비 칸(머리·망토·갑옷·장갑·신발 /
## 목걸이·반지 2 / 근접·원거리 주·보조)과 전신 | 오른쪽 캐릭터 소지품 칸·금화·무게(캠프에서는 캠프 보관함).
## 소지품 칸을 누르면 메뉴(장착·사용·넘기기·캠프로 보내기), 장비 칸을 누르면 벗기. 끌어다 놓기: 소지품 → 장비 칸(장착),
## 장비 칸 → 소지품(벗기), 소지품 → 파티 탭(넘기기). 규칙은 equipment.gd·interact.gd가 정하고 이 창은 결과를 그린다.

signal changed
signal select_requested(c: Node)
signal spellbook_requested(c: Node)

const S := preload("res://scenes/ui/ui_style.gd")
const UiText := preload("res://scenes/ui/ui_text.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Equipment := preload("res://scripts/rules/equipment.gd")
const Interact := preload("res://scripts/rules/interact.gd")
const Actions := preload("res://scripts/rules/actions.gd")
const DiceExpr := preload("res://scripts/rules/dice_expr.gd")
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
## 보기: "character"(한 명 — BG3 캐릭터 창) | "party"(파티원 나란히 — BG3 파티 소지품)
var view_mode := "character"
## 소지품 검색어·정렬(최신·가치·무게·유형 — BG3 정렬 메뉴)
var search := ""
var sort_key := "recent"
## 메뉴를 연 칸의 주인(파티 보기에서 다른 파티원 칸)
var _menu_owner: Node
const DAMAGE_KO := {"acid": "산", "bludgeoning": "타격", "cold": "냉기", "fire": "화염", "force": "역장", "lightning": "번개", "necrotic": "사령",
	"piercing": "관통", "poison": "독", "psychic": "정신", "radiant": "광휘", "slashing": "참격", "thunder": "천둥", "all": "모든 피해"}


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
	_resize()
	_build_tabs()
	if view_mode == "party":
		for p: Node in Interact.party_members(world):
			body.add_child(_member_column(p))
	else:
		body.add_child(_left(c))
		body.add_child(_center(c))
		body.add_child(_right(c))
	note.text = message
	visible = true


## 파티 보기는 넓게(파티원 넷 나란히).
func _resize() -> void:
	var half := 620 if view_mode == "party" else 490
	offset_left = -half
	offset_right = half


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
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(gap)
	# BG3 위 탭: 소지품(파티) · 캐릭터 · 주문서(K)
	for m: Array in [["party", "tab_party_inventory"], ["character", "tab_character"], ["spellbook", "tab_spellbook"]]:
		var b := Button.new()
		b.text = UiText.t(m[1])
		b.toggle_mode = true
		b.button_pressed = view_mode == m[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 36)
		var mode_id: String = m[0]
		b.pressed.connect(func() -> void:
			if mode_id == "spellbook":
				spellbook_requested.emit(creature)
				return
			view_mode = mode_id
			show_for(world, creature))
		tabs.add_child(b)
	var info := Label.new()
	var lv: int = creature.level if creature != null else 1
	var cap: int = int(RulesDB.get_entry("progression", "standard").get("level_cap", 12))
	info.text = "   %s   %s %d" % [UiText.t("max_level") if lv >= cap else UiText.t("xp_line") % int(world.get("xp", 0)),
		UiText.t("gold"), Interact.count(world, "gold", creature)]
	info.add_theme_color_override("font_color", S.GOLD)
	tabs.add_child(info)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(40, 0)  # 닫기 버튼 자리
	tabs.add_child(spacer)


func _left(c: Node) -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(230, 0)
	v.add_theme_constant_override("separation", 6)
	var cls := RulesDB.get_entry("class", c.class_id)
	var sp := RulesDB.get_entry("species", c.species_id)
	v.add_child(S.title(c.label(), 22))
	var sub := Label.new()
	var cls_text := UiText.name_of(cls.get("name", {"ko": "", "en": ""}))
	var parts: Array = []
	for k: String in c.class_levels:
		parts.append(UiText.t("class_level") % [int(c.class_levels[k]), UiText.name_of(RulesDB.get_entry("class", k).get("name", {"ko": k, "en": k}))])
	if parts.is_empty():
		parts.append(UiText.t("class_level") % [c.level, cls_text])
	sub.text = "%s\n%s" % [UiText.name_of(sp.get("name", {"ko": "", "en": ""})), " / ".join(parts)]  # BG3: 5레벨 파이터 / 5레벨 바드
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD
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
	var conds := HFlowContainer.new()
	conds.add_theme_constant_override("h_separation", 4)
	conds.add_theme_constant_override("v_separation", 4)
	var seen := {}
	for ci: Dictionary in c.conditions:
		if seen.has(ci["id"]):
			continue
		seen[ci["id"]] = true
		var cd := RulesDB.get_entry("condition", str(ci["id"]))
		conds.add_child(_chip(UiText.name_of(cd.get("name", {"ko": ci["id"], "en": ci["id"]})), str(cd.get("notes_ko", ""))))
	if seen.is_empty():
		conds.add_child(_chip(UiText.t("none"), ""))
	v.add_child(conds)
	v.add_child(S.title(UiText.t("resistances"), 15))
	var res := Label.new()
	var rl: Array = []
	for dt: String in c._damage_list("damage_resistance", c.damage_resistances):
		var nm: String = DAMAGE_KO.get(dt, dt) if UiText.lang == "ko" else dt
		if not nm in rl:
			rl.append(nm)
	for dt: String in c._damage_list("damage_immunity", c.damage_immunities):
		rl.append("%s(%s)" % [DAMAGE_KO.get(dt, dt) if UiText.lang == "ko" else dt, UiText.t("immune")])
	res.text = ", ".join(rl) if not rl.is_empty() else UiText.t("none")
	res.autowrap_mode = TextServer.AUTOWRAP_WORD
	res.add_theme_font_size_override("font_size", 13)
	v.add_child(res)
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
	v.add_child(_weapon_stats(c, 46))
	return v


## BG3: 무기 칸 아래 무기마다 명중 보너스와 피해 범위(근거리 주·보조 | 공격 보너스·피해 | 원거리 주·보조).
func _weapon_stats(c: Node, w: int) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	for cdef: Array in [["melee", "main"], ["melee", "off"], [], ["ranged", "main"], ["ranged", "off"]]:
		var l := Label.new()
		l.custom_minimum_size = Vector2(w if not cdef.is_empty() else 56, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 12)
		if cdef.is_empty():
			l.text = "%s\n%s" % [UiText.t("attack_bonus"), UiText.t("damage")]
			l.add_theme_color_override("font_color", S.TEXT_DIM)
			l.add_theme_font_size_override("font_size", 10)
		else:
			var wid: String = c.weapon_sets.get(cdef[0], {}).get(cdef[1], "")
			if wid != "" and Combat.weapon_data(wid).has("damage"):
				var a: Dictionary = Combat.build_weapon_attack(c, wid, {"hand": "off"} if cdef[1] == "off" else {})
				var st := DiceExpr.stats(str(a["damage"][0]["dice"]))
				l.text = "%+d\n%d~%d" % [int(a["bonus"]), int(st["min"]), int(st["max"])]
		row.add_child(l)
	return row


## 장비 칸: 비면 칸 이름, 차 있으면 그림. 누르면 벗기, 소지품에서 끌어다 놓으면 장착.
func _equip_slot(c: Node, slot: String, size_px: int = 46) -> Control:
	var id := str(c.equipment.get(slot, ""))
	var p := ItemSlot.new()
	p.sheet = self
	p.kind = "slot"
	p.slot = slot
	p.item = id
	p.member = c
	p.custom_minimum_size = Vector2(size_px, size_px)
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
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(fill)  # 골드는 위 탭 줄에(BG3)
	if world.get("at_camp", false):
		var sb := Button.new()
		sb.text = UiText.t("inventory") if show_stash else UiText.t("camp_stash")
		sb.focus_mode = Control.FOCUS_NONE
		sb.pressed.connect(func() -> void:
			show_stash = not show_stash
			show_for(world, creature))
		head.add_child(sb)
	v.add_child(head)
	v.add_child(_search_row())
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
	for item: String in _sorted_items(bag, not show_stash):
		g.add_child(_item_slot(item, int(bag[item]), "stash" if show_stash else "inv", c))
		shown += 1
	for i in range(shown, 36):
		var empty := PanelContainer.new()
		empty.custom_minimum_size = Vector2(48, 48)
		empty.add_theme_stylebox_override("panel", S.slot())
		empty.mouse_filter = Control.MOUSE_FILTER_PASS
		g.add_child(empty)
	v.add_child(_weight_row(c, 200))
	return v


## 검색창과 정렬 메뉴(BG3: 모두 표시 · 최신·가치·무게·유형). iPad: 누르기만으로 쓴다.
func _search_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var le := LineEdit.new()
	le.placeholder_text = UiText.t("search_all")
	le.text = search
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.custom_minimum_size = Vector2(0, 34)
	le.text_submitted.connect(func(t: String) -> void:
		search = t
		show_for(world, creature))
	le.text_changed.connect(func(t: String) -> void:
		search = t)
	row.add_child(le)
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.custom_minimum_size = Vector2(0, 34)
	var keys := ["recent", "value", "weight", "type"]
	for i in keys.size():
		ob.add_item(UiText.t("sort_" + keys[i]), i)
	ob.selected = keys.find(sort_key)
	ob.item_selected.connect(func(i: int) -> void:
		sort_key = keys[i]
		show_for(world, creature))
	row.add_child(ob)
	return row


## 보이는 아이템(검색어로 거르고 정렬). recent = 얻은 순서의 역순(사전 순서 — 새로 얻은 것이 앞).
func _sorted_items(bag: Dictionary, hide_gold: bool) -> Array:
	var items: Array = []
	for item: String in bag.keys():
		if int(bag[item]) <= 0 or (item == "gold" and hide_gold):
			continue
		if search != "":
			var nm := UiText.name_of(Equipment.entry(item).get("name", {"ko": item, "en": item})).to_lower()
			if not search.to_lower() in nm and not search.to_lower() in item:
				continue
		items.append(item)
	match sort_key:
		"recent":
			items.reverse()
		"value":
			items.sort_custom(func(a: String, b: String) -> bool: return float(Equipment.entry(a).get("price_gp", 0)) > float(Equipment.entry(b).get("price_gp", 0)))
		"weight":
			items.sort_custom(func(a: String, b: String) -> bool: return float(Equipment.entry(a).get("weight_kg", 0)) > float(Equipment.entry(b).get("weight_kg", 0)))
		_:
			items.sort_custom(func(a: String, b: String) -> bool: return _order(a) < _order(b))
	return items


## 소지품 정렬(유형): 장비 → 물약·두루마리 → 나머지(이름순)
func _order(item: String) -> String:
	var k := Equipment.kind_of(item)
	var cat := str(RulesDB.get_entry("item", item).get("category", ""))
	var rank := "0" if k != "" else ("1" if cat in ["potion", "scroll"] else "2")
	return rank + UiText.name_of(Equipment.entry(item).get("name", {"ko": item, "en": item}))


func _item_slot(item: String, n: int, where: String, owner_c: Node = null, size_px: int = 48) -> Control:
	var p := ItemSlot.new()
	p.sheet = self
	p.kind = where
	p.item = item
	p.member = owner_c
	p.custom_minimum_size = Vector2(size_px, size_px)
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
	var c: Node = src.member if src.member != null else creature  # 파티 보기: 그 칸 주인
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
	var c: Node = dst.member if dst.member != null and dst.kind != "member" else creature  # 놓은 칸의 주인
	var from: Node = src.get("owner", creature)
	match dst.kind:
		"slot":
			if src["kind"] == "inv":
				if from != c:
					if not Interact.transfer(world, from, c, src["item"]):
						return
				_apply(Equipment.equip(world, c, src["item"], dst.slot))
		"inventory", "inv":
			if src["kind"] == "slot" and from == c:
				_apply(Equipment.unequip(world, c, src["slot"]))
			elif src["kind"] == "stash":
				_apply({"ok": Interact.take_from_stash(world, c, src["item"])})
			elif src["kind"] == "inv" and from != c:
				_apply({"ok": Interact.transfer(world, from, c, src["item"])})  # 파티 보기: 다른 사람 칸으로 넘기기
		"member":
			if src["kind"] == "inv" and dst.member != from:
				_apply({"ok": Interact.transfer(world, from, dst.member, src["item"])})


## 파티 보기의 한 사람 열(BG3 파티 소지품): 이름·레벨, 장비 칸, 방어도·무기별 명중/피해, 작은 소지품 칸, 무게 막대.
## 다른 열의 소지품 칸으로 끌어다 놓으면 넘기기(누르면 메뉴 — 넘기기).
func _member_column(p: Node) -> Control:
	var col := PanelContainer.new()
	var sb := S.panel(12, S.GOLD if p == creature else S.BRONZE_DARK, S.BG, 1 if p != creature else 2)
	sb.set_content_margin_all(8)
	col.add_theme_stylebox_override("panel", sb)
	col.custom_minimum_size = Vector2(286, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	col.add_child(v)
	var name_l := S.title("%s  %s" % [p.label(), UiText.t("level_short") % p.level], 17)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_l)
	var mid := HBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 4)
	v.add_child(mid)
	var lc := VBoxContainer.new()
	lc.add_theme_constant_override("separation", 3)
	for slot: String in ["head", "cloak", "armor", "hands", "feet"]:
		lc.add_child(_equip_slot(p, slot, 34))
	mid.add_child(lc)
	var fig := TextureRect.new()
	fig.texture = S.portrait_tex(p, Rect2(144, 0, 72, 108))
	fig.custom_minimum_size = Vector2(110, 180)
	fig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fig.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mid.add_child(fig)
	var rc := VBoxContainer.new()
	rc.add_theme_constant_override("separation", 3)
	for slot: String in ["amulet", "ring1", "ring2"]:
		rc.add_child(_equip_slot(p, slot, 34))
	mid.add_child(rc)
	var wrow := HBoxContainer.new()
	wrow.alignment = BoxContainer.ALIGNMENT_CENTER
	wrow.add_theme_constant_override("separation", 4)
	wrow.add_child(_equip_slot(p, "melee_main", 34))
	wrow.add_child(_equip_slot(p, "melee_off", 34))
	var ac := ACBadge.new()
	ac.value = p.ac()
	ac.custom_minimum_size = Vector2(48, 54)
	wrow.add_child(ac)
	wrow.add_child(_equip_slot(p, "ranged_main", 34))
	wrow.add_child(_equip_slot(p, "ranged_off", 34))
	v.add_child(wrow)
	v.add_child(_weapon_stats(p, 34))
	var grid := ItemSlot.new()
	grid.sheet = self
	grid.kind = "inventory"
	grid.member = p
	grid.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var g := GridContainer.new()
	g.columns = 7
	g.add_theme_constant_override("h_separation", 3)
	g.add_theme_constant_override("v_separation", 3)
	grid.add_child(g)
	v.add_child(grid)
	var shown := 0
	for item: String in _sorted_items(p.inventory, true):
		g.add_child(_item_slot(item, int(p.inventory[item]), "inv", p, 36))
		shown += 1
	for i in range(shown, 21):
		var empty := PanelContainer.new()
		empty.custom_minimum_size = Vector2(36, 36)
		empty.add_theme_stylebox_override("panel", S.slot())
		empty.mouse_filter = Control.MOUSE_FILTER_PASS
		g.add_child(empty)
	v.add_child(_weight_row(p, 170))
	return col


## 무게 막대(BG3: 막대 + 지금/한도 숫자).
func _weight_row(c: Node, bar_w: int) -> Control:
	var cap := Interact.capacity_kg(c)
	var kg := Interact.carried_kg(c)
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 6)
	var wb := S.bar(S.GOLD_SOFT, Vector2(bar_w, 8))
	wb.max_value = cap
	wb.value = minf(kg, cap)
	wb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrow.add_child(wb)
	var wl := Label.new()
	wl.text = "%.1f / %.0f kg" % [kg, cap]
	wl.add_theme_font_size_override("font_size", 12)
	if kg > cap:
		wl.add_theme_color_override("font_color", Color(0.9, 0.45, 0.35))
	elif kg > Interact.load_limit_kg(c, "encumbered"):
		wl.add_theme_color_override("font_color", Color(0.9, 0.7, 0.35))
	wrow.add_child(wl)
	return wrow


## 상태 칩(BG3 상태 목록 — 이름, 누르거나 올리면 설명).
func _chip(text: String, tip: String) -> Control:
	var p := PanelContainer.new()
	var sb := S.panel(8, S.BRONZE_DARK, S.BG_SLOT, 1)
	sb.set_content_margin_all(2)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	p.add_child(l)
	p.tooltip_text = tip
	return p


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
			if kind == "member" or (kind == "inventory" and member != null and member != sheet.creature):
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
		return {"kind": kind, "item": item, "slot": slot, "owner": member if member != null else sheet.creature}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		if not data is Dictionary:
			return false
		match kind:
			"slot":
				return data["kind"] == "inv" and slot in sheet.Equipment.slots_for(data["item"])
			"inventory", "inv":
				return data["kind"] in ["slot", "stash"] or (data["kind"] == "inv" and member != null and data.get("owner") != member)
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
