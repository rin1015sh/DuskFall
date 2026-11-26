extends Node3D
## 시험 맵 화면: 탐험(6단계, 실시간) → 발견·적대 행동이면 전투(4단계 최소 화면, 턴제).
## 규칙은 scripts/rules가 처리하고, 이 씬은 판정 결과를 그리고 입력을 '미리보기 → 확정'으로 넘긴다.
##
## 실행 인자(-- 뒤): --combat(탐험 없이 바로 전투), --autoplay(파티도 AI, 바로 전투), --seed=<n>, --lang=en, --fast(지연 없음),
##   --sneak(탐험: 은신 켜고 시작), --dialogue=<생물 이름>(탐험: 그 생물과 대화를 열고 시작), --goto=x,y(탐험: 리더 이동),
##   --shot=<png 경로> --frames=<n>(n프레임 뒤 캡처하고 끝), --steps=<n>(캡처 전 n턴 진행), --cam=x,y --zoom=<배율>(카메라 고정),
##   --select=<생물 이름> --mode=<move|attack|shove|jump|spell:<id>> --preview=x,y 또는 생물 이름(캡처할 미리보기)

const Roster := preload("res://scenes/battle/test_roster.gd")
const V := preload("res://scenes/battle/view3d.gd")
const MapLoader := preload("res://scripts/rules/map_loader.gd")
const MapView := preload("res://scenes/battle/map_view.gd")
const DungeonKit := preload("res://scenes/kit/dungeon_kit.gd")
const PIXEL_KIT_DIR := "res://assets/pixel_kit"
const ActorView := preload("res://scenes/battle/actor_view.gd")
const InputRouter := preload("res://scenes/battle/input_router.gd")
const ActionInfo := preload("res://scenes/ui/action_info.gd")
const UiText := preload("res://scenes/ui/ui_text.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Physics := preload("res://scripts/rules/physics.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const SimpleAI := preload("res://scripts/ai/simple_ai.gd")
const Exploration := preload("res://scripts/rules/exploration.gd")
const Interact := preload("res://scripts/rules/interact.gd")
const Stealth := preload("res://scripts/rules/stealth.gd")
const Rest := preload("res://scripts/rules/rest.gd")
const Dialogue := preload("res://scripts/rules/dialogue.gd")
const SaveGame := preload("res://scripts/rules/save_game.gd")
const TICK_SEC := 6.0
## 따라가는 카메라는 발보다 화면 40px(1단계) 위를 본다
const FOLLOW_UP := Vector3(0, 1, 0)
const Progression := preload("res://scripts/rules/progression.gd")
const Travel := preload("res://scripts/rules/travel.gd")
const Shop := preload("res://scripts/rules/shop.gd")
const Actions := preload("res://scripts/rules/actions.gd")
const Hotbar := preload("res://scenes/ui/hotbar.gd")
const S := preload("res://scenes/ui/ui_style.gd")
const CharacterSheet := preload("res://scenes/ui/character_sheet.gd")
const SpellbookWindow := preload("res://scenes/ui/spellbook_window.gd")
const Equipment := preload("res://scripts/rules/equipment.gd")
const Minimap := preload("res://scenes/ui/minimap.gd")
const Vfx := preload("res://scenes/battle/vfx.gd")
## 상태 → 아이콘(assets/statuses). 없으면 이로운 것 buff, 해로운 것 debuff.
const CONDITION_ICON := {"blinded": "blind", "charmed": "charm", "frightened": "fear", "paralyzed": "paralysis",
	"poisoned": "poison", "stunned": "stun", "restrained": "snare", "grappled": "snare", "invisible": "hidden",
	"prone": "daze", "wet": "soaked", "burning": "burn", "surprised": "telegraphed", "unconscious": "stamina_depleted",
	"incapacitated": "daze", "slowed": "lethargy", "outlined": "marked", "coated_weapon": "venom_weapon",
	"enfeebled": "debuff", "sanctuary_ward": "guarding", "acid": "acid_corrosion", "deafened": "f3_auditory",
	"petrified": "petrify", "exhaustion": "exhaustion", "hasted": "haste"}

var world: Dictionary
var party: Array = []
var foes: Array = []
var map_view: Node3D
var sorted: Node3D
var views := {}  # creature → ActorView
var camera: Camera3D
## 도트 화면(저해상도 렌더링·외곽선·디더링)
var pixel: PixelView
## 카메라가 바라보는 점(세계)·확대(1 = 1칸 64px). 직교 투영, 회전 없음(view3d.gd).
var cam_target := Vector3.ZERO
var cam_zoom := 0.92
var router: RefCounted
var highlights: Node3D

var selected: Node = null
var mode := "move"
## 여러 대상 고르기(BG3식): 고른 칸 목록과 그 주문 모드. Spellcasting.target_plan이 수·종류를 정한다.
var _picked: Array = []
## 상호작용 물체 강조(G 또는 화면 버튼으로 켜고 끄기 — iPad 키보드·터치)
var alt_highlight := false
var hp_btn: Button
var hl_btn: Button
var _picked_mode := ""
var cast_now_btn: Button
## 고른 행동 설명 카드(아이패드 — 마우스 올리기 툴팁 대신, BG3 콘솔식): 단축 막대 위에 고르는 동안 떠 있다
var info_card: PanelContainer
var info_title: Label
var info_body: Label
var info_hint: Label
## 마지막 입력이 터치인가(터치면 자신 대상 행동도 '고르기 → 같은 칸 다시 누르기 = 실행')
var touch_ui := false
## 터치로 골라 둔 자신 대상 행동(다시 누르면 실행)
var armed_self := ""
var preview_cell := Vector2i(-1, -1)
var preview_data := {}
var busy := false

var args := {}
# UI
var ui: CanvasLayer
var round_label: Label
var order_box: HBoxContainer
var party_box: VBoxContainer
var action_box: HBoxContainer
var status_label: Label
var log_box: RichTextLabel
var tooltip: PanelContainer
var tooltip_label: Label
## BG3식 대상 정보 막대(위 가운데)·커서 옆 확률
var target_panel: PanelContainer
var tp_name: Label
var tp_bar: ProgressBar
var tp_hp: Label
var tp_conds: HBoxContainer
var tp_chips: HBoxContainer
var hit_label: Label
var info_panel: PanelContainer
var info_label: Label
var banner: Label
var _log_seen := 0
var _frames := 0
# 탐험
var explore: Node
var exploring := false
var _tick_acc := 0.0
var follow := true
## 로그: 전투 중에는 보이고, 탐험 중에는 L 키로 켤 때만(BG3처럼 화면을 비움)
var log_forced := false
var dlg: RefCounted = null
var dlg_panel: PanelContainer
var dlg_text: RichTextLabel
var dlg_options: VBoxContainer
var dlg_use_insp: CheckBox
var hotbar: Control
var sheet: Control
var spellbook: Control
var minimap: Control
var vfx: Node2D


class Highlights extends Node3D:
	## 바닥 위 표시(이동 경로·범위·미리보기 칸·시야 원뿔 등): 칸 윗면 높이에 얇게 깐 판(ImmediateMesh).
	var scene: Node
	var _im := ImmediateMesh.new()
	var _mi := MeshInstance3D.new()
	var _dirty := true
	var _g: Node

	func _ready() -> void:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.render_priority = 3
		_mi.mesh = _im
		_mi.material_override = m
		_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mi)

	func queue_redraw() -> void:
		_dirty = true

	func _process(_delta: float) -> void:
		if not _dirty:
			return
		_dirty = false
		_im.clear_surfaces()
		_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		# 빈 표면은 만들 수 없어 보이지 않는 삼각형 하나로 연다
		_tri(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Color(0, 0, 0, 0))
		_draw()
		_im.surface_end()

	func _tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
		for p: Vector3 in [a, b, c]:
			_im.surface_set_color(col)
			_im.surface_add_vertex(p)

	func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
		_tri(a, b, c, col)
		_tri(a, c, d, col)

	## 칸 평면 점(칸 단위) → 그 자리 바닥 위(자연 지형은 언덕 면을 따라)
	func _at(p: Vector2) -> Vector3:
		return V.flat(p, scene.map_view.ground_at(p) + V.LIFT * 2.0)

	## 바닥 위 선(굵기 w 유닛). 점마다 그 칸 높이.
	func _line(pts: Array, w: float, col: Color) -> void:
		for i in pts.size() - 1:
			var a: Vector3 = _at(pts[i])
			var b: Vector3 = _at(pts[i + 1])
			var dv := b - a
			var n := Vector3(-dv.z, 0, dv.x).normalized() * (w * 0.5)
			if n == Vector3.ZERO:
				continue
			_quad(a + n, b + n, b - n, a - n, col)

	## 바닥 위 원(채움 + 테두리)
	func _disc(center: Vector2, r: float, fill: Color, line: Color) -> void:
		var c: Vector3 = _at(center)
		var pts := []
		for i in 33:
			var a := TAU * i / 32.0
			pts.append(center + Vector2(cos(a), sin(a)) * r)
		for i in 32:
			var p0: Vector3 = V.flat(pts[i], c.y)
			var p1: Vector3 = V.flat(pts[i + 1], c.y)
			_tri(c, p0, p1, fill)
		_line(pts, 2.0 / V.T, line)

	func _draw() -> void:
		var g: Node = scene.world["grid"]
		_g = g
		var d: Dictionary = scene.preview_data
		_entities(g)
		if scene.exploring:
			_explore_marks(g)
		if scene.alt_highlight:
			# BG3: Alt를 누르는 동안 상호작용할 수 있는 물체(전리품·자물쇠·문·살펴볼 것) 강조
			for oc: Vector2i in g.objects.keys():
				var obj: Dictionary = g.objects[oc]
				if not obj.get("loot", {}).is_empty() or obj.has("lock") or obj.has("door") or obj.has("contents"):
					_cell(g, oc, Color(1, 0.85, 0.3, 0.18), Color(1, 0.85, 0.3, 1.0))
			for e: Dictionary in scene.world.get("examines", []):
				if not e.get("done", false):
					_cell(g, Vector2i(int(e["cell"][0]), int(e["cell"][1])), Color(1, 0.85, 0.3, 0.18), Color(1, 0.85, 0.3, 1.0))
		var partial: Array = d.get("partial", [])
		for c: Vector2i in d.get("area", []):
			_cell(g, c, Color(1, 0.55, 0.1, 0.33), Color(1, 0.6, 0.2, 0.0))  # 걸친 칸도 똑같이 맞는다
		_shape_outline(d.get("shape", {}), Color(1, 0.75, 0.35, 0.95))
		for c: Vector2i in d.get("path", []):
			_cell(g, c, Color(0.3, 0.6, 1.0, 0.3), Color(0.4, 0.7, 1.0, 0.8))
		for c: Vector2i in d.get("reaction_cells", []):
			_cell(g, c, Color(0.2, 1.0, 1.0, 0.25), Color(0.2, 1.0, 1.0, 0.9))
		for c: Vector2i in d.get("spread", []):
			_cell(g, c, Color(1, 0.3, 0.0, 0.15), Color(1, 0.3, 0.0, 0.9))
		for c: Vector2i in d.get("oa", []):
			var m := Vector2(c) + Vector2(0.5, 0.5)
			var k := 10.0 / V.T
			_line([m + Vector2(-k, -k), m + Vector2(k, k)], 4.0 / V.T, Color.RED)
			_line([m + Vector2(k, -k), m + Vector2(-k, k)], 4.0 / V.T, Color.RED)
		var cell: Vector2i = scene.preview_cell
		if g.in_bounds(cell):
			var col := Color(1, 1, 1, 0.9) if d.get("valid", true) else Color(1, 0.2, 0.2, 0.9)
			_cell(g, cell, Color(1, 1, 1, 0.08), col)

	## 탐험 표시: 은신 중이면 적 시야 원뿔(칸 빛 단계별 색 — 5단계), 찾은 함정(붉게), 살펴볼 것(노랗게).
	## 주문이 남긴 존재(Spiritual Weapon·Flaming Sphere·Mage Hand·환영·침묵·오두막)
	func _entities(g: Node) -> void:
		const COL := {"spiritual_weapon": Color(0.75, 0.8, 1.0), "flaming_sphere": Color(1.0, 0.5, 0.15), "mage_hand": Color(0.6, 0.9, 0.8),
			"illusion": Color(0.75, 0.6, 1.0), "silence": Color(0.6, 0.6, 0.7), "tiny_hut": Color(0.9, 0.8, 0.5)}
		for inst: Dictionary in preload("res://scripts/rules/spellcasting.gd").instances.values():
			var e: Dictionary = inst.get("entity", {})
			if e.is_empty():
				continue
			var cell: Vector2i = e["cell"]
			var col: Color = COL.get(e["kind"], Color.WHITE)
			var r := 26.0 if e["kind"] in ["silence", "tiny_hut"] else 13.0
			_disc(Vector2(cell) + Vector2(0.5, 0.5), r / V.T, Color(col, 0.35), col)

	func _explore_marks(g: Node) -> void:
		var sneaking := false
		for p: Node in scene.party:
			sneaking = sneaking or p.sneaking
		if sneaking:
			for o: Node in g.creatures():
				if o.dead or o.team == "party" or o.is_incapacitated():
					continue
				var cov: Dictionary = Stealth.cone_coverage(g, o)
				for c: Vector2i in cov:
					var l: int = g.light_at(c)
					var k := 1.0  # 걸친 칸도 시야 안(완전히 벗어난 칸만 안전)
					if l == 2:
						_cell(g, c, Color(1, 0.15, 0.1, 0.30 * k), Color(1, 0.2, 0.1, 0.0))
					elif l == 1:
						_cell(g, c, Color(1, 0.55, 0.1, 0.18 * k), Color(1, 0.5, 0.1, 0.0))
				var f := Vector2(o.facing).normalized()
				var apex := Vector2(g.cell_of(o)) + Vector2(0.5, 0.5)
				_shape_outline({"type": "cone", "apex": apex, "dir": f, "len": o.sight_tiles + 0.5, "half": PI / 4}, Color(1, 0.35, 0.25, 0.6))
		for t: Dictionary in scene.world.get("traps", []):
			if t.get("found", false) and t["state"] == "armed":
				var tc := Vector2i(int(t["cell"][0]), int(t["cell"][1]))
				_cell(g, tc, Color(1, 0, 0, 0.35), Color(1, 0.1, 0.1, 1.0))
		for e: Dictionary in scene.world.get("examines", []):
			if not e.get("done", false):
				var ec := Vector2i(int(e["cell"][0]), int(e["cell"][1]))
				_cell(g, ec, Color(1, 0.9, 0.3, 0.06), Color(1, 0.9, 0.3, 0.7))

	## 매끄러운 범위 윤곽(칸 좌표 → 화면: 바닥 기준)
	func _shape_outline(sh: Dictionary, col: Color) -> void:
		if sh.is_empty():
			return
		var pts := []
		match sh["type"]:
			"circle":
				for i in 49:
					var a := TAU * i / 48.0
					pts.append(sh["center"] + Vector2(cos(a), sin(a)) * sh["r"])
			"cone":
				var apex: Vector2 = sh["apex"]
				var base: float = sh["dir"].angle()
				pts.append(apex)
				for i in 17:
					var a: float = base - sh["half"] + 2.0 * sh["half"] * i / 16.0
					pts.append(apex + Vector2(cos(a), sin(a)) * sh["len"])
				pts.append(apex)
			"line":
				var a: Vector2 = sh["a"]
				var dv: Vector2 = sh["dir"]
				var n: Vector2 = Vector2(-dv.y, dv.x) * float(sh["half_w"])
				var b: Vector2 = a + dv * sh["len"]
				pts = [a + n, b + n, b - n, a - n, a + n]
		_line(pts, 6.0 / V.T, Color(col, col.a * 0.35))
		_line(pts, 2.0 / V.T, col)

	## 칸 하나: 윗면 채움 + 테두리(2px 안쪽). 바닥을 따라 4×4 조각으로 깐다(언덕에서도 묻히지 않게).
	func _cell(g: Node, c: Vector2i, fill: Color, line: Color) -> void:
		var i := 2.0 / V.T
		var o := Vector2(c) + Vector2(i, i)
		var span := 1.0 - 2.0 * i
		const N := 4
		if fill.a > 0.0:
			for zz in N:
				for xx in N:
					var p0 := o + Vector2(xx, zz) * span / N
					var p1 := o + Vector2(xx + 1, zz + 1) * span / N
					_quad(_at(p0), _at(Vector2(p1.x, p0.y)), _at(p1), _at(Vector2(p0.x, p1.y)), fill)
		if line.a > 0.0:
			var pts := []
			for k in N * 4 + 1:
				var t := float(k) / N
				var side := mini(int(t), 3)
				var f := t - side
				var corner := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(0, 0)]
				pts.append(o + (corner[side] as Vector2).lerp(corner[side + 1], f) * span)
			_line(pts, 2.0 / V.T, line)


