extends Node
## 탐험(룰북 5단계 '실시간 규칙'): 실시간 6초 틱, 파티 이동(리더를 따라감, 묶기·풀기), 은신 켜고 끄기,
## 원뿔 판정(들어갈 때·틱마다), 함정 자동 지각·발동, 발견·적대 행동이면 전투 시작(전투 구역, 기습).
## world["explore"] = 이 노드. 실시간에서는 반응이 발동하지 않는다(적대 행동은 전투를 시작한다).

const Stealth := preload("res://scripts/rules/stealth.gd")
const Interact := preload("res://scripts/rules/interact.gd")

var world: Dictionary = {}
## 활성 파티(최대 4)
var party: Array = []
var leader: Node = null
## 묶인 파티원(리더를 따라가고 은신도 함께 켜진다)
var linked := {}
## 전투 시작 알림: [{"zone", "surprised", "reason"}]
var combat_requests: Array = []
var _moving := false


func setup(w: Dictionary, p: Array) -> Node:
	world = w
	world["explore"] = self
	party = p.duplicate()
	leader = party[0] if not party.is_empty() else null
	for c: Node in party:
		linked[c] = true
	if not EventBus.on_enter_tile.is_connected(_on_enter_tile):
		EventBus.on_enter_tile.connect(_on_enter_tile)
	return self


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and EventBus.on_enter_tile.is_connected(_on_enter_tile):
		EventBus.on_enter_tile.disconnect(_on_enter_tile)


func in_combat() -> bool:
	return world.get("turns") != null and world["turns"].in_combat


# ---------- 은신 ----------

## 은신 켜고 끔(탐험 중 비용 없음). 묶인 파티면 함께.
func set_sneak(c: Node, on: bool) -> void:
	var who: Array = party.filter(func(o: Node) -> bool: return linked.get(o, false)) if linked.get(c, false) else [c]
	for o: Node in who:
		o.sneaking = on
		if not on:
			o.remove_meta("stealth_total")
	for o: Node in who:
		_check_cones_for(o)


func link(c: Node, on: bool) -> void:
	linked[c] = on


# ---------- 이동 ----------

## 리더(또는 풀린 한 명)를 칸으로 옮긴다. 묶인 파티원은 뒤를 따른다. 결과: 옮긴 칸 수.
func move_to(c: Node, to: Vector2i) -> int:
	if in_combat():
		return 0
	var grid: Node = world["grid"]
	var allies: Array = grid.creatures().filter(func(o: Node) -> bool: return o != c and not o.is_hostile_to(c))
	var p: Dictionary = grid.find_path(c, to, -1, allies)
	if p.is_empty():
		return 0
	var steps := 0
	var trail: Array[Vector2i] = [grid.cell_of(c)]
	for nxt: Vector2i in p["path"]:
		if in_combat() or c.dead:
			break
		var other: Node = grid.creature_at(nxt)
		if other != null and other != c:
			break
		c.facing = Vector2i(signi(nxt.x - grid.cell_of(c).x), signi(nxt.y - grid.cell_of(c).y))
		grid.move_creature(c, nxt)
		trail.push_front(nxt)
		steps += 1
		if c == leader or linked.get(c, false):
			_follow(c, trail)
	return steps


## 묶인 파티원이 리더가 지나간 자리를 따라간다(줄 대형).
func _follow(lead: Node, trail: Array[Vector2i]) -> void:
	var grid: Node = world["grid"]
	var i := 1
	for o: Node in party:
		if o == lead or not linked.get(o, false) or o.dead or o.is_down():
			continue
		if i >= trail.size():
			break
		var want: Vector2i = trail[i]
		i += 1
		if grid.cell_of(o) == want or grid.creature_at(want) != null:
			continue
		var path: Dictionary = grid.find_path(o, want, 3, [lead])
		if not path.is_empty() and not path["path"].is_empty():
			var step: Vector2i = path["path"][0]
			if grid.creature_at(step) == null:
				o.facing = Vector2i(signi(step.x - grid.cell_of(o).x), signi(step.y - grid.cell_of(o).y))
				grid.move_creature(o, step)


func _on_enter_tile(c: Object, _cell: Vector2i) -> void:
	if world.is_empty() or not world["grid"].creatures().has(c) or in_combat():
		return
	if c in party:
		Interact.on_party_enter(world, c)
		_check_cones_for(c)
	else:
		# 적이 움직이면 그 적의 원뿔도 다시 본다
		for p: Node in party:
			_observe(c, p)


func _check_cones_for(target: Node) -> void:
	for o: Node in world["grid"].creatures():
		if o != target and o.is_hostile_to(target):
			_observe(o, target)


func _observe(observer: Node, target: Node) -> void:
	if in_combat():
		return
	var r := Stealth.observe(world["grid"], observer, target)
	if r == "alerted":
		_request_combat(observer, [], "발견")


# ---------- 시간 ----------

## 6초 틱: 지속시간·표면(TurnManager.tick), 원뿔 안에 머무는 은신 재판정, 의심·수색하는 적의 감지 행동.
func tick() -> void:
	if in_combat():
		return
	if world.get("turns") != null:
		world["turns"].tick()
	var grid: Node = world["grid"]
	for o: Node in grid.creatures():
		if o.dead or o.team == "party":
			continue
		for p: Node in party:
			if in_combat():
				return
			var aw: Dictionary = o.awareness.get(p, {})
			if aw.get("state", "") in ["suspicious", "searching"]:
				if Stealth.search(grid, o, p) == "alerted":
					_request_combat(o, [], "수색")
					continue
			if Stealth.in_cone(grid, o, p):
				_observe(o, p)


# ---------- 전투 시작 ----------

## 적대 행동(공격·적대 주문): 숨은 채 하면 알아채지 못한 적은 기습당한다(3단계 기습).
func hostile_action(attacker: Node, target: Node) -> void:
	if in_combat():
		return
	var hidden: bool = attacker.sneaking or attacker.has_condition("invisible")
	var surprised: Array = []
	if hidden:
		for o: Node in world["grid"].creatures():
			if o.is_hostile_to(attacker) and not o.dead and o.awareness.get(attacker, {}).get("state", "") != "alerted":
				surprised.append(o)
		Stealth.after_hidden_attack(world["grid"], attacker, target)
	_request_combat(target, surprised, "적대 행동")


func _request_combat(near: Node, surprised: Array, reason: String) -> void:
	var grid: Node = world["grid"]
	var zone := ""
	for c in grid.occupied_cells(near):
		if not grid.zones(c).is_empty():
			zone = grid.zones(c)[0]
			break
	combat_requests.append({"zone": zone, "surprised": surprised, "reason": reason})
	for p: Node in party:
		p.sneaking = false
	if world.get("turns") != null and zone != "":
		world["turns"].start_combat(zone, surprised)
