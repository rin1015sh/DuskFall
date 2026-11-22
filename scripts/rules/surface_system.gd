extends Node
## 표면 시스템. 룰북 4단계 '원인 × 대상 반응표', '표면 규칙', 9단계 충돌 C·D.
##
## 사건(event)을 줄에 넣어 차례로 처리한다. 사건 하나가 일으킨 반응은 깊이 +1이다.
## 깊이 3을 넘거나 한 번에 바뀐 칸이 64칸에 이르면 남은 사건은 다음 턴 틱(end_round)으로 미룬다.
## 사건: {"kind": "damage"|"surface"|"cloud"|"water", "cell", "depth", ...}

const Resolver := preload("res://scripts/rules/resolver.gd")
const Area := preload("res://scripts/rules/area.gd")

const MAX_DEPTH := 3
const MAX_CELLS := 64
## 주문이 만든 표면이 아니면 표면 내성 DC는 12(4단계 표면 규칙).
const DEFAULT_DC := 12

var grid: Node
## 미룬 사건(다음 end_round에 깊이 1로 다시 처리).
var deferred: Array[Dictionary] = []
## 반응 기록(로그·미리보기 확인용): {"cell", "reaction", "depth"}
var history: Array[Dictionary] = []

var _changed := 0
var _reactions: Dictionary = {}  # "cause|target" → reaction
## 생물 → {"turn": int, "ids": {표면 ID: true}} — 같은 턴에 같은 표면 효과는 한 번만.
var _hits: Dictionary = {}


func setup(g: Node) -> Node:
	grid = g
	_reactions.clear()
	for id: String in RulesDB.ids("reaction"):
		var r := RulesDB.get_entry("reaction", id)
		_reactions["%s|%s" % [r["cause"], r["target"]]] = r
	if not EventBus.on_enter_tile.is_connected(_on_enter_tile):
		EventBus.on_enter_tile.connect(_on_enter_tile)
	return self


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and EventBus.on_enter_tile.is_connected(_on_enter_tile):
		EventBus.on_enter_tile.disconnect(_on_enter_tile)


# ======================================================================
# 바깥에서 부르는 원인
# ======================================================================

## 칸들이 피해 유형을 받는다(범위 주문 등). 칸 반응과 칸의 물체 피해. 단일 대상 효과는 부르지 않는다(충돌 A).
func tile_damage(cells: Array, damage_type: String, amount: int = 0, source: Variant = null) -> void:
	var events: Array[Dictionary] = []
	for c: Vector2i in cells:
		events.append({"kind": "damage", "cell": c, "damage_type": damage_type, "amount": amount,
			"source": source, "depth": 1})
	_run(events)


## 표면을 놓는다. opts: {"turns": int(-1 영구, 없으면 기본), "source", "dc"}
func place_surface(cells: Array, id: String, opts: Dictionary = {}) -> void:
	var events: Array[Dictionary] = []
	for c: Vector2i in cells:
		events.append({"kind": "surface", "cell": c, "id": id, "opts": opts, "depth": 1})
	_run(events)


func place_cloud(cells: Array, id: String, opts: Dictionary = {}) -> void:
	var events: Array[Dictionary] = []
	for c: Vector2i in cells:
		events.append({"kind": "cloud", "cell": c, "id": id, "opts": opts, "depth": 1})
	_run(events)


## 물·비가 닿는다(반응표의 '물·비' 열).
func apply_water(cells: Array) -> void:
	var events: Array[Dictionary] = []
	for c: Vector2i in cells:
		events.append({"kind": "water", "cell": c, "depth": 1})
	_run(events)


# ======================================================================
# 사건 처리
# ======================================================================

func _run(events: Array) -> void:
	_changed = 0
	var queue := events.duplicate()
	while not queue.is_empty():
		var e: Dictionary = queue.pop_front()
		if e["depth"] > MAX_DEPTH or _changed >= MAX_CELLS:
			deferred.append(e)
			continue
		match e["kind"]:
			"damage":
				_handle_damage(e, queue)
			"surface":
				_handle_surface(e, queue)
			"cloud":
				_set_cloud(e["cell"], e["id"], e.get("opts", {}))
			"water":
				_handle_reaction_or_nothing(e, "water", queue)