func _ready() -> void:
	_parse_args()
	UiText.lang = args.get("lang", "ko")
	Dice.set_seed(int(args.get("seed", "7")))
	var map_id: String = args.get("map", "fallen_watch")
	var b := Roster.build(map_id, int(args.get("level", "1")))
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 1.0
	camera.far = V.CAM_DIST * 2.0
	RenderingServer.set_default_clear_color(Color("0c0b0e"))
	add_child(camera)
	camera.make_current()
	_setup_pixel()
	router = InputRouter.new()
	router.cell_at = func(pos: Vector2) -> Vector2i: return _pick(pos)
	router.preview.connect(_on_preview)
	router.confirm.connect(_on_confirm)
	router.info.connect(_on_info)
	router.pan.connect(func(delta: Vector2) -> void:
		follow = false
		cam_target -= V.pan_delta(delta, cam_zoom))
	router.zoom.connect(_on_zoom)
	router.cancel.connect(_cancel_mode)
	EventBus.on_enter_tile.connect(func(c: Object, _cell: Vector2i) -> void:
		if views.has(c):
			views[c].sync())
	highlights = Highlights.new()
	highlights.scene = self
	_setup_world(b, map_id)
	add_child(highlights)
	vfx = Vfx.new()
	vfx.scene = self
	add_child(vfx)
	# 반응: 파티 기본은 자동(매번 묻기 팝업은 반응 대기 구조와 함께 다음 단계)
	for c: Node in party:
		for r: String in c.known_reactions:
			c.reaction_settings[r] = "auto"
	_build_ui()
	if args.has("combat") or args.has("autoplay"):
		_begin_battle()
		return
	exploring = true
	selected = party[0]
	if args.has("sneak"):
		explore.set_sneak(selected, true)
	if args.has("goto"):
		var gp: PackedStringArray = args["goto"].split(",")
		explore.move_to(selected, Vector2i(int(gp[0]), int(gp[1])))
	_refresh()
	if args.has("levelup"):
		for cid: String in str(args["levelup"]).split(","):
			world["xp"] = 999999  # 시험용: --levelup=클래스,클래스(고른 캐릭터를 그 클래스로 레벨 업 — 멀티클래스 확인)
			var ex: Dictionary = {} if selected.class_levels.has(cid) else Progression.new_class_extra(selected, cid)
			Progression.level_up(world, selected, cid, ex)
	if args.has("give"):
		for it: String in str(args["give"]).split(","):
			selected.inventory[it] = int(selected.inventory.get(it, 0)) + 1  # 시험용: --give=아이템,아이템
	if args.has("equip"):
		for it: String in str(args["equip"]).split(","):
			Equipment.equip(world, selected, it)  # 시험용: --equip=아이템,아이템(소지품에 있어야)
	if args.has("sheet"):
		if str(args["sheet"]) == "party":
			sheet.view_mode = "party"  # 캡처용: --sheet=party
		sheet.show_for(world, selected)
	if args.has("spellbook"):
		var bi := int(str(args["spellbook"])) if str(args["spellbook"]).is_valid_int() else 0
		selected = party[clampi(bi, 0, party.size() - 1)]
		selected.inventory["spell_scroll_magic_missile"] = 1  # 시험용: 배우기 단추가 보이게
		_refresh()
		spellbook.show_for(world, selected)
	if args.has("camp"):
		_go_camp()
	if args.has("shop"):
		_open_shop(args["shop"])
	if args.has("roll"):
		_visible_roll(selected, "dex", "sleight_of_hand", 15, _skill_name("sleight_of_hand"), func(_r: Dictionary) -> void: pass)
		if args["roll"] == "fail":
			Dice.force([2])
			_roll_ctx["result"] = Interact.visible_check(world, selected, "dex", "sleight_of_hand", 15)
			world["inspiration"] = 1
			_draw_roll()
	if args.has("dialogue"):
		for o: Node in foes:
			if o.name == args["dialogue"]:
				_open_dialogue(o.get_meta("dialogue", ""), o)
	if args.has("preview"):
		var pp: PackedStringArray = args["preview"].split(",")
		_show_preview(Vector2i(int(pp[0]), int(pp[1])))
	_apply_cam_arg()
	_check_combat()


## 맵 하나를 화면에 올린다(처음 시작·맵 이동 공용).
func _setup_world(b: Dictionary, map_id: String) -> void:
	world = b["world"]
	party = b["party"]
	foes = b["foes"]
	for n: Node in [world["grid"], world["surfaces"], world["reactions"], world["turns"]]:
		add_child(n)
	for c: Node in party + foes:
		if c.get_parent() == null:
			add_child(c)
		Roster.add_art(c)
	sorted = Node3D.new()
	map_view = MapView.new()
	add_child(map_view)
	add_child(sorted)
	if highlights != null and highlights.get_parent() == self:
		move_child(highlights, -1)
	map_view.build(world["grid"], sorted, MapLoader.load_map(map_id))
	for c: Node in party + foes + world.get("roster", []):
		if world["grid"].creatures().has(c) and not views.has(c):
			var v: Node3D = ActorView.new()
			v.ground = map_view.ground_at
			v.setup(c, world["grid"])
			sorted.add_child(v)
			views[c] = v
	var start_cell: Vector2i = world["grid"].cell_of(party[0]) if not party.is_empty() else world["grid"].size / 2
	cam_target = V.pos(start_cell, world["grid"].height(start_cell)) + FOLLOW_UP
	_apply_camera()
	explore = Exploration.new()
	add_child(explore)
	explore.setup(world, party)
	if minimap != null:
		minimap.grid = world["grid"]


## 다른 맵으로(맵 이동·캠프). 지금 맵 상태를 맡겨 두고 파티만 데려간다.
func _travel(to: String, spawn: String) -> void:
	world.erase("pending_travel")
	_close_dialogue()
	var carry := Travel.leave(world)
	var grid: Node = world["grid"]
	var keep: Array = party + world.get("roster", [])
	for c: Node in keep:
		if grid.creatures().has(c):
			grid.remove(c)
	for v in views.values():
		v.queue_free()
	views.clear()
	for n: Node in [world["grid"], world["surfaces"], world["reactions"], world["turns"], explore, map_view, sorted] + foes + world.get("summons", []):
		if is_instance_valid(n) and not n in keep:
			n.queue_free()
	var Sp: Variant = Spellcasting
	for id: Variant in Sp.instances.keys():
		Sp.end_instance(id)
	var b := Travel.enter(to, party, carry, spawn)
	_setup_world(b, to)
	exploring = true
	mode = "move"
	selected = party[0]
	world["at_camp"] = RulesDB.get_entry("map", to).get("camp", false)
	if world["at_camp"]:
		var r := Rest.long_rest(world, party, {"tiny_hut": true})  # 캠프에 오면 긴 휴식(보급품이 모자라면 부분 휴식)
		Dice.log_text(UiText.t("camp_rested") % (UiText.t("partial") if r.get("partial", false) else ""))
	_refresh()


func _go_camp() -> void:
	var why := Travel.can_go_camp(world, selected)
	if why != "":
		_notify({"ok": false, "reason": why})
		return
	world["return_to"] = {"map": world["map_id"], "cell": [world["grid"].cell_of(selected).x, world["grid"].cell_of(selected).y]}
	call_deferred("_travel", "camp", "camp_entry")


