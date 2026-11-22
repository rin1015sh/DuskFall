extends Node2D
## 시험 맵 화면: 탐험(6단계, 실시간) → 발견·적대 행동이면 전투(4단계 최소 화면, 턴제).
## 규칙은 scripts/rules가 처리하고, 이 씬은 판정 결과를 그리고 입력을 '미리보기 → 확정'으로 넘긴다.
##
## 실행 인자(-- 뒤): --combat(탐험 없이 바로 전투), --autoplay(파티도 AI, 바로 전투), --seed=<n>, --lang=en, --fast(지연 없음),
##   --sneak(탐험: 은신 켜고 시작), --dialogue=<생물 이름>(탐험: 그 생물과 대화를 열고 시작), --goto=x,y(탐험: 리더 이동),
##   --shot=<png 경로> --frames=<n>(n프레임 뒤 캡처하고 끝), --steps=<n>(캡처 전 n턴 진행),
##   --select=<생물 이름> --mode=<move|attack|shove|jump|spell:<id>> --preview=x,y 또는 생물 이름(캡처할 미리보기)

const Roster := preload("res://scenes/battle/test_roster.gd")
const V := preload("res://scenes/battle/view3q.gd")
const MapLoader := preload("res://scripts/rules/map_loader.gd")
const MapView := preload("res://scenes/battle/map_view.gd")
const ActorView := preload("res://scenes/battle/actor_view.gd")
const InputRouter := preload("res://scenes/battle/input_router.gd")
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

var world: Dictionary
var party: Array = []
var foes: Array = []
var map_view: Node2D
var sorted: Node2D
var views := {}  # creature → ActorView
var camera: Camera2D
var router: RefCounted
var highlights: Node2D

var selected: Node = null
var mode := "move"
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
var info_panel: PanelContainer
var info_label: Label
var banner: Label
var _log_seen := 0
var _frames := 0
# 탐험
var explore: Node
var exploring := false
var _tick_acc := 0.0
var dlg: RefCounted = null
var dlg_panel: PanelContainer
var dlg_text: RichTextLabel
var dlg_options: VBoxContainer
var dlg_use_insp: CheckBox


class Highlights extends Node2D:
	var scene: Node

	func _draw() -> void:
		var g: Node = scene.world["grid"]
		var d: Dictionary = scene.preview_data
		if scene.exploring:
			_explore_marks(g)
		for c: Vector2i in d.get("area", []):
			_cell(g, c, Color(1, 0.55, 0.1, 0.35), Color(1, 0.6, 0.2, 0.9))
		for c: Vector2i in d.get("path", []):
			_cell(g, c, Color(0.3, 0.6, 1.0, 0.3), Color(0.4, 0.7, 1.0, 0.8))
		for c: Vector2i in d.get("reaction_cells", []):
			_cell(g, c, Color(0.2, 1.0, 1.0, 0.25), Color(0.2, 1.0, 1.0, 0.9))
		for c: Vector2i in d.get("spread", []):
			_cell(g, c, Color(1, 0.3, 0.0, 0.15), Color(1, 0.3, 0.0, 0.9))
		for c: Vector2i in d.get("oa", []):
			var p := V.top(c, g.height(c))
			draw_line(p + Vector2(-10, -10), p + Vector2(10, 10), Color.RED, 4)
			draw_line(p + Vector2(10, -10), p + Vector2(-10, 10), Color.RED, 4)
		var cell: Vector2i = scene.preview_cell
		if g.in_bounds(cell):
			var col := Color(1, 1, 1, 0.9) if d.get("valid", true) else Color(1, 0.2, 0.2, 0.9)
			_cell(g, cell, Color(1, 1, 1, 0.08), col)

	## 탐험 표시: 은신 중이면 적 시야 원뿔(칸 빛 단계별 색 — 5단계), 찾은 함정(붉게), 살펴볼 것(노랗게).
	func _explore_marks(g: Node) -> void:
		var sneaking := false
		for p: Node in scene.party:
			sneaking = sneaking or p.sneaking
		if sneaking:
			for o: Node in g.creatures():
				if o.dead or o.team == "party" or o.is_incapacitated():
					continue
				for c in Stealth.cone_cells(g, o):
					var l: int = g.light_at(c)
					if l == 2:
						_cell(g, c, Color(1, 0.15, 0.1, 0.30), Color(1, 0.2, 0.1, 0.0))
					elif l == 1:
						_cell(g, c, Color(1, 0.55, 0.1, 0.18), Color(1, 0.5, 0.1, 0.0))
		for t: Dictionary in scene.world.get("traps", []):
			if t.get("found", false) and t["state"] == "armed":
				var tc := Vector2i(int(t["cell"][0]), int(t["cell"][1]))
				_cell(g, tc, Color(1, 0, 0, 0.35), Color(1, 0.1, 0.1, 1.0))
		for e: Dictionary in scene.world.get("examines", []):
			if not e.get("done", false):
				var ec := Vector2i(int(e["cell"][0]), int(e["cell"][1]))
				_cell(g, ec, Color(1, 0.9, 0.3, 0.06), Color(1, 0.9, 0.3, 0.7))

	func _cell(g: Node, c: Vector2i, fill: Color, line: Color) -> void:
		var r: Rect2 = V.top_rect(g, c).grow(-2)
		draw_rect(r, fill)
		draw_rect(r, line, false, 2.0)