func _handle_damage(e: Dictionary, queue: Array) -> void:
	var c: Vector2i = e["cell"]
	if not grid.in_bounds(c):
		return
	EventBus.on_tile_damage_type.emit(c, e["damage_type"])
	if e["amount"] > 0 and not grid.object_at(c).is_empty():
		_damage_object(c, e["damage_type"], e["amount"], e["depth"], queue)
	if not _handle_reaction_or_nothing(e, "damage:" + e["damage_type"], queue):
		# 표면이 없으면 재질 반응(가연성 + 화염 → 화염 표면)
		if grid.surface_id(c) == "" and e["damage_type"] == "fire" and _material_flammable(c):
			_apply_result(c, _reactions.get("damage:fire|material:flammable", {}), e["depth"], queue)


## 칸의 표면과 원인으로 반응표를 찾는다. 반응했으면 true.
func _handle_reaction_or_nothing(e: Dictionary, cause: String, queue: Array) -> bool:
	var c: Vector2i = e["cell"]
	var sid: String = grid.surface_id(c)
	if sid == "":
		return false
	var r: Dictionary = _reactions.get("%s|surface:%s" % [cause, sid], {})
	if r.is_empty():
		return false
	_apply_result(c, r, e["depth"], queue)
	return true


func _handle_surface(e: Dictionary, queue: Array) -> void:
	var c: Vector2i = e["cell"]
	if not grid.in_bounds(c) or grid.has_flag(c, "wall"):
		return
	var old: String = grid.surface_id(c)
	if old != "":
		var r: Dictionary = _reactions.get("surface:%s|surface:%s" % [e["id"], old], {})
		if not r.is_empty():
			_apply_result(c, r, e["depth"], queue)
			return
	_set_surface(c, e["id"], e.get("opts", {}), e["depth"], queue)


func _apply_result(c: Vector2i, r: Dictionary, depth: int, queue: Array) -> void:
	if r.is_empty():
		return
	var res: Dictionary = r["result"]
	history.append({"cell": c, "reaction": r["id"], "depth": depth})
	if res.get("block", false) or res.get("keep", false):
		return
	if res.get("remove_surface", false):
		_clear_surface(c)
	if res.has("replace_surface"):
		_set_surface(c, res["replace_surface"], {}, depth, queue)
	if res.has("create_surface"):
		_set_surface(c, res["create_surface"], {}, depth, queue)
	if res.has("create_cloud"):
		_set_cloud(c, res["create_cloud"], {})
	for eff: Dictionary in res.get("creatures", []):
		for cr: Node in Area.creatures_in(grid, [c]):
			_apply_effect(cr, eff)


func _set_surface(c: Vector2i, id: String, opts: Dictionary, depth: int, queue: Array) -> void:
	var def := RulesDB.get_entry("surface", id)
	if def.is_empty():
		push_error("모르는 표면 '%s'" % id)
		return
	var turns := int(opts.get("turns", def["duration_turns"]))
	grid.set_surface(c, {"id": id, "turns_left": turns, "source": opts.get("source"), "dc": int(opts.get("dc", DEFAULT_DC))})
	_changed += 1
	# 불이 붙은 가연성 재질은 탄 땅이 된다(changes.md 2026-11-22). 다시 불붙지 않는다.
	if id == "fire" and _material_flammable(c):
		grid.set_material(c, RulesDB.get_entry("material", grid.material(c)).get("burns_to", "burnt_ground"))
	# 표면이 칸의 물체에 피해를 준다(화염 표면 → 물체 1d4 화염). 반응 한 단계로 센다(충돌 D).
	if def.has("object_damage") and not grid.object_at(c).is_empty():
		var amount: int = Dice.roll(def["object_damage"]["dice"], "%s → 물체" % id)["total"]
		queue.append({"kind": "damage", "cell": c, "damage_type": def["object_damage"]["damage_type"],
			"amount": amount, "depth": depth + 1, "object_only": true})


func _clear_surface(c: Vector2i) -> void:
	grid.set_surface(c, null)
	_changed += 1


func _set_cloud(c: Vector2i, id: String, opts: Dictionary) -> void:
	if not grid.in_bounds(c) or grid.has_flag(c, "wall"):
		return
	var def := RulesDB.get_entry("surface", id)
	grid.set_cloud(c, {"id": id, "turns_left": int(opts.get("turns", def.get("duration_turns", -1))),
		"source": opts.get("source"), "dc": int(opts.get("dc", DEFAULT_DC))})
	_changed += 1