func _begin_battle() -> void:
	_apply_cam_arg()
	exploring = false
	if not world["turns"].in_combat:
		var zone_id: String = args.get("zone", "")
		if zone_id == "":
			for c in world["grid"].all_cells():
				if not world["grid"].zones(c).is_empty():
					zone_id = world["grid"].zones(c)[0]
					break
		world["turns"].start_combat(zone_id)
	selected = null
	_refresh()
	_advance()


## 탐험 중 전투가 시작됐으면(발견·적대 행동) 턴제로 넘어간다.
func _check_combat() -> void:
	if exploring and world.has("pending_travel") and not world["turns"].in_combat:
		var pt: Dictionary = world["pending_travel"]
		world.erase("pending_travel")
		call_deferred("_travel", pt["to"], pt["spawn"])
		return
	if world.has("pending_ui") and dlg == null:
		var pu: Dictionary = world["pending_ui"]
		world.erase("pending_ui")
		if pu.has("shop"):
			_open_shop(pu["shop"])
	if exploring and world.has("pending_dialogue") and dlg == null and not world["turns"].in_combat:
		var pd: Dictionary = world["pending_dialogue"]
		world.erase("pending_dialogue")
		if pd.get("speaker") != null and pd["speaker"] in party:
			selected = pd["speaker"]
		if pd["id"] != "":
			_open_dialogue(pd["id"], pd["npc"])
	if exploring and world["turns"].in_combat:
		_close_dialogue()
		banner.text = UiText.t("combat_start")
		banner.visible = true
		get_tree().create_timer(1.2).timeout.connect(func() -> void:
			if banner.text == UiText.t("combat_start"):
				banner.visible = false)
		_begin_battle()


func _parse_args() -> void:
	for a: String in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"


## 캡처용: --cam=x,y면 그 칸을 보고 따라가지 않는다(--zoom=배율)
func _apply_cam_arg() -> void:
	if args.has("zoom"):
		cam_zoom = float(args["zoom"])
	if args.has("cam"):
		var cp: PackedStringArray = args["cam"].split(",")
		var cc := Vector2i(int(cp[0]), int(cp[1]))
		follow = false
		cam_target = V.pos(cc, world["grid"].height(cc))
		_apply_camera()


## 도트 화면(pixel_view.gd): --pixel=<1도트 px>(0 = 끔), --pixel_ss=<초표본>, --pixel_palette=0이면 색 줄이기 끔,
## --pixel_outline=0이면 외곽선 끔
func _setup_pixel() -> void:
	pixel = PixelView.new()
	pixel.scale_px = int(args.get("pixel", str(pixel.scale_px)))
	pixel.ss = maxi(1, int(args.get("pixel_ss", str(pixel.ss))))
	pixel.palette = args.get("pixel_palette", "0") != "0"
	pixel.outline = args.get("pixel_outline", "1") != "0"
	add_child(pixel)
	pixel.setup(camera)
	# 도트 화면이면 키트 그림도 도트 변환본(assets/pixel_kit — tools/pixelize_kit.py), --pixel_art=0이면 원본 그대로
	DungeonKit.art_dir = PIXEL_KIT_DIR if pixel.scale_px > 0 and args.get("pixel_art", "1") != "0" else ""
	MapView.art_dots = 32.0 if DungeonKit.art_dir != "" else 0.0


## 화면 점 → 칸(카메라 광선이 처음 닿는 칸 기둥)
func _pick(screen: Vector2) -> Vector2i:
	_apply_camera()
	return V.pick(world["grid"], camera.project_ray_origin(screen), camera.project_ray_normal(screen))


## 카메라 자세·직교 크기를 cam_target·cam_zoom에 맞춘다.
func _apply_camera() -> void:
	camera.transform = V.camera_transform(cam_target)
	camera.size = V.ortho_size(get_viewport().get_visible_rect().size.y, cam_zoom)


func _on_zoom(factor: float, _at: Vector2) -> void:
	cam_zoom = clampf(cam_zoom * factor, 0.4, 2.2)


func _input(event: InputEvent) -> void:
	# 마지막 입력 장치(터치·진짜 마우스)만 기록한다 — 이벤트는 소비하지 않는다
	if event is InputEventScreenTouch:
		touch_ui = true
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and event.relative.length() > 0.5:
		touch_ui = false


func _build_info_card(parent: Control) -> void:
	info_card = PanelContainer.new()
	info_card.add_theme_stylebox_override("panel", S.panel(12, S.BRONZE, S.BG, 2))
	info_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	info_card.custom_minimum_size = Vector2(380, 0)
	info_card.visible = false
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	info_card.add_child(row)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	info_title = S.title("", 18)
	col.add_child(info_title)
	info_body = Label.new()
	info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_body.custom_minimum_size = Vector2(360, 0)
	info_body.add_theme_font_size_override("font_size", 13)
	info_body.add_theme_color_override("font_color", S.TEXT)
	col.add_child(info_body)
	info_hint = Label.new()
	info_hint.add_theme_font_size_override("font_size", 12)
	info_hint.add_theme_color_override("font_color", S.GOLD_SOFT)
	col.add_child(info_hint)
	var x := Button.new()
	x.text = "×"
	x.focus_mode = Control.FOCUS_NONE
	x.custom_minimum_size = Vector2(40, 40)
	x.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	x.pressed.connect(_cancel_mode)
	row.add_child(x)
	parent.add_child(info_card)


## 고른 행동이 있으면 설명 카드를 채워 보인다(대상 고르는 동안 계속).
func _update_info_card() -> void:
	if info_card == null:
		return
	var key: String = hotbar.selected_key if hotbar != null else ""
	if key == "" or selected == null:
		info_card.visible = false
		return
	var i := ActionInfo.describe(world, selected, key, exploring)
	info_title.text = i["title"]
	var lines: PackedStringArray = [i["meta"]]
	for k: String in ["dice", "desc"]:
		if i[k] != "":
			lines.append(i[k])
	if i["why"] != "":
		lines.append("— " + i["why"])
	info_body.text = "\n".join(lines)
	info_hint.text = UiText.t("info_tap_again") if armed_self == key else UiText.t("info_pick_target")
	info_card.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		# 자리 키로 판정: 아이패드 키보드가 한글 입력 상태면 keycode가 'ㅑ' 등으로 와서 I·K가 안 먹는다
		var key: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		var pan := {KEY_LEFT: Vector2(-40, 0), KEY_RIGHT: Vector2(40, 0), KEY_UP: Vector2(0, -40), KEY_DOWN: Vector2(0, 40)}
		if not exploring:
			# 전투 중 WASD = 화면 이동(탐험 중에는 _wasd_walk가 캐릭터를 걷게 한다)
			pan.merge({KEY_A: Vector2(-40, 0), KEY_D: Vector2(40, 0), KEY_W: Vector2(0, -40), KEY_S: Vector2(0, 40)})
		if pan.has(key):
			follow = false
			cam_target += V.pan_delta(pan[key], cam_zoom)
		elif key == KEY_I or key == KEY_C:
			_toggle_sheet()
		elif key == KEY_K:
			_toggle_spellbook()
		elif key == KEY_L:
			log_forced = not log_forced
			_refresh()
		elif (key == KEY_ENTER or key == KEY_KP_ENTER) and not _picked.is_empty():
			_cast_picked()
		elif key >= KEY_0 and key <= KEY_9 and not event.echo:
			# BG3: 숫자키 = 단축 막대 칸(1~9, 0 = 10번째)
			var idx := 9 if key == KEY_0 else int(key - KEY_1)
			if idx < hotbar.slot_keys.size():
				_on_action(str(hotbar.slot_keys[idx]))
		elif key == KEY_SPACE and not event.echo and not exploring:
			_end_turn()  # BG3: Space = 턴 끝내기
		elif key == KEY_H and not event.echo:
			_toggle_reveal_hp()  # 모든 HP 보기 켜고 끄기(iPad 키보드 — 누르고 있는 Shift 대신)
		elif key == KEY_G and not event.echo:
			_toggle_highlight()  # 상호작용 물체 강조 켜고 끄기(누르고 있는 Alt 대신)
		elif key == KEY_Z and not event.echo:
			_on_action("jump")  # BG3: Z 점프
		elif key == KEY_V and not event.echo:
			_on_action("shove")  # BG3: V 밀치기
		elif key == KEY_ESCAPE:
			if sheet.visible or spellbook.visible:
				sheet.visible = false
				spellbook.visible = false
				return
			_cancel_mode()
		return
	router.handle(event, Time.get_ticks_msec())


func _process(delta: float) -> void:
	router.update(Time.get_ticks_msec())
	if exploring and dlg == null and not args.has("shot"):
		_tick_acc += delta
		if _tick_acc >= TICK_SEC:
			_tick_acc = 0.0
			explore.tick()
			_refresh()
			_check_combat()
	_wasd_walk()
	if follow and selected != null and views.has(selected):
		cam_target = cam_target.lerp(views[selected].position + FOLLOW_UP, minf(1.0, delta * 4.0))
	_apply_camera()
	if pixel != null:
		pixel.sync()
	var occ: Array = []
	for c: Node in views.keys():
		if not c.dead:
			occ.append(views[c].occlusion_info())
	map_view.update_occlusion(occ)
	_frames += 1
	if args.has("hover") and _frames == int(args.get("frames", "30")) - 3:
		# 캡처용: --hover=x,y 칸에 마우스를 올린 것처럼 미리보기(대상 막대·확률), --mode=act:attack 등
		if args.has("mode"):
			mode = args["mode"]
		var hv: PackedStringArray = args["hover"].split(",")
		_show_preview(Vector2i(int(hv[0]), int(hv[1])))
	if args.has("action") and _frames == int(args.get("frames", "30")) - 5:
		# 캡처용: --action=<행동 키> 단축 막대에서 고른 것처럼(설명 카드), --touch면 터치로
		touch_ui = args.has("touch")
		_on_action(args["action"])
	if args.has("shot") and _frames == int(args.get("frames", "30")):
		get_viewport().get_texture().get_image().save_png(args["shot"])
		get_tree().quit()


## 탐험 중 WASD = 고른 캐릭터 직접 걷기(컨트롤러식, 화면 기준 — 카메라 회전 없음: W 북·S 남·A 서·D 동, 둘 누르면 대각선).
## 누르고 있는 동안 걸음이 끝나 갈 때마다 한 칸씩. 묶인 파티원은 따라온다(Exploration.step_dir).
func _wasd_walk() -> void:
	if not exploring or dlg != null or selected == null or selected.team != "party" or not views.has(selected):
		return
	if (sheet != null and sheet.visible) or (spellbook != null and spellbook.visible):
		return
	var fo := get_viewport().gui_get_focus_owner()
	if fo is LineEdit or fo is TextEdit:
		return
	var d := Vector2i.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		d.y -= 1
	if Input.is_physical_key_pressed(KEY_S):
		d.y += 1
	if Input.is_physical_key_pressed(KEY_A):
		d.x -= 1
	if Input.is_physical_key_pressed(KEY_D):
		d.x += 1
	if d == Vector2i.ZERO or views[selected].steps_left() > 1:
		return
	if explore.step_dir(selected, d):
		follow = true
		_clear_preview()
		_refresh()
		_check_combat()


# ======================================================================
# 턴 흐름
# ======================================================================