func _ready() -> void:
	_parse_args()
	UiText.lang = args.get("lang", "ko")
	Dice.set_seed(int(args.get("seed", "7")))
	var b := Roster.build()
	world = b["world"]
	party = b["party"]
	foes = b["foes"]
	for n: Node in [world["grid"], world["surfaces"], world["reactions"], world["turns"]]:
		add_child(n)
	for c: Node in party + foes:
		add_child(c)
	# 반응: 파티 기본은 자동(매번 묻기 팝업은 반응 대기 구조와 함께 다음 단계)
	for c: Node in party:
		for r: String in c.known_reactions:
			c.reaction_settings[r] = "auto"
	sorted = Node2D.new()
	sorted.y_sort_enabled = true
	map_view = MapView.new()
	add_child(map_view)
	add_child(sorted)
	map_view.build(world["grid"], sorted, MapLoader.load_map("test_arena"))
	for c: Node in party + foes:
		var v: Node2D = ActorView.new()
		v.setup(c, world["grid"])
		sorted.add_child(v)
		views[c] = v
	highlights = Highlights.new()
	highlights.scene = self
	highlights.z_index = 50
	add_child(highlights)
	camera = Camera2D.new()
	camera.position = V.ground(world["grid"].size / 2) - Vector2(0, 40)
	camera.zoom = Vector2(0.92, 0.92)
	RenderingServer.set_default_clear_color(Color("0c0b0e"))
	add_child(camera)
	router = InputRouter.new()
	router.cell_at = func(pos: Vector2) -> Vector2i: return V.pick(world["grid"], _to_world(pos))
	router.preview.connect(_on_preview)
	router.confirm.connect(_on_confirm)
	router.info.connect(_on_info)
	router.pan.connect(func(delta: Vector2) -> void: camera.position -= delta / camera.zoom.x)
	router.zoom.connect(_on_zoom)
	EventBus.on_enter_tile.connect(func(c: Object, _cell: Vector2i) -> void:
		if views.has(c):
			views[c].sync())
	explore = Exploration.new()
	add_child(explore)
	explore.setup(world, party)
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
	if args.has("dialogue"):
		for o: Node in foes:
			if o.name == args["dialogue"]:
				_open_dialogue(o.get_meta("dialogue", ""), o)
	if args.has("preview"):
		var pp: PackedStringArray = args["preview"].split(",")
		_show_preview(Vector2i(int(pp[0]), int(pp[1])))
	_check_combat()


func _begin_battle() -> void:
	exploring = false
	if not world["turns"].in_combat:
		world["turns"].start_combat("arena")
	selected = null
	_refresh()
	_advance()


## 탐험 중 전투가 시작됐으면(발견·적대 행동) 턴제로 넘어간다.
func _check_combat() -> void:
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