func _material_flammable(c: Vector2i) -> bool:
	return RulesDB.get_entry("material", grid.material(c)).get("flammable", false)


# ---------- 물체 ----------

## 물체 피해. 물체는 독·정신 피해 면역(SRD). 깨짐 재질은 피해를 받으면 부서진다.
## 부서지면 내용물이 표면이 된다(그 표면은 다음 깊이).
func _damage_object(c: Vector2i, damage_type: String, amount: int, depth: int, queue: Array) -> void:
	var obj: Dictionary = grid.objects[c]
	if damage_type in ["poison", "psychic"]:
		return
	var fragile: bool = RulesDB.get_entry("material", obj.get("material", "")).get("fragile", false)
	obj["hp"] = int(obj.get("hp", 1)) - amount
	if fragile or obj["hp"] <= 0:
		break_object(c, depth, queue)


## 물체를 부순다. 내용물 {"surface", "radius"}가 원형 마스크로 퍼진다.
func break_object(c: Vector2i, depth: int = 1, queue: Variant = null) -> void:
	var obj: Dictionary = grid.object_at(c)
	if obj.is_empty():
		return
	grid.remove_object(c)
	_changed += 1
	history.append({"cell": c, "reaction": "break:" + str(obj.get("id", "")), "depth": depth})
	var contents: Dictionary = obj.get("contents", {})
	if contents.is_empty():
		return
	var events: Array[Dictionary] = []
	for cell in Area.circle(grid, c, int(contents.get("radius", 0))):
		events.append({"kind": "surface", "cell": cell, "id": contents["surface"], "opts": {}, "depth": depth + 1})
	if queue == null:
		_run(events)
	else:
		queue.append_array(events)


# ======================================================================
# 시간: 라운드 끝(탐험 중에는 6초 틱)
# ======================================================================

## 번짐 → 지속시간 감소·만료 → 미룬 사건 처리.
func end_round() -> void:
	var spread := preview_spread()
	var events: Array[Dictionary] = []
	for c in spread:
		events.append({"kind": "damage", "cell": c, "damage_type": "fire", "amount": 0, "depth": 1})
	_run(events)
	for c in grid.all_cells():
		_tick_layer(c, true)
		_tick_layer(c, false)
	if not deferred.is_empty():
		var again := deferred.duplicate()
		deferred.clear()
		for e in again:
			e["depth"] = 1
		_run(again)


func _tick_layer(c: Vector2i, ground: bool) -> void:
	var inst: Variant = grid.surface(c) if ground else grid.cloud(c)
	if inst == null or inst["turns_left"] < 0:
		return
	inst["turns_left"] -= 1
	if inst["turns_left"] > 0:
		return
	var def := RulesDB.get_entry("surface", inst["id"])
	if ground:
		grid.set_surface(c, null)
		if def.has("expires_to"):
			grid.set_surface(c, {"id": def["expires_to"], "turns_left": int(RulesDB.get_entry("surface", def["expires_to"])["duration_turns"]),
				"source": null, "dc": DEFAULT_DC})
	else:
		grid.set_cloud(c, null)


## 긴 시간이 흐름(휴식): 시간 제한 표면·구름이 turns 안에 끝나면 걷어낸다(-1 = 전부). 번짐은 따지지 않는다.
## 끝나며 바뀌는 표면(expires_to)은 바뀐 뒤 남은 시간도 따져 한 번 더 걷는다.
func expire_timed(turns: int) -> void:
	for c in grid.all_cells():
		for ground: bool in [true, false]:
			for _i in 2:
				var inst: Variant = grid.surface(c) if ground else grid.cloud(c)
				if inst == null or inst["turns_left"] < 0:
					break
				if turns >= 0 and inst["turns_left"] > turns:
					inst["turns_left"] -= turns
					break
				inst["turns_left"] = 1
				_tick_layer(c, ground)