func _advance() -> void:
	var tm: Node = world["turns"]
	var steps_left := int(args.get("steps", "-1"))
	while tm.in_combat:
		var group: Array = tm.current_group()
		if group.is_empty():
			break
		var c: Node = group[0]
		var ai: bool = c.team != "party" or c.has_meta("summoner") or args.has("autoplay") or steps_left > 0
		if not ai:
			if not group.has(selected):
				selected = group[0]
			busy = false
			_refresh()
			if args.has("select"):
				# 캡처용: --shot이면 차례가 아니어도 그 캐릭터를 고른다
				for m: Node in (party if args.has("shot") else group):
					if m.name == args["select"]:
						selected = m
			if args.has("precast"):
				# 시험용: --precast=주문@x,y[;주문@x,y]
				var pc: Node = selected
				for o: Node in party:
					if o.name == args.get("select", ""):
						pc = o
				for part: String in args["precast"].split(";"):
					var sp: PackedStringArray = part.split("@")
					var xy: PackedStringArray = sp[1].split(",")
					pc.spells.append(sp[0])
					pc.reset_turn()
					var pr: Dictionary = Spellcasting.cast(world, pc, sp[0], Vector2i(int(xy[0]), int(xy[1])))
					if not pr.get("ok", false):
						print("precast ", sp[0], ": ", pr.get("reason", ""))
				args.erase("precast")
				map_view.refresh()
			if args.has("mode"):
				mode = args["mode"]
				if mode.begins_with("act:"):
					hotbar.selected_key = mode.trim_prefix("act:")
					hotbar.tab = "spells" if mode.begins_with("act:spell:") else hotbar.tab
			_refresh()
			if args.has("preview"):
				var p: PackedStringArray = args["preview"].split(",")
				if p.size() == 2:
					_show_preview(Vector2i(int(p[0]), int(p[1])))
				else:
					for o: Node in party + foes:
						if o.name == args["preview"]:
							_show_preview(world["grid"].cell_of(o))
			return
		busy = true
		selected = c
		_refresh()
		if not args.has("fast") and steps_left < 0:
			await get_tree().create_timer(0.6).timeout
		SimpleAI.take_turn(world, c)
		_refresh()
		if tm.in_combat:
			tm.end_turn(c)
		if steps_left > 0:
			steps_left -= 1
			args["steps"] = str(steps_left)
	busy = false
	_refresh()
	if not tm.in_combat:
		banner.text = UiText.t("victory") if tm.result == "victory" else UiText.t("defeat")
		banner.visible = true
		if tm.result == "victory" and not args.has("autoplay"):
			# 이기면 탐험으로 돌아간다(경험치·구역 보상)
			exploring = true
			explore.check_zone_rewards()
			selected = party.filter(func(p: Node) -> bool: return not p.dead)[0]
			explore.leader = selected
			mode = "move"
			_refresh()


## 모든 생물 HP 보기(H·화면 버튼 — 켜고 끄기).
func _toggle_reveal_hp() -> void:
	ActorView.reveal_hp = not ActorView.reveal_hp
	if hp_btn != null:
		hp_btn.button_pressed = ActorView.reveal_hp
	_refresh()


## 상호작용 물체 강조(G·화면 버튼 — 켜고 끄기).
func _toggle_highlight() -> void:
	alt_highlight = not alt_highlight
	if hl_btn != null:
		hl_btn.button_pressed = alt_highlight
	highlights.queue_redraw()


## 고르던 행동·대상 취소(Esc·우클릭 — BG3).
func _cancel_mode() -> void:
	armed_self = ""
	_picked = []
	_picked_mode = ""
	mode = "move"
	hotbar.selected_key = ""
	_clear_preview()
	_refresh()


func _end_turn() -> void:
	if busy or selected == null:
		return
	_clear_preview()
	world["turns"].end_turn(selected)
	selected = null
	_advance()


func _select(c: Node) -> void:
	follow = true
	if sheet.visible:
		sheet.creature = c  # 캐릭터 창은 고른 캐릭터를 따라간다
	if exploring:
		if c.dead:
			return
		selected = c
		explore.leader = c
		_clear_preview()
		_refresh()
		return
	if not world["turns"].in_combat or not c in world["turns"].order:
		# 전투에 끼지 않은 파티원: 실시간으로 직접 옮길 수 있다
		selected = c
		mode = "rt_move"
		_clear_preview()
		_refresh()
		return
	if busy or not world["turns"].is_current(c):
		return
	selected = c
	_clear_preview()
	_refresh()


func _set_mode(m: String) -> void:
	mode = m
	_clear_preview()
	_refresh()


# ======================================================================
# 미리보기 → 확정
# ======================================================================

func _on_preview(pos: Vector2) -> void:
	if (busy and mode != "rt_move") or selected == null or dlg != null:
		return
	_show_preview(_pick(pos))


func _show_preview(cell: Vector2i) -> void:
	preview_cell = cell
	preview_data = _compute_preview(cell)
	preview_data["spread"] = world["surfaces"].preview_spread()
	highlights.queue_redraw()
	var text: String = preview_data.get("text", "")
	tooltip.visible = text != ""
	tooltip_label.text = text
	var screen := camera.unproject_position(V.top(world["grid"], cell)) if world["grid"].in_bounds(cell) else Vector2.ZERO
	tooltip.position = screen + Vector2(24, -60)
	_show_target_info(cell, screen)


## BG3 대상 막대: 커서 아래 생물의 이름·레벨·HP·상태, 노리는 중이면 유리·불리·보정 칩과 커서 옆 확률.
func _show_target_info(cell: Vector2i, screen: Vector2) -> void:
	if target_panel == null:
		return
	var g: Node = world["grid"]
	var t: Node = g.creature_at(cell) if g.in_bounds(cell) else null
	if t == null or (t != selected and not views.has(t)) or (views.has(t) and not views[t].visible):
		target_panel.visible = false
		hit_label.visible = false
		return
	var info := Actions.target_info(t)
	tp_name.text = "%s  %s" % [info["name"], UiText.t("level_short") % int(info["level"])]
	tp_bar.max_value = maxi(1, int(info["hp_max"]))
	tp_bar.value = int(info["hp"])
	var col: Color = S.HP_ALLY if t.team == "party" else (S.HP_ENEMY if selected != null and selected.is_hostile_to(t) else S.MOVE)
	tp_bar.add_theme_stylebox_override("fill", S.bar_fill(col))
	tp_hp.text = "%d/%d%s" % [int(info["hp"]), int(info["hp_max"]), "  (+%d)" % int(info["temp_hp"]) if int(info["temp_hp"]) > 0 else ""]
	for ch in tp_conds.get_children():
		ch.queue_free()
	for cd: Dictionary in info["conditions"]:
		tp_conds.add_child(_chip(UiText.name_of(cd["name"]), S.TEXT_DIM, ""))
	for ch in tp_chips.get_children():
		ch.queue_free()
	var aiming := t != selected and not preview_data.is_empty()
	for r: Variant in (preview_data.get("advantage", []) if aiming else []):
		tp_chips.add_child(_chip(str(r), Color(0.35, 0.62, 0.36), "▲"))
	for r: Variant in (preview_data.get("disadvantage", []) if aiming else []):
		tp_chips.add_child(_chip(str(r), Color(0.72, 0.25, 0.22), "▼"))
	for m: Dictionary in (preview_data.get("mods", []) if aiming else []):
		tp_chips.add_child(_chip("%s %+d" % [m["text"], int(m["value"])], Color(0.35, 0.62, 0.36) if int(m["value"]) > 0 else Color(0.72, 0.25, 0.22), ""))
	if aiming and preview_data.has("warning"):
		tp_chips.add_child(_chip(str(preview_data["warning"]), Color(0.85, 0.2, 0.18), "⚠"))
	target_panel.visible = true
	if aiming and preview_data.has("chance") and preview_data.get("valid", false):
		hit_label.text = "%d%%" % roundi(float(preview_data["chance"]) * 100)
		hit_label.position = screen + Vector2(-26, -96)
		hit_label.visible = true
	else:
		hit_label.visible = false


## 칩(BG3 유리·불리 표시): 색 테두리 둥근 판에 기호 + 글.
func _chip(text: String, color: Color, mark: String) -> Control:
	var p := PanelContainer.new()
	var sb := S.panel(10, color, Color(color, 0.28), 1)
	sb.set_content_margin_all(3)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = ("%s %s" % [mark, text]) if mark != "" else text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", S.TEXT)
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _clear_preview() -> void:
	preview_cell = Vector2i(-1, -1)
	preview_data = {}
	tooltip.visible = false
	if target_panel != null:
		target_panel.visible = false
		hit_label.visible = false
	router.previewed_cell = Vector2i(-1, -1)
	highlights.queue_redraw()


func _compute_preview(cell: Vector2i) -> Dictionary:
	var g: Node = world["grid"]
	var c := selected
	if not g.in_bounds(cell):
		return {}
	if mode == "rt_move":
		var rp: Dictionary = g.find_path(c, cell, -1, party)
		if rp.is_empty():
			return {"valid": false}
		return {"valid": true, "path": rp["path"].slice(0, int(explore.rt_budget.get(c, c.speed()))), "text": UiText.t("rt_move") % int(explore.rt_budget.get(c, c.speed()))}
	if mode.begins_with("act:"):
		var ap: Dictionary = Actions.preview(world, c, mode.trim_prefix("act:"), cell, exploring)
		var ao := {"valid": ap.get("valid", false), "text": "\n".join(PackedStringArray(ap.get("lines", [])))}
		for k: String in ["chance", "advantage", "disadvantage", "mods"]:
			if ap.has(k):
				ao[k] = ap[k]
		if ap.has("warning"):
			ao["warning"] = ap["warning"]  # 아군·중립 공격 경고(BG3 — 붉은 표시)
			ao["text"] = "⚠ %s\n%s" % [ap["warning"], ao["text"]]
		if ap.has("path"):
			ao["path"] = ap["path"]
		if ap.has("area"):
			ao["area"] = ap["area"]
			ao["partial"] = ap.get("partial", [])
			ao["shape"] = ap.get("shape", {})
		return ao
	if exploring:
		return _explore_preview(cell)
	var target: Node = g.creature_at(cell)
	var lines: PackedStringArray = []
	var out := {"valid": true}
	if mode == "move" and target == null:
		var p := Combat.preview_move(world, c, cell)
		if not p.get("valid", false) or p["cost"] > int(c.turn.get("movement", 0)):
			return {"valid": false, "text": UiText.t("blocked") % "-"}
		out["path"] = p["path"]
		out["oa"] = p["opportunity_attacks"].map(func(o: Dictionary) -> Vector2i: return o["cell"])
		lines.append(UiText.t("move_cost") % [p["cost"], int(c.turn["movement"]) - p["cost"]])
		if not out["oa"].is_empty():
			lines.append(UiText.t("opportunity") % out["oa"].size())
	elif target != null and target != c and not target.dead and ((mode == "move" and c.is_hostile_to(target)) or mode == "attack"):
		var p := Combat.preview_attack(world, c, target)
		if not p.get("valid", false):
			return {"valid": false, "text": UiText.t("blocked") % p.get("reason", "")}
		out["chance"] = p["hit_chance"]
		out.merge(Actions.roll_chips(p), true)
		var ffw := Actions.friendly_fire_warning(c, target)
		if ffw != "":
			out["warning"] = ffw
			lines.append("⚠ " + ffw)
		lines.append(UiText.t("hit_chance") % roundi(p["hit_chance"] * 100))
		lines.append(UiText.t("damage_range") % [p["damage"]["min"], p["damage"]["max"], p["damage"]["avg"]])
		if p.has("high_ground"):
			lines.append(UiText.t("high_ground") % p["high_ground"])
		if "근접 위협" in p.get("disadvantage", []):
			lines.append(UiText.t("threatened"))
	elif mode == "shove" and target != null:
		var p := Physics.preview_shove(g, c, target, c.team == target.team)
		if not p["valid"] or g.distance_between(c, target) > 1:
			return {"valid": false, "text": UiText.t("blocked") % p.get("reason", "")}
		out["path"] = p["path"]
		lines.append(UiText.t("shove_chance") % [roundi(p["chance"] * 100), p["distance"]])
		if p["fall_levels"] > 0:
			lines.append(UiText.t("fall") % p["fall_levels"])
		var reacts: Array = world["surfaces"].preview_tile_damage([p["landing"]], "fire")
		if g.surface_id(p["landing"]) != "":
			lines.append(g.surface_id(p["landing"]))
	elif mode == "jump":
		var ok: bool = g.distance(g.cell_of(c), cell) <= Combat.jump_distance(c) and not g.blocks_movement(cell)
		out["valid"] = ok
		out["path"] = [cell]
		var drop: int = g.height(g.cell_of(c)) - g.height(cell)
		lines.append(UiText.t("jump"))
		if drop >= 2:
			lines.append(UiText.t("fall") % drop)
	elif mode.begins_with("spell:"):
		var sid := mode.trim_prefix("spell:")
		var p := Spellcasting.preview(world, c, sid, cell)
		out["valid"] = p["valid"]
		out["area"] = p["cells"]
		out["partial"] = p.get("partial", [])
		out["shape"] = p.get("shape", {})
		lines.append(UiText.name_of(RulesDB.get_entry("spell", sid)["name"]))
		if not p["valid"]:
			lines.append(UiText.t("blocked") % p["reason"])
		for row: Dictionary in p["targets"]:
			var t: Node = row["creature"]
			var check: Dictionary = RulesDB.get_entry("spell", sid)["effects"].get("check", {})
			if row.has("chance") and t == target:
				out["chance"] = row["chance"]  # 커서 옆 확률(내성 주문은 실패 확률)
			if check.get("type") == "save":
				lines.append(UiText.t("fail_chance") % [t.label(), roundi(row["chance"] * 100)])
			elif row.has("chance"):
				lines.append("%s: %s" % [t.label(), UiText.t("hit_chance") % roundi(row["chance"] * 100)])
		if not p["reactions"].is_empty():
			out["reaction_cells"] = p["reactions"].map(func(r: Dictionary) -> Vector2i: return r["cell"])
			var names := {}
			for r: Dictionary in p["reactions"]:
				names[r["reaction"]] = true
			lines.append(UiText.t("reaction_preview") % ", ".join(names.keys()))
	else:
		return {}
	var spread: Array = world["surfaces"].spread_warnings(party)
	if not spread.is_empty():
		lines.append(UiText.t("spread_warning") % ", ".join(spread.map(func(x: Node) -> String: return x.label())))
	out["text"] = "\n".join(lines)
	return out