func _to_world(screen: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen


func _on_zoom(factor: float, _at: Vector2) -> void:
	var z := clampf(camera.zoom.x * factor, 0.4, 2.2)
	camera.zoom = Vector2(z, z)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var pan := {KEY_LEFT: Vector2(-40, 0), KEY_RIGHT: Vector2(40, 0), KEY_UP: Vector2(0, -40), KEY_DOWN: Vector2(0, 40)}
		if pan.has(event.keycode):
			camera.position += pan[event.keycode]
		elif event.keycode == KEY_ESCAPE:
			_clear_preview()
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
	var rects: Array = []
	for c: Node in views.keys():
		if not c.dead:
			rects.append([views[c].screen_rect(), views[c].position.y])
	map_view.update_occlusion(rects)
	_frames += 1
	if args.has("shot") and _frames == int(args.get("frames", "30")):
		get_viewport().get_texture().get_image().save_png(args["shot"])
		get_tree().quit()


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
		var ai: bool = c.team != "party" or args.has("autoplay") or steps_left > 0
		if not ai:
			if not group.has(selected):
				selected = group[0]
			busy = false
			_refresh()
			if args.has("select"):
				for m: Node in group:
					if m.name == args["select"]:
						selected = m
			if args.has("mode"):
				mode = args["mode"]
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
			# 이기면 탐험으로 돌아간다
			exploring = true
			selected = party.filter(func(p: Node) -> bool: return not p.dead)[0]
			explore.leader = selected
			mode = "move"
			_refresh()


func _end_turn() -> void:
	if busy or selected == null:
		return
	_clear_preview()
	world["turns"].end_turn(selected)
	selected = null
	_advance()


func _select(c: Node) -> void:
	if exploring:
		if c.dead:
			return
		selected = c
		explore.leader = c
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
	if busy or selected == null or dlg != null:
		return
	_show_preview(V.pick(world["grid"], _to_world(pos)))


func _show_preview(cell: Vector2i) -> void:
	preview_cell = cell
	preview_data = _compute_preview(cell)
	preview_data["spread"] = world["surfaces"].preview_spread()
	highlights.queue_redraw()
	var text: String = preview_data.get("text", "")
	tooltip.visible = text != ""
	tooltip_label.text = text
	var screen := get_canvas_transform() * V.top(cell, world["grid"].height(cell))
	tooltip.position = screen + Vector2(24, -60)


func _clear_preview() -> void:
	preview_cell = Vector2i(-1, -1)
	preview_data = {}
	tooltip.visible = false
	router.previewed_cell = Vector2i(-1, -1)
	highlights.queue_redraw()


func _compute_preview(cell: Vector2i) -> Dictionary:
	var g: Node = world["grid"]
	var c := selected
	if not g.in_bounds(cell):
		return {}
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
	elif (mode == "move" or mode == "attack") and target != null and c.is_hostile_to(target):
		var p := Combat.preview_attack(world, c, target)
		if not p.get("valid", false):
			return {"valid": false, "text": UiText.t("blocked") % p.get("reason", "")}
		lines.append(UiText.t("hit_chance") % roundi(p["hit_chance"] * 100))
		lines.append(UiText.t("damage_range") % [p["damage"]["min"], p["damage"]["max"], p["damage"]["avg"]])
		if p.has("high_ground"):
			lines.append(UiText.t("high_ground") % p["high_ground"])
		if "근접 위협" in p.get("disadvantage", []):
			lines.append(UiText.t("threatened"))
	elif mode == "shove" and target != null:
		var p := Physics.preview_shove(g, c, target, not c.is_hostile_to(target))
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
		lines.append(UiText.name_of(RulesDB.get_entry("spell", sid)["name"]))
		if not p["valid"]:
			lines.append(UiText.t("blocked") % p["reason"])
		for row: Dictionary in p["targets"]:
			var t: Node = row["creature"]
			var check: Dictionary = RulesDB.get_entry("spell", sid)["effects"].get("check", {})
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
	if busy or selected == null or dlg != null:
		return
	var cell := V.pick(world["grid"], _to_world(pos))
	if not preview_data.get("valid", false) or cell != preview_cell:
		return
	if exploring:
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
		if target.has_meta("dialogue") and not target.dead and target.team != "party":
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
				return {"valid": false, "text": UiText.t("blocked") % "-"}
			out["path"] = p["path"]
			if selected.sneaking:
				lines.append(UiText.t("sneaking"))
		"attack":
			lines.append(UiText.t("start_fight"))
			if selected.sneaking:
				lines.append(UiText.t("surprise_hint"))
		"talk":
			lines.append(UiText.t("talk") % a["creature"].label())
		"lock":
			var lk: Dictionary = a["obj"]["lock"]
			var pv := Interact.preview_check(selected, "dex", "sleight_of_hand", int(lk["dc"]))
			lines.append(UiText.t("pick_lock") % [int(lk["dc"]), roundi(pv["chance"] * 100), Interact.count(world, "thieves_tools")])
		"loot":
			lines.append(UiText.t("loot"))
			if a["obj"].get("owner", "") != "":
				lines.append(UiText.t("owned"))
		"disarm":
			var t: Dictionary = a["trap"]
			var pv := Interact.preview_check(selected, "dex", "sleight_of_hand", int(t["dc_disarm"]))
			lines.append(UiText.t("disarm") % [int(t["dc_disarm"]), roundi(pv["chance"] * 100), Interact.count(world, "trap_disarm_kit")])
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
		"lock":
			if _approach(cell):
				var r := Interact.open_lock(world, selected, cell, {"inspiration": _use_inspiration()})
				if r.get("success", false) and a["obj"].has("art_open"):
					a["obj"]["art"] = a["obj"]["art_open"]
				_notify(r)
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
				_notify(Interact.disarm(world, selected, a["trap"], {"inspiration": _use_inspiration()}))
		"examine":
			if _approach(cell):
				var r := Interact.examine(world, selected, a["examine"], {"inspiration": _use_inspiration()})
				if r.get("ok", false):
					var txt: Dictionary = r["result"].get("text", {})
					if not txt.is_empty():
						Dice.log_text(UiText.name_of(txt))
				_notify(r)
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
	if npc != null:
		Stealth.face_toward(world["grid"], npc, world["grid"].cell_of(selected))
		views[npc].face_toward(world["grid"].cell_of(selected))
	_show_dialogue()


func _show_dialogue() -> void:
	dlg_panel.visible = true
	dlg_text.clear()
	dlg_text.append_text("[b]%s[/b]\n%s\n" % [UiText.name_of(dlg.data["speaker"]), UiText.name_of(dlg.text())])
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
	var r: Dictionary = dlg.choose(index, {"inspiration": _use_inspiration()})
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


func _close_dialogue() -> void:
	dlg = null
	if dlg_panel != null:
		dlg_panel.visible = false


func _execute(cell: Vector2i) -> void:
	var g: Node = world["grid"]
	var c := selected
	var target: Node = g.creature_at(cell)
	if mode == "move" and target == null:
		Combat.move(world, c, cell)
	elif (mode == "move" or mode == "attack") and target != null and c.is_hostile_to(target):
		views[c].face_toward(cell)
		Combat.attack(world, c, target)
	elif mode == "shove" and target != null:
		Combat.shove(world, c, target)
	elif mode == "jump":
		Combat.jump(world, c, cell)
	elif mode.begins_with("spell:"):
		Spellcasting.cast(world, c, mode.trim_prefix("spell:"), cell)
	map_view.refresh()
	_clear_preview()
	_refresh()
	if world["turns"].check_end():
		_advance()


func _on_info(pos: Vector2) -> void:
	var cell := V.pick(world["grid"], _to_world(pos))
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
	ui.add_child(root)
	# 위: 라운드와 턴 순서 막대
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.position = Vector2(-300, 8)
	top.add_theme_constant_override("separation", 6)
	root.add_child(top)
	round_label = Label.new()
	top.add_child(round_label)
	order_box = HBoxContainer.new()
	order_box.add_theme_constant_override("separation", 4)
	top.add_child(order_box)
	# 왼쪽: 파티 초상
	party_box = VBoxContainer.new()
	party_box.position = Vector2(10, 70)
	root.add_child(party_box)
	# 아래: 행동 막대와 자원
	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.position = Vector2(-430, -86)
	root.add_child(bottom)
	status_label = Label.new()
	bottom.add_child(status_label)
	action_box = HBoxContainer.new()
	bottom.add_child(action_box)
	# 오른쪽: 전투 로그
	log_box = RichTextLabel.new()
	log_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	log_box.position = Vector2(-410, 60)
	log_box.size = Vector2(400, 300)
	log_box.scroll_following = true
	log_box.add_theme_font_size_override("normal_font_size", 13)
	var log_bg := StyleBoxFlat.new()
	log_bg.bg_color = Color(0, 0, 0, 0.55)
	log_box.add_theme_stylebox_override("normal", log_bg)
	root.add_child(log_box)
	tooltip = PanelContainer.new()
	tooltip_label = Label.new()
	tooltip.add_child(tooltip_label)
	tooltip.visible = false
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tooltip)
	info_panel = PanelContainer.new()
	info_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	info_panel.position = Vector2(-410, 370)
	info_label = Label.new()
	info_panel.add_child(info_label)
	info_panel.visible = false
	root.add_child(info_panel)
	dlg_panel = PanelContainer.new()
	dlg_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	dlg_panel.position = Vector2(-330, -330)
	dlg_panel.custom_minimum_size = Vector2(660, 230)
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = Color(0.06, 0.05, 0.07, 0.92)
	dsb.border_color = Color(0.75, 0.62, 0.35)
	dsb.set_border_width_all(2)
	dsb.set_content_margin_all(12)
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
	dv.add_child(dlg_use_insp)
	dlg_panel.visible = false
	root.add_child(dlg_panel)
	banner = Label.new()
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.add_theme_font_size_override("font_size", 48)
	banner.visible = false
	root.add_child(banner)


