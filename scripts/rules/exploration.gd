extends Node
## 탐험(룰북 5단계 '실시간 규칙'): 실시간 6초 틱, 파티 이동(리더를 따라감, 묶기·풀기), 은신 켜고 끄기,
## 원뿔 판정(들어갈 때·틱마다), 함정 자동 지각·발동, 발견·적대 행동이면 전투 시작(전투 구역, 기습).
## world["explore"] = 이 노드. 실시간에서는 반응이 발동하지 않는다(적대 행동은 전투를 시작한다).

const Stealth := preload("res://scripts/rules/stealth.gd")
const Interact := preload("res://scripts/rules/interact.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Physics := preload("res://scripts/rules/physics.gd")

var world: Dictionary = {}
## 활성 파티(최대 4)
var party: Array = []
var leader: Node = null
## 묶인 파티원(리더를 따라가고 은신도 함께 켜진다)
var linked := {}
## 전투 시작 알림: [{"zone", "surprised", "reason"}]
var combat_requests: Array = []
var _moving := false
## 전투 중 구역 밖 파티원의 실시간 이동력(라운드마다 속도만큼, 직접 움직인 파티원은 자동 따라오기에서 뺀다)
var rt_budget := {}
var rt_manual := {}


func setup(w: Dictionary, p: Array) -> Node:
	world = w
	world["explore"] = self
	EventBus.realtime = not in_combat()
	party = p.duplicate()
	leader = party[0] if not party.is_empty() else null
	for c: Node in party:
		linked[c] = true
	if not EventBus.on_enter_tile.is_connected(_on_enter_tile):
		EventBus.on_enter_tile.connect(_on_enter_tile)
	if not EventBus.on_round_end.is_connected(_on_round_end):
		EventBus.on_round_end.connect(_on_round_end)
	return self


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		EventBus.realtime = false
		if EventBus.on_enter_tile.is_connected(_on_enter_tile):
			EventBus.on_enter_tile.disconnect(_on_enter_tile)
		if EventBus.on_round_end.is_connected(_on_round_end):
			EventBus.on_round_end.disconnect(_on_round_end)


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
		# 걸어서 못 가면(높은 바위 위 등) 점프로 내려가 이어 간다(탐험 중 점프는 비용 없음, 2단계 이상 떨어지면 낙하 피해)
		var land := _jump_spot(c, to, allies)
		if land.x < 0 or not jump(c, land):
			return 0
		return 1 + move_to(c, to)
	var steps := 0
	var trail: Array[Vector2i] = [grid.cell_of(c)]
	for nxt: Vector2i in p["path"]:
		if in_combat() or c.dead or world.has("pending_dialogue"):
			break
		var other: Node = grid.creature_at(nxt)
		if other != null and other != c:
			# 묶인 파티원과는 자리를 바꿔 지나간다(좁은 통로)
			if other in party and grid.size_of(other) == 1 and grid.size_of(c) == 1:
				grid.move_creature(other, grid.cell_of(c))
			else:
				break
		c.facing = Vector2i(signi(nxt.x - grid.cell_of(c).x), signi(nxt.y - grid.cell_of(c).y))
		grid.move_creature(c, nxt)
		trail.push_front(nxt)
		steps += 1
		if c == leader or linked.get(c, false):
			_follow(c, trail)
	return steps


## 탐험 중 점프(실시간이라 행동·이동력 비용 없음). 거리·착지·높이 제한은 전투 점프와 같다(3단계).
func jump(c: Node, to: Vector2i) -> bool:
	var grid: Node = world["grid"]
	var from: Vector2i = grid.cell_of(c)
	if grid.distance(from, to) > Combat.jump_distance(c) or grid.blocks_movement(to) or grid.creature_at(to) != null:
		return false
	if grid.height(to) - grid.height(from) > 1:
		return false
	grid.move_creature(c, to)
	var drop: int = grid.height(from) - grid.height(to)
	if drop >= 2:
		Physics.fall(c, drop)
	return true


## 목적지로 이어지는 점프 착지 칸(낙하가 가장 작은 곳 → 목적지에 가까운 곳).
func _jump_spot(c: Node, to: Vector2i, allies: Array) -> Vector2i:
	var grid: Node = world["grid"]
	var from: Vector2i = grid.cell_of(c)
	var reach: int = Combat.jump_distance(c)
	var best := Vector2i(-1, -1)
	var best_key := Vector2i(1 << 20, 1 << 20)
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var n := from + Vector2i(dx, dy)
			if n == from or not grid.in_bounds(n) or grid.blocks_movement(n) or grid.creature_at(n) != null:
				continue
			if grid.height(n) - grid.height(from) > 1 or not grid.has_line_of_sight(from, n, true):
				continue
			var key := Vector2i(maxi(0, grid.height(from) - grid.height(n)), grid.distance(n, to))
			if key.x > best_key.x or (key.x == best_key.x and key.y >= best_key.y):
				continue
			# 그 칸에서 목적지까지 걸어갈 수 있어야 한다
			var saved: Vector2i = grid.cell_of(c)
			grid._placement[c]["cell"] = n
			var ok: bool = n == to or not grid.find_path(c, to, -1, allies).is_empty()
			grid._placement[c]["cell"] = saved
			if ok:
				best = n
				best_key = key
	return best


## 묶인 파티원이 리더가 지나간 자리를 따라간다(줄 대형). 리더가 한 칸 갈 때마다 각자 한 칸씩,
## 멀리 떨어져 있으면 지름길로 다가온다(실시간이라 거리 제한 없음).
func _follow(lead: Node, trail: Array[Vector2i]) -> void:
	var grid: Node = world["grid"]
	var i := 1
	for o: Node in party:
		if o == lead or not linked.get(o, false) or o.dead or o.is_down() or not grid.creatures().has(o):
			continue
		var want: Vector2i = trail[mini(i, trail.size() - 1)]
		i += 1
		if grid.distance(grid.cell_of(o), grid.cell_of(lead)) <= i - 1:
			continue
		var path: Dictionary = grid.find_path(o, want, -1, party)
		if path.is_empty() or path["path"].is_empty():
			continue
		for k in (1 if grid.distance(grid.cell_of(o), want) <= 3 else 2):
			if k >= path["path"].size():
				break
			var step: Vector2i = path["path"][k]
			if grid.creature_at(step) != null:
				break
			o.facing = Vector2i(signi(step.x - grid.cell_of(o).x), signi(step.y - grid.cell_of(o).y))
			grid.move_creature(o, step)
			if in_combat() or world.has("pending_dialogue"):
				return


## 모이기: 묶인 파티원이 리더 뒤 가까운 칸으로 걸어온다(실시간 이동, 은신·원뿔 판정은 그대로 돈다).
func regroup() -> void:
	if in_combat() or leader == null:
		return
	var grid: Node = world["grid"]
	var near: Array[Vector2i] = []
	var lc: Vector2i = grid.cell_of(leader)
	for r in range(1, 4):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var n := lc + Vector2i(dx, dy)
				if maxi(absi(dx), absi(dy)) == r and grid.in_bounds(n) and not grid.blocks_movement(n) and not n in near:
					near.append(n)
	for o: Node in party:
		if o == leader or not linked.get(o, false) or o.dead or o.is_down() or not grid.creatures().has(o):
			continue
		if grid.distance(grid.cell_of(o), lc) <= 2:
			continue
		for n: Vector2i in near:
			if grid.creature_at(n) != null:
				continue
			var p: Dictionary = grid.find_path(o, n, -1, party)
			if p.is_empty():
				continue
			for step: Vector2i in p["path"]:
				if grid.creature_at(step) != null or in_combat() or world.has("pending_dialogue"):
					break
				o.facing = Vector2i(signi(step.x - grid.cell_of(o).x), signi(step.y - grid.cell_of(o).y))
				grid.move_creature(o, step)
			break
		if in_combat() or world.has("pending_dialogue"):
			return


func _on_enter_tile(c: Object, cell: Vector2i) -> void:
	if world.is_empty() or not world["grid"].creatures().has(c):
		return
	# 함정 발동: 설치한 편(owner_team)이 있으면 그 반대편이 밟을 때(Glyph of Warding), 맵 함정은 전투 중에도 파티가 밟으면
	for t: Dictionary in world.get("traps", []):
		if t["state"] != "armed" or Vector2i(int(t["cell"][0]), int(t["cell"][1])) != cell:
			continue
		var owner: String = t.get("owner_team", "")
		if (owner != "" and c.team != owner) or (owner == "" and c in party and in_combat()):
			Interact.trigger(world, t, c)
	if in_combat():
		return
	if c == leader:
		for tr: Dictionary in world.get("transitions", []):
			if Vector2i(int(tr["cell"][0]), int(tr["cell"][1])) == cell:
				world["pending_travel"] = {"to": tr["to"], "spawn": tr["spawn"]}  # 화면이 맵을 바꾼다
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


## 원뿔 판정. 숨은 대상은 원뿔에 '들어올 때' 한 번만 굴리고, 머무는 동안은 틱마다(reroll) 다시 굴린다(5단계 은신 판정).
func _observe(observer: Node, target: Node, reroll: bool = false) -> void:
	if in_combat():
		return
	var inside: Dictionary = observer.get_meta("cone_inside", {})
	if not Stealth.in_cone(world["grid"], observer, target):
		inside.erase(target)
		observer.set_meta("cone_inside", inside)
		return
	var was_inside: bool = inside.has(target)
	inside[target] = true
	observer.set_meta("cone_inside", inside)
	if was_inside and target.sneaking and not reroll:
		return
	var r := Stealth.observe(world["grid"], observer, target)
	if r == "alerted":
		if world.has("pending_dialogue"):
			return  # 대화가 먼저 열린다
		# 같은 세력에 대화할 상대가 있으면 전투 대신 대화를 먼저 연다(한 번만)
		var talker := _talker_of(observer)
		if talker != null:
			talker.set_meta("dialogue_done", true)
			world["pending_dialogue"] = {"id": talker.get_meta("dialogue"), "npc": talker, "reason": "detected", "speaker": target}
			return
		_request_combat(observer, [], "발견", [target])


func _talker_of(o: Node) -> Node:
	for c: Node in world["grid"].creatures():
		if c.dead or not c.has_meta("dialogue") or c.get_meta("dialogue_done", false):
			continue
		if c == o or (o.faction != "" and c.faction == o.faction):
			return c
	return null


## 전투 중 구역 밖 파티원: 실시간으로 계속 움직여(라운드마다 속도만큼) 전투 중인 파티원 쪽으로 간다.
## 구역에 들어오면 TurnManager가 다음 라운드에 합류시킨다(3단계 전투 참가).
## 전투 중 구역 밖 파티원을 직접 옮긴다(실시간, 라운드마다 속도만큼). 결과: 옮긴 칸 수.
func realtime_move(c: Node, to: Vector2i) -> int:
	if not in_combat() or c in world["turns"].order or c in world["turns"]._pending:
		return 0
	var grid: Node = world["grid"]
	var p: Dictionary = grid.find_path(c, to, -1, party)
	if p.is_empty():
		return 0
	rt_manual[c] = true
	var budget: int = int(rt_budget.get(c, c.speed()))
	var steps := 0
	for nxt: Vector2i in p["path"]:
		if steps >= budget or grid.creature_at(nxt) != null:
			break
		c.facing = Vector2i(signi(nxt.x - grid.cell_of(c).x), signi(nxt.y - grid.cell_of(c).y))
		grid.move_creature(c, nxt)
		steps += 1
		if c in world["turns"]._pending:
			break  # 구역에 들어왔다 — 다음 라운드에 합류
	rt_budget[c] = budget - steps
	return steps


func _on_round_end() -> void:
	if not in_combat() or world.is_empty():
		return
	var manual := rt_manual.duplicate()
	rt_budget.clear()
	rt_manual.clear()
	var tm: Node = world["turns"]
	var grid: Node = world["grid"]
	var fighting: Array = party.filter(func(o: Node) -> bool: return o in tm.order and not o.dead)
	if fighting.is_empty():
		return
	var anchor: Node = fighting[0]
	for o: Node in party:
		if o in tm.order or o.dead or o.is_down() or not linked.get(o, false) or not grid.creatures().has(o) or manual.has(o):
			continue
		var best := {}
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var n: Vector2i = grid.cell_of(anchor) + Vector2i(dx, dy) * 2
				if not grid.in_bounds(n) or grid.blocks_movement(n) or grid.creature_at(n) != null:
					continue
				var p: Dictionary = grid.find_path(o, n, -1, party)
				if not p.is_empty() and (best.is_empty() or int(p["cost"]) < int(best["cost"])):
					best = p
		if best.is_empty():
			continue
		var steps := 0
		for nxt: Vector2i in best["path"]:
			if steps >= o.speed() or grid.creature_at(nxt) != null or not in_combat():
				break
			o.facing = Vector2i(signi(nxt.x - grid.cell_of(o).x), signi(nxt.y - grid.cell_of(o).y))
			grid.move_creature(o, nxt)
			steps += 1
			if o in tm._pending:
				break
		# 구역 밖에서 싸움이 벌어지면(쫓아 나온 적) 3칸 안까지 다가온 파티원도 합류한다
		if not o in tm._pending:
			for q: Node in tm.order:
				if q.team == "enemy" and not q.dead and grid.distance_between(o, q) <= 3:
					tm._pending.append(o)
					break


# ---------- 시간 ----------

## 6초 틱: 지속시간·표면(TurnManager.tick), 원뿔 안에 머무는 은신 재판정, 의심·수색하는 적의 감지 행동.
func tick() -> void:
	if in_combat() or world.has("pending_dialogue"):
		return
	if world.get("turns") != null:
		world["turns"].tick()
	check_zone_rewards()
	_decay_awareness()
	var grid: Node = world["grid"]
	for o: Node in grid.creatures():
		if o.dead or o.team == "party":
			continue
		for p: Node in party:
			if in_combat():
				return
			var aw: Dictionary = o.awareness.get(p, {})
			if aw.get("state", "") == "searching" and aw.has("last"):
				_walk_toward(o, aw["last"], 3)  # 수색: 마지막 위치 쪽으로(5단계 '수색은 마지막 위치 주변')
			if aw.get("state", "") in ["suspicious", "searching"]:
				if Stealth.search(grid, o, p) == "alerted":
					_request_combat(o, [], "수색", [p])
					continue
			if Stealth.in_cone(grid, o, p):
				_observe(o, p, true)


## 실시간 적 이동: 칸 쪽으로 최대 n칸(틱 6초 — 걸음 반)
func _walk_toward(o: Node, cell: Vector2i, n: int) -> void:
	var grid: Node = world["grid"]
	if o.speed() <= 0 or grid.distance(grid.cell_of(o), cell) <= 1:
		return
	var p: Dictionary = grid.find_path(o, cell, -1, [])
	if p.is_empty():
		return
	var steps := 0
	for nxt: Vector2i in p["path"]:
		if steps >= n or grid.creature_at(nxt) != null or in_combat():
			break
		o.facing = Vector2i(signi(nxt.x - grid.cell_of(o).x), signi(nxt.y - grid.cell_of(o).y))
		grid.move_creature(o, nxt)
		steps += 1


## 알아챔이 시간이 지나면 풀린다: 의심 10턴(1분), 수색 100턴(10분). 발견은 전투로 이어지므로 그대로(changes.md).
const SUSPICIOUS_TURNS := 10
const SEARCHING_TURNS := 100


func _decay_awareness() -> void:
	for o: Node in world["grid"].creatures():
		if o.dead or o.team == "party":
			continue
		for k in o.awareness.keys():
			var a: Dictionary = o.awareness[k]
			var st: String = a.get("state", "")
			if st != "suspicious" and st != "searching":
				continue
			a["turns"] = int(a.get("turns", 0)) + 1
			if a["turns"] >= (SUSPICIOUS_TURNS if st == "suspicious" else SEARCHING_TURNS):
				o.awareness.erase(k)
				Dice.log_text("%s: 경계를 푼다" % o.label())


# ---------- 구역 보상 ----------

## 구역에 적대 생물이 하나도 남지 않으면(쓰러뜨렸거나 평화 해결) 구역 보상 경험치를 한 번 준다.
func check_zone_rewards() -> void:
	var rewards: Dictionary = world.get("zone_rewards", {})
	if rewards.is_empty() or in_combat():
		return
	if not world.has("zones_cleared"):
		world["zones_cleared"] = {}
	var grid: Node = world["grid"]
	for z: String in rewards:
		if world["zones_cleared"].has(z):
			continue
		var hostile := false
		var any := false
		for o: Node in grid.creatures():
			var inz := false
			if o.has_meta("home_zone"):
				inz = o.get_meta("home_zone") == z
			else:
				for c in grid.occupied_cells(o):
					inz = inz or z in grid.zones(c)
			if not inz or o.team == "party":
				continue
			any = true
			if o.team == "enemy" and not o.dead:
				hostile = true
		if any and not hostile:
			world["zones_cleared"][z] = true
			var P: Variant = load("res://scripts/rules/progression.gd")
			P.award_defeated(world, grid.creatures())
			if int(rewards[z]) > 0:
				P.award(world, int(rewards[z]), "구역 정리: " + z)


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
	_request_combat(target, surprised, "적대 행동", [attacker])


func _request_combat(near: Node, surprised: Array, reason: String, extra: Array = []) -> void:
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
		world["turns"].start_combat(zone, surprised, extra)