func _on_confirm(pos: Vector2) -> void:
	if (busy and mode != "rt_move") or selected == null or dlg != null:
		return
	var cell := _pick(pos)
	if not preview_data.get("valid", false) or cell != preview_cell:
		return
	if mode == "rt_move":
		explore.realtime_move(selected, cell)
		_clear_preview()
		_refresh()
	elif mode.begins_with("act:"):
		_act_execute(mode.trim_prefix("act:"), cell)
	elif exploring:
		_explore_execute(cell)
	else:
		_execute(cell)


# ======================================================================
# 탐험(6단계): 이동·은신·상호작용·대화·휴식·저장
# ======================================================================

func _trap_at(cell: Vector2i) -> Dictionary:
	for t: Dictionary in world.get("traps", []):
		if t.get("found", false) and t["state"] == "armed" and Vector2i(int(t["cell"][0]), int(t["cell"][1])) == cell:
			return t
	return {}


func _examine_at(cell: Vector2i) -> Dictionary:
	for e: Dictionary in world.get("examines", []):
		if not e.get("done", false) and Vector2i(int(e["cell"][0]), int(e["cell"][1])) == cell:
			return e
	return {}


## 칸에서 할 수 있는 탐험 행동: {"kind", ...}
func _explore_action(cell: Vector2i) -> Dictionary:
	var g: Node = world["grid"]
	var target: Node = g.creature_at(cell)
	if target != null and target != selected:
		if world.get("at_camp", false) and target in world.get("roster", []):
			return {"kind": "swap", "creature": target}
		if target.has_meta("dialogue") and not target.dead and target.team != "party" and not target.get_meta("dialogue_done", false):
			var aware: bool = target.awareness.values().any(func(a: Dictionary) -> bool: return a.get("state", "") == "alerted")
			if not aware:
				return {"kind": "talk", "creature": target}
		if selected.is_hostile_to(target) and not target.dead:
			return {"kind": "attack", "creature": target}
		return {}
	var obj: Dictionary = g.object_at(cell)
	if obj.get("lock", {}).get("locked", false):
		return {"kind": "lock", "obj": obj}
	if not obj.get("loot", {}).is_empty():
		return {"kind": "loot", "obj": obj}
	var t := _trap_at(cell)
	if not t.is_empty():
		return {"kind": "disarm", "trap": t}
	var e := _examine_at(cell)
	if not e.is_empty():
		return {"kind": "examine", "examine": e}
	return {"kind": "move"}


func _explore_preview(cell: Vector2i) -> Dictionary:
	var g: Node = world["grid"]
	var a := _explore_action(cell)
	var lines: PackedStringArray = []
	var out := {"valid": true}
	match a.get("kind", ""):
		"move":
			if g.blocks_movement(cell):
				return {"valid": false}
			var p: Dictionary = g.find_path(selected, cell, -1, party)
			if p.is_empty():
				var land: Vector2i = explore._jump_spot(selected, cell, party)
				if land.x < 0:
					return {"valid": false, "text": UiText.t("blocked") % "-"}
				out["path"] = [land, cell]
				var drop: int = g.height(g.cell_of(selected)) - g.height(land)
				lines.append(UiText.t("jump"))
				if drop >= 2:
					lines.append(UiText.t("fall") % drop)
			else:
				out["path"] = p["path"]
			if selected.sneaking:
				lines.append(UiText.t("sneaking"))
		"attack":
			lines.append(UiText.t("start_fight"))
			if selected.sneaking:
				lines.append(UiText.t("surprise_hint"))
		"talk":
			lines.append(UiText.t("talk") % a["creature"].label())
		"swap":
			lines.append(UiText.t("swap") % [selected.label(), a["creature"].label()])
		"lock":
			var lk: Dictionary = a["obj"]["lock"]
			var pv := Interact.preview_check(selected, "dex", "sleight_of_hand", int(lk["dc"]))
			lines.append(UiText.t("pick_lock") % [int(lk["dc"]), roundi(pv["chance"] * 100), Interact.count(world, "thieves_tools", selected)])
		"loot":
			lines.append(UiText.t("loot"))
			if a["obj"].get("owner", "") != "":
				lines.append(UiText.t("owned"))
		"disarm":
			var t: Dictionary = a["trap"]
			var pv := Interact.preview_check(selected, "dex", "sleight_of_hand", int(t["dc_disarm"]))
			lines.append(UiText.t("disarm") % [int(t["dc_disarm"]), roundi(pv["chance"] * 100), Interact.count(world, "trap_disarm_kit", selected)])
		"examine":
			var e: Dictionary = a["examine"]
			var pv := Interact.preview_check(selected, e.get("ability", "int"), e.get("skill", "investigation"), int(e["dc"]))
			lines.append(UiText.t("examine") % [UiText.name_of(e.get("name", {"ko": e["id"], "en": e["id"]})), int(e["dc"]), roundi(pv["chance"] * 100)])
		_:
			return {"valid": false}
	out["text"] = "\n".join(lines)
	return out


## 대상 옆까지 걸어간다(이미 옆이면 그대로). 결과: 옆에 섰는가.
func _approach(cell: Vector2i) -> bool:
	var g: Node = world["grid"]
	if g.distance(g.cell_of(selected), cell) <= 1:
		return true
	var best := Vector2i(-1, -1)
	var best_cost := 1 << 20
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var n: Vector2i = cell + Vector2i(dx, dy)
			if n == cell or not g.in_bounds(n) or g.blocks_movement(n) or (g.creature_at(n) != null and g.creature_at(n) != selected):
				continue
			var p: Dictionary = g.find_path(selected, n, -1, party)
			if not p.is_empty() and int(p["cost"]) < best_cost:
				best_cost = int(p["cost"])
				best = n
	if best.x < 0:
		return false
	explore.move_to(selected, best)
	return g.distance(g.cell_of(selected), cell) <= 1 and not world["turns"].in_combat


func _explore_execute(cell: Vector2i) -> void:
	follow = true
	var a := _explore_action(cell)
	_clear_preview()
	match a.get("kind", ""):
		"move":
			explore.move_to(selected, cell)
		"attack":
			views[selected].face_toward(cell)
			explore.hostile_action(selected, a["creature"])
		"talk":
			if _approach(cell):
				_open_dialogue(a["creature"].get_meta("dialogue"), a["creature"])
		"swap":
			var other: Node = a["creature"]
			if Progression.swap(world, selected, other):
				party = world["party"]
				explore.party = party.duplicate()
				explore.leader = other
				selected = other
		"lock":
			if _approach(cell):
				var lk: Dictionary = a["obj"]["lock"]
				var c0: Node = selected
				var open_with := func(res: Dictionary) -> void:
					var r := Interact.open_lock(world, c0, cell, {} if res.is_empty() else {"result": res})
					if r.get("success", false) and a["obj"].has("art_open"):
						a["obj"]["art"] = a["obj"]["art_open"]
					_notify(r)
					map_view.refresh()
					_refresh()
				if lk.get("key", "") != "" and Interact.count(world, lk["key"]) > 0:
					open_with.call({})
				elif Interact.count(world, "thieves_tools", selected) <= 0:
					_notify({"ok": false, "reason": "도둑 도구가 없다"})
				else:
					_visible_roll(c0, "dex", "sleight_of_hand", int(lk["dc"]), UiText.t("pick_lock").get_slice(" DC", 0), open_with)
		"loot":
			if _approach(cell):
				var r := Interact.take_loot(world, selected, cell)
				_notify(r)
				var pd: Dictionary = world.get("pending_dialogue", {})
				if not pd.is_empty():
					world.erase("pending_dialogue")
					if pd["id"] != "":
						_open_dialogue(pd["id"], pd["npc"])
		"disarm":
			if _approach(cell):
				var trap: Dictionary = a["trap"]
				var c1: Node = selected
				if Interact.count(world, "trap_disarm_kit", selected) <= 0:
					_notify({"ok": false, "reason": "함정 해체 도구가 없다"})
				elif trap.get("retry_blocked", false):
					_notify({"ok": false, "reason": "이 함정은 다시 시도할 수 없다"})
				else:
					_visible_roll(c1, "dex", "sleight_of_hand", int(trap["dc_disarm"]), UiText.t("disarm").get_slice(" DC", 0), func(res: Dictionary) -> void:
						_notify(Interact.disarm(world, c1, trap, {"result": res}))
						map_view.refresh()
						_refresh())
		"examine":
			if _approach(cell):
				var ex: Dictionary = a["examine"]
				var c2: Node = selected
				_visible_roll(c2, ex.get("ability", "int"), ex.get("skill", "investigation"), int(ex["dc"]),
					UiText.name_of(ex.get("name", {"ko": ex["id"], "en": ex["id"]})), func(res: Dictionary) -> void:
						var r := Interact.examine(world, c2, ex, {"result": res})
						if r.get("ok", false):
							var txt: Dictionary = r["result"].get("text", {})
							if not txt.is_empty():
								Dice.log_text(UiText.name_of(txt))
						_notify(r)
						_refresh())
	map_view.refresh()
	_refresh()
	_check_combat()


func _use_inspiration() -> bool:
	return dlg_use_insp != null and dlg_use_insp.button_pressed


func _notify(r: Dictionary) -> void:
	if not r.get("ok", true) and r.has("reason"):
		Dice.log_text(r["reason"])


func _toggle_sneak() -> void:
	explore.set_sneak(selected, not selected.sneaking)
	_refresh()
	_check_combat()


func _rest(kind: String) -> void:
	var r: Dictionary = Rest.short_rest(world, party) if kind == "short" else Rest.long_rest(world, party)
	_notify(r)
	_refresh()


func _save() -> void:
	var err := SaveGame.write("quick", world)
	Dice.log_text(UiText.t("saved") if err == OK else UiText.t("blocked") % str(err))
	_refresh()


func _load() -> void:
	var snap := SaveGame.read("quick")
	if snap.is_empty() or not SaveGame.restore(world, snap):
		Dice.log_text(UiText.t("blocked") % "-")
	for v in views.values():
		v.snap()
	map_view.refresh()
	_refresh()


# ---------- 대화창 ----------

