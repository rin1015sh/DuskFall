extends Control
## 캐릭터 생성 화면(5단계). 종족·혈통·체형, 배경, 클래스, 포인트 구매 27점, 능력치 보너스, 기능, 미리보기.
## 실행: godot --path . res://scenes/ui/character_creation.tscn  (-- --shot=<png>로 캡처)
## 완료하면 created(spec)를 보낸다. 화면 글은 한국어·영어(UiText).

signal created(spec: Dictionary)

const Model := preload("res://scenes/ui/creation_model.gd")
const UiText := preload("res://scenes/ui/ui_text.gd")
const SKILL_KO := {"acrobatics": "곡예", "animal_handling": "동물 조련", "arcana": "비전", "athletics": "운동", "deception": "기만",
	"history": "역사", "insight": "통찰", "intimidation": "위협", "investigation": "조사", "medicine": "의학", "nature": "자연",
	"perception": "지각", "performance": "공연", "persuasion": "설득", "religion": "종교", "sleight_of_hand": "손재주",
	"stealth": "은신", "survival": "생존"}
const ABIL_KO := {"str": "근력", "dex": "민첩", "con": "건강", "int": "지능", "wis": "지혜", "cha": "매력"}

var model := Model.new("fighter")
var _box: VBoxContainer
var _preview: Label
var _errors: Label
var _args := {}
var _frames := 0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("1c1a20")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 24)
	row.offset_left = 20
	row.offset_top = 16
	add_child(row)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(760, 690)
	row.add_child(scroll)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_box)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(440, 0)
	row.add_child(right)
	_preview = Label.new()
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD
	_preview.custom_minimum_size = Vector2(440, 0)
	right.add_child(_preview)
	_errors = Label.new()
	_errors.add_theme_color_override("font_color", Color(1, 0.5, 0.4))
	_errors.autowrap_mode = TextServer.AUTOWRAP_WORD
	_errors.custom_minimum_size = Vector2(440, 0)
	right.add_child(_errors)
	var done := Button.new()
	done.text = "완료 / Done"
	done.pressed.connect(func() -> void:
		if model.errors().is_empty():
			created.emit(model.spec.duplicate(true)))
	right.add_child(done)
	if _args.has("demo"):
		_demo()
	_rebuild()


## 캡처용 예시 선택
func _demo() -> void:
	model.set_class("wizard")
	model.set_species("elf")
	for a: String in ["int", "int", "int", "int", "int", "int", "int", "dex", "dex", "dex", "dex", "dex", "dex", "con", "con", "con", "con", "con"]:
		model.raise(a)
	model.set_bonus_two_one("int", "dex")
	model.toggle_skill("arcana")
	model.toggle_skill("investigation")
	model.spec["name"] = {"ko": "엘라", "en": "Ella"}


func _process(_d: float) -> void:
	_frames += 1
	if _args.has("shot") and _frames == 20:
		get_viewport().get_texture().get_image().save_png(_args["shot"])
		get_tree().quit()


