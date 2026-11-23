extends Control
## 캐릭터·소지품 창(BG3 인벤토리 화면 배치 참고, 표현 계층): 왼쪽 능력치·상태·특성 | 가운데 전신 그림·무기·방어도 | 오른쪽 소지품 칸·무게.
## 규칙 값은 생물·세계에서 읽기만 한다. I 키 또는 단축 막대의 캐릭터 버튼으로 연다.

const S := preload("res://scenes/ui/ui_style.gd")
const UiText := preload("res://scenes/ui/ui_text.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const ABIL := ["str", "dex", "con", "int", "wis", "cha"]
const ABIL_KO := {"str": "근력", "dex": "민첩", "con": "건강", "int": "지능", "wis": "지혜", "cha": "매력"}
const ABIL_EN := {"str": "STR", "dex": "DEX", "con": "CON", "int": "INT", "wis": "WIS", "cha": "CHA"}
## 아이템 → 그림(assets/items). 없으면 상자 아이콘.
const ITEM_ICON := {"potion_of_healing": "minor_potion", "potion_of_greater_healing": "medium_potion",
	"potion_of_superior_healing": "greater_potion", "potion_of_supreme_healing": "greater_potion",
	"rations": "ration", "thieves_tools": "mine_hammer", "trap_disarm_kit": "mine_powder_pouch",
	"gold": "old_gold_coin", "chest_key": "crypt_key", "raider_key": "fortress_key"}

var frame: Control
var body: HBoxContainer


func _ready() -> void:
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -450
	offset_right = 450
	offset_top = -280
	offset_bottom = 240
	frame = S.OrnateFrame.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.radius = 18
	frame.fill = S.BG_DEEP
	add_child(frame)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	add_child(margin)
	body = HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	margin.add_child(body)
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


func show_for(world: Dictionary, c: Node) -> void:
	for ch in body.get_children():
		ch.queue_free()
	if c == null:
		return
	body.add_child(_left(c))
	body.add_child(_center(c))
	body.add_child(_right(world, c))
	visible = true


func _left(c: Node) -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(230, 0)
	v.add_theme_constant_override("separation", 6)
	var cls := RulesDB.get_entry("class", c.class_id)
	var sp := RulesDB.get_entry("species", c.species_id)
	v.add_child(S.title(c.label(), 22))
	var sub := Label.new()
	sub.text = "%d%s %s · %s" % [c.level, UiText.t("lv"), UiText.name_of(cls.get("name", {"ko": "", "en": ""})), UiText.name_of(sp.get("name", {"ko": "", "en": ""}))]
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
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(260, 0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 8)
	var fig := TextureRect.new()
	fig.texture = S.portrait_tex(c, Rect2(144, 0, 72, 108))
	fig.custom_minimum_size = Vector2(200, 300)
	fig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fig.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	v.add_child(fig)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	row.add_child(_weapon_box(c, "melee"))
	var ac := ACBadge.new()
	ac.value = c.ac()
	ac.custom_minimum_size = Vector2(64, 74)
	ac.tooltip_text = UiText.t("armor_class")
	row.add_child(ac)
	row.add_child(_weapon_box(c, "ranged"))
	return v


func _weapon_box(c: Node, set_name: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var t := Label.new()
	t.text = UiText.t("set_" + set_name)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", S.TEXT_DIM)
	t.add_theme_font_size_override("font_size", 12)
	v.add_child(t)
	var wid: String = c.weapon_sets.get(set_name, {}).get("main", "")
	var slot := PanelContainer.new()
	slot.add_theme_stylebox_override("panel", S.slot(S.BRONZE, c.active_set == set_name))
	slot.custom_minimum_size = Vector2(52, 52)
	var tr := TextureRect.new()
	tr.texture = load(preload("res://scenes/ui/hotbar.gd")._weapon_icon(wid, set_name))
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.material = S.icon_material()
	slot.add_child(tr)
	slot.tooltip_text = UiText.name_of(RulesDB.get_entry("weapon", wid).get("name", {"ko": "-", "en": "-"}))
	v.add_child(slot)
	if wid != "":
		var atk: Dictionary = Combat.build_weapon_attack(c, wid)
		var lo := 0
		var hi := 0
		for part: Dictionary in atk.get("damage", []):
			var st: Dictionary = preload("res://scripts/rules/dice_expr.gd").stats(part["dice"])
			lo += int(st.get("min", 0))
			hi += int(st.get("max", 0))
		var l := Label.new()
		l.text = "%+d\n%d~%d" % [int(atk.get("bonus", 0)), lo, hi]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 13)
		l.tooltip_text = "%s / %s" % [UiText.t("attack_bonus"), UiText.t("damage")]
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		v.add_child(l)
	return v


func _right(world: Dictionary, c: Node) -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(330, 0)
	v.add_theme_constant_override("separation", 6)
	v.add_child(S.title(UiText.t("inventory"), 18))
	var g := GridContainer.new()
	g.columns = 6
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	v.add_child(g)
	var total_kg := 0.0
	var inv: Dictionary = world.get("inventory", {})
	var shown := 0
	for item: String in inv:
		var n := int(inv[item])
		if n <= 0:
			continue
		var e := RulesDB.get_entry("item", item)
		total_kg += float(e.get("weight_kg", 0.0)) * n
		g.add_child(_item_slot(item, e, n))
		shown += 1
	for i in range(shown, 36):
		var empty := PanelContainer.new()
		empty.custom_minimum_size = Vector2(48, 48)
		empty.add_theme_stylebox_override("panel", S.slot())
		g.add_child(empty)
	var cap: float = c.abilities["str"] * 6.8  # SRD 운반 한계: 근력 × 15파운드
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 8)
	var wl := Label.new()
	wl.text = "%s %.1f / %.0f kg" % [UiText.t("weight"), total_kg, cap]
	wl.add_theme_font_size_override("font_size", 12)
	wrow.add_child(wl)
	var wb := S.bar(S.GOLD_SOFT, Vector2(150, 8))
	wb.max_value = cap
	wb.value = total_kg
	wb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrow.add_child(wb)
	v.add_child(wrow)
	return v


func _item_slot(item: String, e: Dictionary, n: int) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(48, 48)
	var rare: String = e.get("rarity", "common")
	var col: Color = {"common": S.BRONZE_DARK, "uncommon": Color("4d6e43"), "rare": Color("3f5f86"), "very_rare": Color("6b4a86")}.get(rare, S.BRONZE_DARK)
	p.add_theme_stylebox_override("panel", S.slot(col))
	var tr := TextureRect.new()
	var path := "res://assets/items/%s.webp" % ITEM_ICON.get(item, item)
	tr.texture = load(path) if ResourceLoader.exists(path) else load("res://assets/items/ration.webp")
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.material = S.icon_material()
	p.add_child(tr)
	if n > 1:
		var l := Label.new()
		l.text = str(n)
		l.add_theme_font_size_override("font_size", 11)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 4)
		l.size_flags_horizontal = Control.SIZE_SHRINK_END
		l.size_flags_vertical = Control.SIZE_SHRINK_END
		p.add_child(l)
	p.tooltip_text = UiText.name_of(e.get("name", {"ko": item, "en": item}))
	if e.get("category", "") == "currency":
		p.tooltip_text += " %d" % n
	return p


func _rule() -> Control:
	var r := ColorRect.new()
	r.color = Color(S.BRONZE, 0.5)
	r.custom_minimum_size = Vector2(0, 1)
	return r


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