func _open_dialogue(id: String, npc: Node) -> void:
	dlg = Dialogue.start(world, id, selected, npc)
	if dlg == null:
		return
	# 대화 카메라(BG3 참고): 두 사람 사이로 다가가 확대, 닫으면 되돌린다
	if npc != null and views.has(npc) and views.has(selected):
		_cam_before = {"pos": cam_target, "zoom": cam_zoom, "follow": follow}
		follow = false
		# 두 사람 가운데에서 화면 70px 아래를 본다(대화창 자리만큼 인물이 위로)
		var mid: Vector3 = (views[npc].position + views[selected].position) / 2.0 - Vector3(0, 70.0 / V.STEP_PX, 0)
		var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
		tw.tween_property(self, "cam_target", mid, 0.45)
		tw.tween_property(self, "cam_zoom", 1.35, 0.45)
	if npc != null and npc.team == "enemy":
		npc.set_meta("dialogue_done", true)
	if npc != null:
		Stealth.face_toward(world["grid"], npc, world["grid"].cell_of(selected))
		views[npc].face_toward(world["grid"].cell_of(selected))
	_show_dialogue()


func _show_dialogue() -> void:
	dlg_panel.visible = true
	hotbar.visible = false
	dlg_text.clear()
	dlg_text.append_text("[font_size=19][color=#c7a35f]%s[/color][/font_size]\n%s\n" % [UiText.name_of(dlg.data["speaker"]), UiText.name_of(dlg.text())])
	for l: Dictionary in dlg.extra_lines:
		dlg_text.append_text("[color=#9ad]%s[/color]\n" % UiText.name_of(l))
	for ch in dlg_options.get_children():
		ch.queue_free()
	if dlg.finished:
		var b := Button.new()
		b.text = UiText.t("close")
		b.pressed.connect(_close_dialogue)
		dlg_options.add_child(b)
	else:
		var n := 1
		for o: Dictionary in dlg.options():
			var b := Button.new()
			var tag := ""
			if o["kind"] == "check":
				tag = "  [DC %d · %d%%]" % [o["dc"], roundi(o["chance"] * 100)]
			elif o["kind"] == "save":
				tag = "  [%s DC %d]" % [o["ability"].to_upper(), o["dc"]]
			b.text = "%d. %s%s" % [n, UiText.name_of(o["text"]), tag]
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.pressed.connect(_choose_option.bind(o["index"]))
			dlg_options.add_child(b)
			n += 1
	dlg_use_insp.text = UiText.t("use_inspiration") % int(world.get("inspiration", 0))
	_update_log()


func _choose_option(index: int) -> void:
	var ck: Dictionary = dlg.option_check(index)
	if not ck.is_empty():
		# 보이는 굴림: 판정 창에서 굴리고(실패하면 영감·전술적 판단) 그 결과로 고른다
		_visible_roll(dlg.speaker, ck["ability"], ck["skill"], int(ck["dc"]), _skill_name(ck["skill"]), func(res: Dictionary) -> void:
			_finish_choice(index, {"result": res}))
		return
	_finish_choice(index, {})


func _finish_choice(index: int, opts: Dictionary) -> void:
	var r: Dictionary = dlg.choose(index, opts)
	if world.has("pending_ui"):
		_close_dialogue()
		_check_combat()
		return
	for k: String in ["check", "save"]:
		if r.has(k):
			var c: Dictionary = r[k]
			dlg_text.append_text("%s\n" % (UiText.t("roll_result") % [int(c["natural"]), int(c["total"]), int(c["dc"]),
				UiText.t("success") if c["success"] else UiText.t("failure")]))
	if dlg.outcome == "hostile":
		_close_dialogue()
		_refresh()
		_check_combat()
		return
	_show_dialogue()
	_refresh()


# ---------- 상점 창 ----------

var shop_panel: PanelContainer


func _open_shop(shop_id: String) -> void:
	if shop_panel == null:
		shop_panel = PanelContainer.new()
		shop_panel.add_theme_stylebox_override("panel", S.panel(18, S.BRONZE, S.BG_DEEP, 2))
		shop_panel.anchor_left = 0.5
		shop_panel.anchor_right = 0.5
		shop_panel.anchor_top = 0.5
		shop_panel.anchor_bottom = 0.5
		shop_panel.offset_left = -330
		shop_panel.offset_right = 330
		shop_panel.offset_top = -220
		shop_panel.offset_bottom = 200
		ui.get_child(0).add_child(shop_panel)
	for ch in shop_panel.get_children():
		ch.queue_free()
	shop_panel.visible = true
	var shop := RulesDB.get_entry("shop", shop_id)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	shop_panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_child(S.title(UiText.name_of(shop.get("name", {"ko": shop_id, "en": shop_id})), 20))
	var gold := Label.new()
	gold.text = "   %s · %s %d" % [selected.label(), UiText.t("gold"), Interact.count(world, "gold", selected)]  # 거래하는 캐릭터의 금화
	gold.add_theme_color_override("font_color", S.GOLD)
	head.add_child(gold)
	v.add_child(head)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	v.add_child(cols)
	var buy := VBoxContainer.new()
	buy.custom_minimum_size = Vector2(300, 0)
	buy.add_child(S.title(UiText.t("buy"), 15))
	for row: Dictionary in Shop.stock(world, shop_id):
		var b := Button.new()
		b.text = "%s ×%d — %dgp" % [UiText.name_of(RulesDB.get_entry("item", row["item"]).get("name", {})), int(row["count"]), int(row["price"])]
		b.disabled = int(row["count"]) <= 0 or Interact.count(world, "gold", selected) < int(row["price"])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void:
			_notify(Shop.buy(world, shop_id, row["item"], selected))
			_open_shop(shop_id))
		buy.add_child(b)
	cols.add_child(buy)
	var sell := VBoxContainer.new()
	sell.custom_minimum_size = Vector2(300, 0)
	sell.add_child(S.title(UiText.t("sell"), 15))
	for item: String in selected.inventory.keys():
		if Interact.count(world, item, selected) <= 0 or RulesDB.get_entry("item", item).get("category", "currency") == "currency":
			continue
		var b := Button.new()
		b.text = "%s ×%d — %dgp" % [UiText.name_of(RulesDB.get_entry("item", item).get("name", {})), Interact.count(world, item, selected), Shop.sell_price(shop_id, item)]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void:
			_notify(Shop.sell(world, shop_id, item, selected))
			_open_shop(shop_id))
		sell.add_child(b)
	cols.add_child(sell)
	var close := Button.new()
	close.text = UiText.t("close")
	close.pressed.connect(func() -> void:
		shop_panel.visible = false
		_refresh())
	v.add_child(close)


# ---------- 판정 창(보이는 굴림 — 2단계, BG3 주사위 창 참고) ----------

var roll_panel: PanelContainer
var _roll_ctx := {}


func _skill_name(skill: String) -> String:
	var ko := {"sleight_of_hand": "손재주", "persuasion": "설득", "intimidation": "위협", "deception": "기만", "insight": "통찰",
		"investigation": "조사", "arcana": "비전", "history": "역사", "perception": "지각", "survival": "생존", "athletics": "운동",
		"acrobatics": "곡예", "stealth": "은신", "religion": "종교", "medicine": "의학", "nature": "자연", "performance": "공연",
		"animal_handling": "동물 조련"}
	return ko.get(skill, skill) if UiText.lang == "ko" else skill.capitalize()


## 판정 창을 띄운다: DC·보너스·성공 확률을 먼저 보여 주고(굴리기), 실패하면 영감 재굴림·전술적 판단을 고른다.
## 끝나면 cb(결과)를 부른다.
func _visible_roll(c: Node, ability: String, skill: String, dc: int, title: String, cb: Callable) -> void:
	_roll_ctx = {"c": c, "ability": ability, "skill": skill, "dc": dc, "title": title, "cb": cb, "result": {}}
	_draw_roll()


func _draw_roll() -> void:
	if roll_panel == null:
		roll_panel = PanelContainer.new()
		roll_panel.add_theme_stylebox_override("panel", S.panel(18, S.BRONZE, S.BG_DEEP, 2))
		roll_panel.anchor_left = 0.5
		roll_panel.anchor_right = 0.5
		roll_panel.anchor_top = 0.5
		roll_panel.anchor_bottom = 0.5
		roll_panel.offset_left = -190
		roll_panel.offset_right = 190
		roll_panel.offset_top = -150
		roll_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		ui.get_child(0).add_child(roll_panel)
	for ch in roll_panel.get_children():
		ch.queue_free()
	roll_panel.visible = true
	var c: Node = _roll_ctx["c"]
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 8)
	roll_panel.add_child(v)
	var t := S.title(UiText.t("roll_title") % _roll_ctx["title"], 20)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var pv := Interact.preview_check(c, _roll_ctx["ability"], _roll_ctx["skill"], _roll_ctx["dc"])
	var info := Label.new()
	info.text = "%s · %s  —  DC %d · %+d · %d%%" % [c.label(), _skill_name(_roll_ctx["skill"]), _roll_ctx["dc"], int(pv["bonus"]), roundi(pv["chance"] * 100)]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_color_override("font_color", S.TEXT_DIM)
	v.add_child(info)
	var res: Dictionary = _roll_ctx["result"]
	var big := S.title("d20" if res.is_empty() else str(int(res["total"])), 44)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not res.is_empty():
		big.add_theme_color_override("font_color", S.HP_ALLY.lightened(0.3) if res["success"] else S.HP.lightened(0.3))
	v.add_child(big)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	if res.is_empty():
		var go := Button.new()
		go.text = UiText.t("roll_go")
		go.pressed.connect(func() -> void:
			_roll_ctx["result"] = Interact.visible_check(world, c, _roll_ctx["ability"], _roll_ctx["skill"], _roll_ctx["dc"])
			_draw_roll())
		row.add_child(go)
		return
	var detail := Label.new()
	detail.text = "d20 %d %+d%s = %d  →  %s" % [int(res["natural"]), int(res["bonus"]),
		(" %+d" % int(res["tactical_roll"])) if res.has("tactical_roll") else "", int(res["total"]),
		UiText.t("success") if res["success"] else UiText.t("failure")]
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(detail)
	v.move_child(detail, 3)
	for opt: String in Interact.reroll_options(world, c, res):
		var b := Button.new()
		b.text = UiText.t("roll_inspiration") % int(world.get("inspiration", 0)) if opt == "inspiration" else UiText.t("roll_tactical") % c.resource(c.cap_resource("check_boost_d10"))
		b.pressed.connect(func() -> void:
			_roll_ctx["result"] = Interact.reroll(world, c, res, opt)
			_draw_roll())
		row.add_child(b)
	var ok := Button.new()
	ok.text = UiText.t("roll_accept")
	ok.pressed.connect(func() -> void:
		roll_panel.visible = false
		var cb: Callable = _roll_ctx["cb"]
		var final: Dictionary = _roll_ctx["result"]
		_roll_ctx = {}
		cb.call(final))
	row.add_child(ok)


var _cam_before := {}


func _close_dialogue() -> void:
	dlg = null
	if not _cam_before.is_empty() and camera != null:
		var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
		tw.tween_property(self, "cam_zoom", _cam_before["zoom"], 0.35)
		follow = _cam_before["follow"]
		_cam_before = {}
	if dlg_panel != null:
		dlg_panel.visible = false
		_refresh()


func _execute(cell: Vector2i) -> void:
	var g: Node = world["grid"]
	var c := selected
	var target: Node = g.creature_at(cell)
	if mode == "move" and target == null:
		Combat.move(world, c, cell)
	elif target != null and target != c and not target.dead and ((mode == "move" and c.is_hostile_to(target)) or mode == "attack"):
		views[c].face_toward(cell)
		Combat.attack(world, c, target)
	elif mode == "shove" and target != null:
		Combat.shove(world, c, target)
	elif mode == "jump":
		Combat.jump(world, c, cell)
	elif mode.begins_with("spell:"):
		var sid := mode.trim_prefix("spell:")
		var plan := Spellcasting.target_plan(c, sid)
		if int(plan["count"]) != 1:
			if _picked_mode != mode:
				_picked = []
				_picked_mode = mode
			if plan["kind"] == "creature" and target == null:
				return
			if not plan["repeat"] and cell in _picked:
				_picked.erase(cell)  # 다시 누르면 빼기
			else:
				_picked.append(cell)
			if int(plan["count"]) > 0 and _picked.size() >= int(plan["count"]):
				_cast_picked()
			else:
				_refresh()
			return
		Spellcasting.cast(world, c, sid, cell)
	map_view.refresh()
	_clear_preview()
	_refresh()
	if world["turns"].check_end():
		_advance()