func _rebuild() -> void:
	for ch in _box.get_children():
		ch.queue_free()
	_title("캐릭터 생성 / Character Creation")
	# 클래스
	_option_row("클래스 / Class", RulesDB.ids("class"), model.spec["class"], func(id: String) -> void:
		model.set_class(id)
		_rebuild(), func(id: String) -> String: return UiText.name_of(RulesDB.get_entry("class", id)["name"]))
	# 종족·혈통·크기
	_option_row("종족 / Species", model.species_list(), model.spec["species"], func(id: String) -> void:
		model.set_species(id)
		_rebuild(), func(id: String) -> String: return UiText.name_of(RulesDB.get_entry("species", id)["name"]))
	var lins: Array = model.lineages(model.spec["species"])
	if not lins.is_empty():
		_option_row("혈통 / Lineage", lins, model.spec.get("lineage", ""), func(id: String) -> void:
			model.spec["lineage"] = id
			_rebuild(), func(id: String) -> String: return UiText.name_of(RulesDB.get_entry("species", id)["name"]))
	var sp := RulesDB.get_entry("species", model.spec["species"])
	if sp.has("size_choice"):
		_option_row("체형 / Size", sp["size_choice"], model.spec.get("size", "medium"), func(id: String) -> void:
			model.spec["size"] = id
			_rebuild(), func(id: String) -> String: return {"medium": "보통 / Medium", "small": "작은 / Small"}.get(id, id))
	_option_row("배경 / Background", RulesDB.ids("background"), model.spec["background"], func(id: String) -> void:
		model.spec["background"] = id
		_rebuild(), func(id: String) -> String: return UiText.name_of(RulesDB.get_entry("background", id)["name"]))
	# 포인트 구매
	_title("능력치(포인트 %d / 27 남음) / Abilities" % model.points_left())
	for a: String in model.ABILITIES:
		var h := HBoxContainer.new()
		var l := Label.new()
		l.text = "%s %s" % [ABIL_KO[a], a.to_upper()]
		l.custom_minimum_size = Vector2(110, 0)
		h.add_child(l)
		var minus := Button.new()
		minus.text = "−"
		minus.disabled = model.spec["scores"][a] <= 8
		minus.pressed.connect(func() -> void:
			model.lower(a)
			_rebuild())
		h.add_child(minus)
		var v := Label.new()
		v.text = " %2d " % model.spec["scores"][a]
		h.add_child(v)
		var plus := Button.new()
		plus.text = "+"
		plus.disabled = not model.can_raise(a)
		plus.pressed.connect(func() -> void:
			model.raise(a)
			_rebuild())
		h.add_child(plus)
		var bonus := Label.new()
		var b: int = int(model.spec["bonus"].get(a, 0))
		bonus.text = "  보너스 %+d → %d" % [b, model.final_score(a)] if b != 0 else "  → %d" % model.final_score(a)
		h.add_child(bonus)
		var p2 := Button.new()
		p2.text = "+2"
		p2.pressed.connect(func() -> void:
			var cur1: String = ""
			for k: String in model.spec["bonus"].keys():
				if model.spec["bonus"][k] == 1:
					cur1 = k
			model.set_bonus_two_one(a, cur1 if cur1 != "" and cur1 != a else ("con" if a != "con" else "dex"))
			_rebuild())
		h.add_child(p2)
		var p1 := Button.new()
		p1.text = "+1"
		p1.pressed.connect(func() -> void:
			var cur2: String = ""
			for k: String in model.spec["bonus"].keys():
				if model.spec["bonus"][k] == 2:
					cur2 = k
			if cur2 != "" and cur2 != a:
				model.set_bonus_two_one(cur2, a)
			_rebuild())
		h.add_child(p1)
		_box.add_child(h)
	# 기능
	var cls := RulesDB.get_entry("class", model.spec["class"])
	_title("기능 %d개 고르기 / Skills" % int(cls["skills"]["choose"]))
	var grid := GridContainer.new()
	grid.columns = 3
	for s: String in cls["skills"]["from"]:
		var cb := CheckBox.new()
		cb.text = "%s %s" % [SKILL_KO.get(s, s), s]
		cb.button_pressed = s in model.spec["skills"]
		cb.toggled.connect(func(_on: bool) -> void:
			model.toggle_skill(s)
			_rebuild())
		grid.add_child(cb)
	_box.add_child(grid)
	_update_preview()


func _title(t: String) -> void:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
	_box.add_child(l)


func _option_row(label: String, ids: Array, current: String, on_pick: Callable, name_fn: Callable) -> void:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(170, 0)
	h.add_child(l)
	var ob := OptionButton.new()
	for i in ids.size():
		ob.add_item(name_fn.call(ids[i]), i)
		if ids[i] == current:
			ob.select(i)
	ob.item_selected.connect(func(i: int) -> void: on_pick.call(ids[i]))
	h.add_child(ob)
	_box.add_child(h)


func _update_preview() -> void:
	var p := model.preview()
	var lines: PackedStringArray = []
	if p.has("hp"):
		lines.append("HP %d · AC %d · 속도 %d칸 · 암시야 %d칸" % [p["hp"], p["ac"], p["speed"], p["darkvision"]])
		lines.append("체형 틀: %s" % {"medium": "보통", "small": "작은", "dwarf": "드워프(작은 체형 변형)"}[p["body"]])
		var ab: PackedStringArray = []
		var sv: PackedStringArray = []
		for a: String in model.ABILITIES:
			ab.append("%s %d" % [ABIL_KO[a], p["abilities"][a]])
			sv.append("%s %+d" % [ABIL_KO[a], p["saves"][a]])
		lines.append("능력치: " + ", ".join(ab))
		lines.append("내성: " + ", ".join(sv))
		lines.append("기능·특성: " + ", ".join(p["features"]))
		if not p["spells"].is_empty():
			lines.append("주문: " + ", ".join(p["spells"]))
	_preview.text = "\n".join(lines)
	_errors.text = "\n".join(model.errors())