func _refresh() -> void:
	var tm: Node = world["turns"]
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
		var l := Label.new()
		l.text = " %s %d " % [c.label(), c.hp]
		var sb := StyleBoxFlat.new()
		sb.bg_color = (Color(0.15, 0.35, 0.2) if c.team == "party" else Color(0.45, 0.15, 0.12))
		if c in tm.current_group():
			sb.border_color = Color(1, 0.85, 0.2)
			sb.set_border_width_all(2)
		l.add_theme_stylebox_override("normal", sb)
		order_box.add_child(l)
	for ch in party_box.get_children():
		ch.queue_free()
	for c: Node in party:
		var btn := Button.new()
		btn.text = "%s  %s%s" % [c.label(), UiText.t("hp") % [c.hp, c.hp_max], "  ✝" if c.dead else ""]
		btn.custom_minimum_size = Vector2(190, 44)
		btn.toggle_mode = true
		btn.button_pressed = c == selected
		var art: Dictionary = c.get_meta("art", {})
		if art.has("sheet"):
			var at := AtlasTexture.new()
			at.atlas = load(art["sheet"])
			at.region = Rect2(144, 0, 72, 54)
			btn.icon = at
		btn.pressed.connect(_select.bind(c))
		party_box.add_child(btn)
	for ch in action_box.get_children():
		ch.queue_free()
	if exploring and selected != null:
		_action_button(UiText.t("sneak_on") if selected.sneaking else UiText.t("sneak_off"), _toggle_sneak, selected.sneaking)
		var linked: bool = explore.linked.get(selected, false)
		_action_button(UiText.t("linked") if linked else UiText.t("unlinked"), func() -> void: explore.link(selected, not linked); _refresh(), linked)
		_action_button(UiText.t("short_rest") % int(world.get("short_rests_left", Rest.SHORT_RESTS)), _rest.bind("short"))
		_action_button(UiText.t("long_rest") % Rest.supplies(world), _rest.bind("long"))
		_action_button(UiText.t("save"), _save)
		_action_button(UiText.t("load"), _load)
		status_label.text = UiText.t("explore_status") % [selected.label(), int(world.get("inspiration", 0)),
			Interact.count(world, "gold"), Interact.count(world, "thieves_tools"), Interact.count(world, "trap_disarm_kit")]
	elif selected != null and selected.team == "party" and not busy:
		for m: String in ["move", "attack", "shove", "jump"]:
			_action_button(UiText.t(m), func() -> void: _set_mode(m), mode == m)
		for sid: String in selected.spells:
			var sp := RulesDB.get_entry("spell", sid)
			if not sp.is_empty():
				_action_button(UiText.name_of(sp["name"]), func() -> void: _set_mode("spell:" + sid), mode == "spell:" + sid)
		_action_button(UiText.t("dash"), func() -> void: Combat.dash(selected); _refresh())
		_action_button(UiText.t("disengage"), func() -> void: Combat.disengage(selected); _refresh())
		_action_button(UiText.t("hide"), func() -> void: Combat.hide(world, selected); _refresh())
		_action_button(UiText.t("stand"), func() -> void: Combat.stand_up(selected); _refresh())
		_action_button(UiText.t("switch"), func() -> void: Combat.switch_weapon_set(selected); _refresh())
		_action_button(UiText.t("end_turn"), _end_turn)
		var t: Dictionary = selected.turn
		status_label.text = "%s — %s" % [selected.label(), UiText.t("actions") % [int(t.get("action", 0)),
			int(t.get("bonus", 0)), int(t.get("reaction", 0)), int(t.get("movement", 0))]]
	else:
		status_label.text = UiText.t("enemy_turn") if busy else ""
	_update_log()
	map_view.refresh()


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