## 모은 대상으로 시전(다 찼거나 Enter·[시전] — BG3식).
func _cast_picked() -> void:
	if _picked.is_empty() or selected == null or not _picked_mode.begins_with("spell:"):
		return
	var sid := _picked_mode.trim_prefix("spell:")
	var plan := Spellcasting.target_plan(selected, sid)
	var opts := {}
	if plan["kind"] == "cell":
		if _picked.size() > 1:
			opts["second_cell"] = _picked[1]
	else:
		opts["targets"] = _picked.map(func(cc: Vector2i) -> Node: return world["grid"].creature_at(cc)).filter(func(n: Variant) -> bool: return n != null)
	var aim: Vector2i = _picked[0]
	_picked = []
	_picked_mode = ""
	if views.has(selected):
		views[selected].face_toward(aim)
	Spellcasting.cast(world, selected, sid, aim, opts)
	map_view.refresh()
	_clear_preview()
	_refresh()
	if world["turns"].check_end():
		_advance()


func _on_info(pos: Vector2) -> void:
	var cell := _pick(pos)
	var c: Node = world["grid"].creature_at(cell)
	if c == null:
		info_panel.visible = false
		return
	var conds: Array = c.conditions.map(func(i: Dictionary) -> String: return i["id"])
	info_label.text = "%s\n%s\n%s" % [c.label(), UiText.t("hp") % [c.hp, c.hp_max],
		UiText.t("info") % [c.ac(), c.speed(), ", ".join(conds) if not conds.is_empty() else UiText.t("none")]]
	info_panel.visible = true


# ======================================================================
# UI
# ======================================================================

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = S.theme()
	ui.add_child(root)
	# 위: 라운드와 턴 순서 막대
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.position = Vector2(-300, 8)
	top.add_theme_constant_override("separation", 6)
	root.add_child(top)
	round_label = S.title("", 18)
	round_label.add_theme_color_override("font_outline_color", Color.BLACK)
	round_label.add_theme_constant_override("outline_size", 5)
	top.add_child(round_label)
	order_box = HBoxContainer.new()
	order_box.add_theme_constant_override("separation", 4)
	top.add_child(order_box)
	# 왼쪽: 파티 초상
	party_box = VBoxContainer.new()
	party_box.position = Vector2(12, 90)
	party_box.add_theme_constant_override("separation", 8)
	root.add_child(party_box)
	# 왼쪽 위: 캐릭터 창 버튼, 오른쪽 위: 미니맵
	var sheet_btn := Button.new()
	sheet_btn.text = UiText.t("character") + " (I)"
	sheet_btn.position = Vector2(12, 12)
	sheet_btn.focus_mode = Control.FOCUS_NONE
	sheet_btn.pressed.connect(_toggle_sheet)
	root.add_child(sheet_btn)
	var book_btn := Button.new()
	book_btn.text = UiText.t("spells_window") + " (K)"
	book_btn.position = Vector2(150, 12)
	book_btn.focus_mode = Control.FOCUS_NONE
	book_btn.pressed.connect(_toggle_spellbook)
	root.add_child(book_btn)
	minimap = Minimap.new()
	minimap.anchor_left = 1.0
	minimap.anchor_right = 1.0
	minimap.offset_left = -200
	minimap.offset_top = 8
	minimap.offset_right = -10
	minimap.offset_bottom = 198
	minimap.grid = world["grid"]
	root.add_child(minimap)
	# 미니맵 아래: 켜고 끄는 보기 버튼(터치·iPad — H 모든 HP, G 물체 강조)
	var vbox := HBoxContainer.new()
	vbox.anchor_left = 1.0
	vbox.anchor_right = 1.0
	vbox.offset_left = -200
	vbox.offset_right = -10
	vbox.offset_top = 202
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)
	root.add_child(vbox)
	hp_btn = Button.new()
	hp_btn.text = UiText.t("toggle_hp")
	hp_btn.toggle_mode = true
	hp_btn.focus_mode = Control.FOCUS_NONE
	hp_btn.pressed.connect(func() -> void:
		ActorView.reveal_hp = hp_btn.button_pressed
		_refresh())
	vbox.add_child(hp_btn)
	hl_btn = Button.new()
	hl_btn.text = UiText.t("toggle_highlight")
	hl_btn.toggle_mode = true
	hl_btn.focus_mode = Control.FOCUS_NONE
	hl_btn.pressed.connect(func() -> void:
		alt_highlight = hl_btn.button_pressed
		highlights.queue_redraw())
	vbox.add_child(hl_btn)
	# 아래: 단축 막대(BG3 구조 — scenes/ui/hotbar.gd)
	var bottom := VBoxContainer.new()
	bottom.anchor_left = 0.5
	bottom.anchor_right = 0.5
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_bottom = -6
	root.add_child(bottom)
	_build_info_card(bottom)
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_outline_color", Color.BLACK)
	status_label.add_theme_constant_override("outline_size", 4)
	bottom.add_child(status_label)
	cast_now_btn = Button.new()
	cast_now_btn.text = UiText.t("cast_now")
	cast_now_btn.visible = false
	cast_now_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cast_now_btn.pressed.connect(_cast_picked)
	bottom.add_child(cast_now_btn)
	action_box = HBoxContainer.new()
	hotbar = Hotbar.new()
	bottom.add_child(hotbar)
	hotbar.action_chosen.connect(_on_action)
	hotbar.end_turn_pressed.connect(_end_turn)
	hotbar.explore_pressed.connect(_on_explore_button)
	hotbar.passive_toggled.connect(func(id: String) -> void:
		if selected != null:
			Actions.toggle_passive(selected, id)
			_refresh())
	# 오른쪽: 전투 로그
	log_box = RichTextLabel.new()
	log_box.anchor_left = 1.0
	log_box.anchor_right = 1.0
	log_box.offset_left = -330
	log_box.offset_right = -10
	log_box.offset_top = 210
	log_box.offset_bottom = 420
	log_box.scroll_following = true
	log_box.add_theme_font_size_override("normal_font_size", 12)
	log_box.add_theme_color_override("default_color", S.TEXT_DIM)
	var log_bg := S.panel(12, S.BRONZE_DARK, Color(0.05, 0.04, 0.035, 0.72), 1)
	log_bg.shadow_size = 0
	log_box.add_theme_stylebox_override("normal", log_bg)
	root.add_child(log_box)
	# 위 가운데: 대상 정보 막대(BG3 — 이름·레벨·HP·상태·유리/불리 칩)
	target_panel = PanelContainer.new()
	target_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	target_panel.position = Vector2(-210, 86)
	target_panel.custom_minimum_size = Vector2(420, 0)
	target_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tps := S.panel(10, S.BRONZE_DARK, Color(S.BG_DEEP, 0.72), 1)
	tps.set_content_margin_all(6)
	target_panel.add_theme_stylebox_override("panel", tps)
	var tpv := VBoxContainer.new()
	tpv.add_theme_constant_override("separation", 4)
	tpv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_panel.add_child(tpv)
	tp_name = S.title("", 20)
	tp_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tp_name.add_theme_color_override("font_outline_color", Color.BLACK)
	tp_name.add_theme_constant_override("outline_size", 5)
	tpv.add_child(tp_name)
	var bar_box := Control.new()
	bar_box.custom_minimum_size = Vector2(400, 18)
	bar_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tpv.add_child(bar_box)
	tp_bar = S.bar(S.HP_ENEMY, Vector2(400, 18))
	bar_box.add_child(tp_bar)
	tp_hp = Label.new()
	tp_hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tp_hp.size = Vector2(400, 18)
	tp_hp.add_theme_font_size_override("font_size", 13)
	tp_hp.add_theme_color_override("font_outline_color", Color.BLACK)
	tp_hp.add_theme_constant_override("outline_size", 4)
	bar_box.add_child(tp_hp)
	tp_conds = HBoxContainer.new()
	tp_conds.alignment = BoxContainer.ALIGNMENT_CENTER
	tp_conds.add_theme_constant_override("separation", 4)
	tpv.add_child(tp_conds)
	tp_chips = HBoxContainer.new()
	tp_chips.alignment = BoxContainer.ALIGNMENT_CENTER
	tp_chips.add_theme_constant_override("separation", 4)
	tpv.add_child(tp_chips)
	target_panel.visible = false
	root.add_child(target_panel)
	# 커서 옆 확률(BG3 — 노리는 대상 위 큰 %)
	hit_label = S.title("", 26)
	hit_label.add_theme_color_override("font_color", S.TEXT)
	hit_label.add_theme_color_override("font_outline_color", Color.BLACK)
	hit_label.add_theme_constant_override("outline_size", 6)
	hit_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hit_label.visible = false
	root.add_child(hit_label)
	tooltip = PanelContainer.new()
	tooltip_label = Label.new()
	tooltip.add_child(tooltip_label)
	tooltip.visible = false
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tooltip)
	info_panel = PanelContainer.new()
	info_panel.anchor_left = 1.0
	info_panel.anchor_right = 1.0
	info_panel.offset_left = -330
	info_panel.offset_top = 430
	info_label = Label.new()
	info_panel.add_child(info_label)
	info_panel.visible = false
	root.add_child(info_panel)
	dlg_panel = PanelContainer.new()
	dlg_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	dlg_panel.position = Vector2(-330, -330)
	dlg_panel.custom_minimum_size = Vector2(660, 230)
	var dsb := S.panel(18, S.BRONZE, S.BG_DEEP, 2)
	dsb.set_content_margin_all(16)
	dlg_panel.add_theme_stylebox_override("panel", dsb)
	var dv := VBoxContainer.new()
	dlg_panel.add_child(dv)
	dlg_text = RichTextLabel.new()
	dlg_text.bbcode_enabled = true
	dlg_text.fit_content = true
	dlg_text.custom_minimum_size = Vector2(636, 60)
	dv.add_child(dlg_text)
	dlg_options = VBoxContainer.new()
	dv.add_child(dlg_options)
	dlg_use_insp = CheckBox.new()
	dlg_use_insp.visible = false  # 영감 재굴림은 판정 창에서 고른다
	dv.add_child(dlg_use_insp)
	dlg_panel.visible = false
	root.add_child(dlg_panel)
	sheet = CharacterSheet.new()
	sheet.changed.connect(_refresh)
	sheet.select_requested.connect(func(c: Node) -> void:
		if exploring and not c.dead:
			_select(c))  # 탐험 중이면 고른 캐릭터도 바꾼다(BG3), 전투 중에는 보기만
	sheet.spellbook_requested.connect(func(c: Node) -> void:
		sheet.visible = false
		spellbook.show_for(world, c if c != null else selected))  # 위 탭 '주문서'
	root.add_child(sheet)
	spellbook = SpellbookWindow.new()
	spellbook.changed.connect(_refresh)
	root.add_child(spellbook)
	banner = S.title("", 44)
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.add_theme_color_override("font_outline_color", Color.BLACK)
	banner.add_theme_constant_override("outline_size", 8)
	banner.visible = false
	root.add_child(banner)