## 다음 라운드 끝에 불이 번질 칸: 화염 표면의 직교 인접 가연성 칸(재질 또는 기름·거미줄 같은 가연성 표면).
func preview_spread() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in grid.all_cells():
		if grid.surface_id(c) != "fire":
			continue
		for d in grid.DIRS_4:
			var n: Vector2i = c + d
			if not grid.in_bounds(n) or n in out or grid.surface_id(n) == "fire" or grid.has_flag(n, "wall"):
				continue
			if _cell_flammable(n):
				out.append(n)
	return out


func _cell_flammable(c: Vector2i) -> bool:
	var sid: String = grid.surface_id(c)
	if sid != "":
		return RulesDB.get_entry("surface", sid).get("flammable", false) or sid == "web"
	return _material_flammable(c)


## 번짐 예고에서 다칠 생물(아군 경고용, 충돌 C).
func spread_warnings(watch: Array) -> Array:
	var cells := preview_spread()
	var out: Array = []
	for cr: Node in watch:
		for c in grid.occupied_cells(cr):
			if c in cells:
				out.append(cr)
				break
	return out


## 범위 효과 미리보기: 칸마다 일어날 반응(깊이 1만, 바꾸지 않음).
func preview_tile_damage(cells: Array, damage_type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c: Vector2i in cells:
		var sid: String = grid.surface_id(c)
		var r: Dictionary = {}
		if sid != "":
			r = _reactions.get("damage:%s|surface:%s" % [damage_type, sid], {})
		elif damage_type == "fire" and _material_flammable(c):
			r = _reactions.get("damage:fire|material:flammable", {})
		if not r.is_empty():
			out.append({"cell": c, "reaction": r["id"], "result": r["result"]})
	return out


# ======================================================================
# 생물에게 주는 표면 효과
# ======================================================================

## 칸에 들어갈 때(강제 이동 포함). grid.move_creature가 on_enter_tile을 보내면 자동으로 불린다.
func _on_enter_tile(creature: Object, cell: Vector2i) -> void:
	if grid == null or not grid.creatures().has(creature):
		return
	creature_entered(creature, cell)


func creature_entered(creature: Node, _cell: Vector2i) -> void:
	for c in grid.occupied_cells(creature):
		_apply_layers(creature, c, "enter")


## 턴 시작: 새 턴이므로 '한 번만' 기록을 비우고 서 있는 칸의 효과를 받는다.
func creature_turn_start(creature: Node) -> void:
	var h: Dictionary = _hits.get(creature, {"turn": 0, "ids": {}})
	_hits[creature] = {"turn": h["turn"] + 1, "ids": {}}
	for c in grid.occupied_cells(creature):
		_apply_layers(creature, c, "turn_start")


func _apply_layers(creature: Node, c: Vector2i, trigger: String) -> void:
	for inst: Variant in [grid.surface(c), grid.cloud(c)]:
		if inst == null or creature.dead:
			continue
		var def := RulesDB.get_entry("surface", inst["id"])
		if trigger == "enter":
			for eff: Dictionary in def.get("on_move", []):
				_apply_effect(creature, eff)  # 가시: 칸마다
		if not _hits.has(creature):
			_hits[creature] = {"turn": 0, "ids": {}}
		if _hits[creature]["ids"].has(inst["id"]):
			continue
		var effects: Array = def.get("on_enter_or_turn_start", []).duplicate()
		if trigger == "turn_start":
			effects.append_array(def.get("on_turn_start", []))
		var save: Dictionary = def.get("save", {})
		var used := not effects.is_empty()
		for eff: Dictionary in effects:
			_apply_effect(creature, eff)
		if not save.is_empty() and (trigger == "enter" or not save.get("on_enter_only", false)):
			used = true
			var r := Resolver.saving_throw(creature, save["ability"], int(inst.get("dc", DEFAULT_DC)))
			if not r["success"]:
				for eff: Dictionary in save["on_fail"]:
					_apply_effect(creature, eff)
		if used:
			_hits[creature]["ids"][inst["id"]] = true


func _apply_effect(creature: Node, eff: Dictionary) -> void:
	match eff["type"]:
		"apply_condition":
			creature.apply_condition(eff["id"])
		"remove_condition":
			creature.remove_condition(eff["id"])
		"damage":
			var r := Dice.roll(eff["dice"], "표면 피해")
			Resolver.apply_damage(creature, [{"amount": r["total"], "damage_type": eff["damage_type"]}])