func _refresh() -> void:
	var tm: Node = world["turns"]
	party = world.get("party", party)
	world["active"] = selected  # 받는 사람을 안 정한 소지품(대화 보상 등)은 고른 캐릭터에게
	_update_info_card()
	for v in views.values():
		v.current = v.creature in tm.current_group()
		v.selected = v.creature == selected
		v.sync()
	round_label.text = UiText.t("exploring") if exploring else UiText.t("round") % tm.round_number
	for ch in order_box.get_children():
		ch.queue_free()
	for c: Node in tm.order:
		if c.dead:
			continue
		order_box.add_child(_order_portrait(c, c in tm.current_group()))
	for ch in party_box.get_children():
		ch.queue_free()
	for c: Node in party:
		party_box.add_child(_party_card(c))
	log_box.visible = log_forced or not exploring
	for m: Node in world.get("summons", []):
		if is_instance_valid(m) and not views.has(m) and world["grid"].creatures().has(m):
			var mv: Node3D = ActorView.new()
			mv.ground = map_view.ground_at
			mv.setup(m, world["grid"])
			sorted.add_child(mv)
			views[m] = mv
	minimap.party = party
	minimap.center_creature = selected if selected != null else (party[0] if not party.is_empty() else null)
	if sheet.visible and selected != null:
		var who: Node = sheet.creature if sheet.creature != null and is_instance_valid(sheet.creature) and sheet.creature in party else selected
		sheet.show_for(world, who, sheet.note.text)
	if spellbook.visible and selected != null and selected != spellbook.creature:
		spellbook.show_for(world, selected)
	if dlg != null:
		hotbar.visible = false  # 대화 중에는 단축 막대를 숨긴다(BG3)
	elif selected != null and selected.team == "party" and (exploring or not busy):
		hotbar.show_for(world, selected, exploring, _explore_buttons() if exploring else [])
	else:
		hotbar.visible = false
	if exploring and selected != null:
		status_label.text = UiText.t("explore_status") % [selected.label(), selected.level, int(world.get("xp", 0)), int(world.get("inspiration", 0)),
			Interact.count(world, "gold", selected), Interact.count(world, "thieves_tools", selected), Interact.count(world, "trap_disarm_kit", selected)]
	elif busy:
		status_label.text = UiText.t("enemy_turn")
	else:
		status_label.text = ""
	if _picked_mode != "" and _picked_mode != mode:
		_picked = []
		_picked_mode = ""
	if cast_now_btn != null:
		cast_now_btn.visible = not _picked.is_empty() and not busy
	if not _picked.is_empty() and selected != null:
		var plan := Spellcasting.target_plan(selected, _picked_mode.trim_prefix("spell:"))
		var names: Array = _picked.map(func(cc: Vector2i) -> String:
			var n: Node = world["grid"].creature_at(cc)
			return n.label() if n != null else str(cc))
		status_label.text = UiText.t("pick_targets") % [_picked.size(), str(plan["count"]) if int(plan["count"]) > 0 else "∞", ", ".join(names)]
	_update_log()
	map_view.refresh()
	if vfx != null:
		vfx.sync_surfaces()


## 이니셔티브 막대의 초상 하나(BG3: 둥근 틀, 파티 청록·적 붉은 아래띠, 현재 턴은 금빛 테두리).
func _order_portrait(c: Node, current: bool) -> Control:
	var p := PanelContainer.new()
	var sb := S.panel(8, S.GOLD if current else S.BRONZE_DARK, S.BG_DEEP, 2 if current else 1)
	sb.set_content_margin_all(2)
	sb.shadow_size = 6 if current else 2
	if current:
		sb.shadow_color = Color(S.GOLD, 0.35)
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	p.add_child(v)
	var tr := TextureRect.new()
	tr.texture = S.portrait_tex(c)
	var k := 1.18 if current else 1.0
	tr.custom_minimum_size = Vector2(42, 46) * k
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	v.add_child(tr)
	var bar := S.bar(S.HP_ALLY if c.team == "party" else S.HP_ENEMY, Vector2(42 * k, 5))
	bar.max_value = c.hp_max
	bar.value = c.hp
	bar.visible = c.team == "party" or ActorView.reveal_hp  # BG3: 적 HP는 마우스를 올렸을 때만(대상 막대)
	v.add_child(bar)
	p.tooltip_text = "%s  HP %d/%d  (%d)" % [c.label(), c.hp, c.hp_max, c.initiative] if c.team == "party" else "%s  (%d)" % [c.label(), c.initiative]
	return p


## 왼쪽 파티 초상(BG3: 세로 사각 초상, 아래 HP 글자, 옆에 상태 아이콘). 누르면 선택.
func _party_card(c: Node) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var b := Button.new()
	b.custom_minimum_size = Vector2(70, 86)
	b.focus_mode = Control.FOCUS_NONE
	var sel := c == selected
	var st := S.panel(10, S.GOLD if sel else S.BRONZE, S.BG_SLOT, 2 if sel else 1)
	st.set_content_margin_all(0)
	if sel:
		st.shadow_color = Color(S.GOLD, 0.4)
	b.add_theme_stylebox_override("normal", st)
	var hv: StyleBoxFlat = st.duplicate()
	hv.border_color = S.GOLD_SOFT
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", hv)
	var tr := TextureRect.new()
	tr.texture = S.portrait_tex(c, Rect2(144 + 10, 2, 52, 60))
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.offset_left = 3
	tr.offset_top = 3
	tr.offset_right = -3
	tr.offset_bottom = -3
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if c.dead:
		tr.modulate = Color(0.35, 0.35, 0.35)
	elif c.is_down():
		tr.modulate = Color(0.75, 0.5, 0.5)
	b.add_child(tr)
	var bar := S.bar(S.HP, Vector2(64, 5))
	bar.max_value = c.hp_max
	bar.value = c.hp
	bar.position = Vector2(3, 66)
	b.add_child(bar)
	var hpl := Label.new()
	hpl.text = "%d/%d" % [c.hp, c.hp_max]
	hpl.add_theme_font_size_override("font_size", 12)
	hpl.add_theme_color_override("font_outline_color", Color.BLACK)
	hpl.add_theme_constant_override("outline_size", 4)
	hpl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hpl.position = Vector2(0, 68)
	hpl.size = Vector2(70, 16)
	hpl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hpl)
	b.tooltip_text = "%s%s" % [c.label(), "  (%s)" % UiText.t("linked") if exploring and explore.linked.get(c, false) else ""]
	b.pressed.connect(_select.bind(c))
	h.add_child(b)
	var icons := VBoxContainer.new()
	icons.add_theme_constant_override("separation", 2)
	for inst: Dictionary in c.conditions.slice(0, 4):
		var path := "res://assets/statuses/%s.webp" % CONDITION_ICON.get(inst["id"], "debuff")
		if ResourceLoader.exists(path):
			var ic := TextureRect.new()
			ic.texture = load(path)
			ic.custom_minimum_size = Vector2(18, 18)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.material = S.icon_material()
			ic.tooltip_text = inst["id"]
			icons.add_child(ic)
	h.add_child(icons)
	return h


func _toggle_sheet() -> void:
	if sheet.visible:
		sheet.visible = false
	elif selected != null:
		spellbook.visible = false
		sheet.show_for(world, selected)


func _toggle_spellbook() -> void:
	if spellbook.visible:
		spellbook.visible = false
	elif selected != null:
		sheet.visible = false
		spellbook.show_for(world, selected)


## 탐험 탭 버튼(BG3의 은신·묶기·휴식·저장 자리)
func _explore_buttons() -> Array:
	var out: Array = []
	var linked: bool = explore.linked.get(selected, false)
	out.append({"id": "link", "text": UiText.t("linked") if linked else UiText.t("unlinked"), "pressed": linked})
	out.append({"id": "regroup", "text": UiText.t("regroup")})
	out.append({"id": "short_rest", "text": UiText.t("short_rest") % int(world.get("short_rests_left", Rest.SHORT_RESTS))})
	out.append({"id": "long_rest", "text": UiText.t("long_rest") % Rest.supplies(world)})
	if Progression.can_level_up(world, selected):
		out.append({"id": "level_up", "text": UiText.t("level_up") % (selected.level + 1)})
	out.append({"id": "save", "text": UiText.t("save")})
	out.append({"id": "load", "text": UiText.t("load")})
	return out


func _on_explore_button(id: String) -> void:
	match id:
		"sneak":
			_toggle_sneak()
		"link":
			explore.link(selected, not explore.linked.get(selected, false))
			_refresh()
		"regroup":
			explore.regroup()
			_refresh()
			_check_combat()
		"short_rest":
			_rest("short")
		"long_rest":
			_go_camp()
		"level_up":
			_open_level_up()
		"save":
			_save()
		"load":
			_load()


## 레벨 업: 올릴 클래스 고르기(지금 클래스 + 새 클래스 — 멀티클래스, 선행 조건 없음 BG3식).
func _open_level_up() -> void:
	var menu := PopupMenu.new()
	add_child(menu)
	var choices: Array = Progression.level_up_choices(selected)
	for i in choices.size():
		var cid: String = choices[i]
		var name := UiText.name_of(RulesDB.get_entry("class", cid).get("name", {"ko": cid, "en": cid}))
		var lv: int = selected.class_level(cid) if selected.class_levels.has(cid) or cid == selected.class_id else 0
		menu.add_item("%s %d → %d" % [name, lv, lv + 1] if lv > 0 else UiText.t("new_class") % name, i)
	menu.id_pressed.connect(func(idx: int) -> void:
		var cid: String = choices[idx]
		var extra: Dictionary = {} if selected.class_levels.has(cid) or cid == selected.class_id else Progression.new_class_extra(selected, cid)
		menu.queue_free()
		if Progression.asi_level_for(selected, cid) > 0:
			_open_feat_pick(cid, extra)  # 재주 고르기(BG3 — 능력치 향상 레벨)
			return
		Progression.level_up(world, selected, cid, extra)
		_refresh())
	menu.popup_hide.connect(func() -> void:
		if is_instance_valid(menu):
			menu.queue_free())
	menu.position = Vector2i(get_viewport().get_mouse_position())
	menu.popup()


## 재주 고르기(BG3식 레벨 업 창): 능력치 +2 또는 일반 재주. 명세 검사를 통과하는 것만 보인다(scripts/rules/progression.gd feat_choices).
func _open_feat_pick(cid: String, extra: Dictionary) -> void:
	var menu := PopupMenu.new()
	add_child(menu)
	var picks: Array = Progression.feat_choices(selected, cid)
	menu.add_separator(UiText.t("pick_feat"))
	for i in picks.size():
		menu.add_item(UiText.name_of(picks[i]["name"]), i)
	menu.id_pressed.connect(func(idx: int) -> void:
		var ex: Dictionary = extra.duplicate()
		ex["asi_pick"] = picks[idx]["pick"]
		Progression.level_up(world, selected, cid, ex)
		menu.queue_free()
		_refresh())
	menu.popup_hide.connect(func() -> void:
		if is_instance_valid(menu):
			menu.queue_free())
	menu.position = Vector2i(get_viewport().get_mouse_position())
	menu.popup()


## 단축 막대에서 행동을 골랐다: 자신 대상이면 바로 실행, 아니면 대상 고르기(미리보기 → 확정).
func _on_action(key: String) -> void:
	if selected == null or (busy and not exploring):
		return
	if not exploring and not world["turns"].is_current(selected):
		return
	if mode == "act:" + key:
		_cancel_mode()  # 고른 칸을 다시 누르면 취소(터치에 Esc가 없다)
		return
	var d := Actions.def_of(key)
	if d.get("target", "self") == "self":
		if touch_ui and armed_self != key:
			# 터치: 첫 누르기 = 고르고 설명 카드, 같은 칸 다시 누르기 = 실행
			_cancel_mode()
			armed_self = key
			hotbar.selected_key = key
			_refresh()
			return
		armed_self = ""
		_act_execute(key, world["grid"].cell_of(selected))
		return
	armed_self = ""
	mode = "act:" + key
	hotbar.selected_key = key
	_clear_preview()
	_refresh()


func _act_execute(key: String, cell: Vector2i) -> void:
	var r: Dictionary = Actions.execute(world, selected, key, cell, exploring)
	_notify(r)
	if r.get("ok", false) and world["grid"].creature_at(cell) != null and cell != world["grid"].cell_of(selected):
		views[selected].face_toward(cell)
	mode = "move"
	armed_self = ""
	hotbar.selected_key = ""
	map_view.refresh()
	_clear_preview()
	_refresh()
	if exploring:
		_check_combat()
	elif world["turns"].check_end():
		_advance()


func _action_button(text: String, cb: Callable, pressed: bool = false) -> void:
	var b := Button.new()
	b.text = text
	b.toggle_mode = pressed
	b.button_pressed = pressed
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(cb)
	action_box.add_child(b)


func _update_log() -> void:
	var lines: Array = Dice.roll_log
	for i in range(_log_seen, lines.size()):
		var e: Dictionary = lines[i]
		if e["kind"] == "text":
			log_box.append_text(e["text"] + "\n")
	_log_seen = lines.size()
