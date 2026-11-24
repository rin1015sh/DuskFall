extends Node
## 격자 세계(칸 데이터만). 룰북 8단계 'Godot 구조', 3단계 이동, 4단계 태그·높은 곳·빛.
## 화면 좌표를 모른다. 칸 좌표는 Vector2i(x, y)다.
##
## 칸 레이어: 높이(정수 단계), 재질, 표면 1개, 구름 1개, 기본 빛, 플래그, 구역.
## 플래그: "wall"(통행·시야 차단), "impassable"(통행만 차단), "blocks_sight"(시야만 차단),
##        "difficult"(어려운 지형), "climb"(오르기 지점), 그 밖의 태그(예: "no_camp")
## 물체 층: 칸마다 물체 하나 {"id", "material", "hp", "ac", "weight_kg", "contents": {"surface", "radius"}}

enum Light { DARK, DIM, BRIGHT }

const DIRS_8: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
const DIRS_4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
## 암시야 거리 60피트 = 12칸(SRD 종족·몬스터 기본값).
const DARKVISION_TILES := 12

var size := Vector2i.ZERO
var _height := PackedInt32Array()
var _material: Array[String] = []
var _flags: Array[Dictionary] = []
var _surface: Array = []  # null 또는 {"id", "turns_left", "source", "dc"}
var _cloud: Array = []
var _light := PackedInt32Array()
var _zones: Array[PackedStringArray] = []
## 칸 → 물체
var objects: Dictionary = {}
## 광원: {"id", "cell", "bright", "dim"} (반경은 칸, 원형 마스크)
var light_sources: Array[Dictionary] = []
## 생물 → {"cell": 기준 칸(왼쪽 위), "size": 1 또는 2}
var _placement: Dictionary = {}


func setup(w: int, h: int, material: String = "stone", light: int = Light.BRIGHT) -> Node:
	size = Vector2i(w, h)
	var n := w * h
	_height.resize(n)
	_height.fill(0)
	_light.resize(n)
	_light.fill(light)
	_material.clear()
	_flags.clear()
	_surface.clear()
	_cloud.clear()
	_zones.clear()
	for i in n:
		_material.append(material)
		_flags.append({})
		_surface.append(null)
		_cloud.append(null)
		_zones.append(PackedStringArray())
	objects.clear()
	light_sources.clear()
	_placement.clear()
	return self


## 글자 지도로 빠르게 만든다(테스트용). '#' 벽, '.' 바닥, 숫자 = 높이.
func setup_from_rows(rows: Array, material: String = "stone") -> Node:
	setup(rows[0].length(), rows.size(), material)
	for y in rows.size():
		for x in rows[y].length():
			var ch: String = rows[y][x]
			var c := Vector2i(x, y)
			if ch == "#":
				set_flag(c, "wall")
			elif ch.is_valid_int():
				set_height(c, ch.to_int())
	return self


# ---------- 칸 레이어 ----------

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y


func _i(c: Vector2i) -> int:
	return c.y * size.x + c.x


func height(c: Vector2i) -> int:
	return _height[_i(c)] if in_bounds(c) else 0


func set_height(c: Vector2i, h: int) -> void:
	_height[_i(c)] = h


func material(c: Vector2i) -> String:
	return _material[_i(c)] if in_bounds(c) else ""


func set_material(c: Vector2i, m: String) -> void:
	_material[_i(c)] = m


func has_flag(c: Vector2i, f: String) -> bool:
	return in_bounds(c) and _flags[_i(c)].has(f)


func set_flag(c: Vector2i, f: String, on: bool = true) -> void:
	if on:
		_flags[_i(c)][f] = true
	else:
		_flags[_i(c)].erase(f)


func zones(c: Vector2i) -> PackedStringArray:
	return _zones[_i(c)] if in_bounds(c) else PackedStringArray()


func add_zone(c: Vector2i, zone: String) -> void:
	if not _zones[_i(c)].has(zone):
		_zones[_i(c)].append(zone)


## 표면 인스턴스(없으면 null).
func surface(c: Vector2i) -> Variant:
	return _surface[_i(c)] if in_bounds(c) else null


func surface_id(c: Vector2i) -> String:
	var s: Variant = surface(c)
	return s["id"] if s != null else ""


func set_surface(c: Vector2i, inst: Variant) -> void:
	_surface[_i(c)] = inst


func cloud(c: Vector2i) -> Variant:
	return _cloud[_i(c)] if in_bounds(c) else null


func cloud_id(c: Vector2i) -> String:
	var s: Variant = cloud(c)
	return s["id"] if s != null else ""


func set_cloud(c: Vector2i, inst: Variant) -> void:
	_cloud[_i(c)] = inst


func base_light(c: Vector2i) -> int:
	return _light[_i(c)] if in_bounds(c) else Light.DARK


func set_base_light(c: Vector2i, level: int) -> void:
	_light[_i(c)] = level


func all_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			out.append(Vector2i(x, y))
	return out


# ---------- 물체 ----------

func place_object(c: Vector2i, obj: Dictionary) -> void:
	objects[c] = obj.duplicate(true)


func object_at(c: Vector2i) -> Dictionary:
	return objects.get(c, {})


func remove_object(c: Vector2i) -> void:
	objects.erase(c)


# ---------- 생물 배치 ----------

func place(creature: Node, cell: Vector2i, creature_size: int = 1) -> void:
	_placement[creature] = {"cell": cell, "size": creature_size}


func remove(creature: Node) -> void:
	_placement.erase(creature)


func cell_of(creature: Node) -> Vector2i:
	return _placement[creature]["cell"] if _placement.has(creature) else Vector2i(-1, -1)


func size_of(creature: Node) -> int:
	return _placement[creature]["size"] if _placement.has(creature) else 1


func creatures() -> Array:
	return _placement.keys()


## 생물이 차지한 칸(큰 생물 2×2는 4칸).
func occupied_cells(creature: Node) -> Array[Vector2i]:
	return footprint(cell_of(creature), size_of(creature))


static func footprint(anchor: Vector2i, creature_size: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in creature_size:
		for dx in creature_size:
			out.append(anchor + Vector2i(dx, dy))
	return out


func creature_at(c: Vector2i) -> Node:
	for cr: Node in _placement.keys():
		if c in occupied_cells(cr):
			return cr
	return null


## 생물을 옮긴다. on_leave_tile·on_enter_tile을 보낸다(강제 이동 포함).
func move_creature(creature: Node, to: Vector2i) -> void:
	var from := cell_of(creature)
	EventBus.on_leave_tile.emit(creature, from)
	_placement[creature]["cell"] = to
	EventBus.on_enter_tile.emit(creature, to)


# ---------- 거리 ----------

## 거리 = max(|dx|, |dy|)(3단계).
static func distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## 두 생물 사이 거리. 큰 생물은 점유 칸 둘레 전체에서 센다(9단계 충돌 E).
func distance_between(a: Node, b: Node) -> int:
	var best := 1 << 30
	for ca in occupied_cells(a):
		for cb in occupied_cells(b):
			best = mini(best, distance(ca, cb))
	return best


# ---------- 이동 ----------

func blocks_movement(c: Vector2i) -> bool:
	if not in_bounds(c):
		return true
	if has_flag(c, "wall") or has_flag(c, "impassable"):
		return true
	return not object_at(c).is_empty() and object_at(c).get("blocks_movement", true)


## 한 칸 걸음이 가능한가(지형만, 생물은 보지 않는다).
## 대각선: 양옆 직교 칸 중 하나라도 벽·통행 불가면 불가(생물은 모서리로 치지 않는다).
## 높이: 1단계는 그냥 걷고, 2단계 이상 오르기는 오르기 지점에서만, 2단계 이상 내려가기는 불가
## (점프·낙하로만, changes.md 2026-11-22).
func can_step(from: Vector2i, to: Vector2i, climber: bool = false, no_climb: bool = false) -> bool:
	var d := to - from
	if absi(d.x) > 1 or absi(d.y) > 1 or d == Vector2i.ZERO:
		return false
	if blocks_movement(to):
		return false
	if d.x != 0 and d.y != 0:
		if _corner_blocks(from + Vector2i(d.x, 0)) or _corner_blocks(from + Vector2i(0, d.y)):
			return false
	var dh := height(to) - height(from)
	if climber and absi(dh) >= 2:
		return true  # 등반 속도(로그 2층 작업): 오르기 지점이 아니어도 오르내린다
	if dh >= 2:
		return not no_climb and (has_flag(from, "climb") or has_flag(to, "climb"))  # 짐 매우 무거움: 오르기 불가
	if dh <= -2:
		return false
	return true


func _corner_blocks(c: Vector2i) -> bool:
	return not in_bounds(c) or has_flag(c, "wall") or has_flag(c, "impassable")


## 들어가는 칸의 이동 비용. 어려운 지형 2배, 오르기는 높이 1단계마다 +1칸(3단계).
## mover가 질주한 턴에 능력 태그 dash_ignores_difficult(날랜 발)면 어려운 지형을 1배로.
func step_cost(from: Vector2i, to: Vector2i, mover: Node = null) -> int:
	var easy: bool = mover != null and ((mover.has_cap("dash_ignores_difficult") and mover.turn.get("dashed", false)) or mover.has_cap("ignore_difficult_terrain"))
	var cost := 2 if is_difficult(to) and not easy else 1
	if not easy and surface_id(to) != "":
		cost = maxi(cost, int(RulesDB.get_entry("surface", surface_id(to)).get("move_cost", 0)))  # 무성한 풀(식물 성장 — BG3 속도 1/4): 1칸 4
	var dh := height(to) - height(from)
	if dh >= 2:
		cost += dh
	return cost


func is_difficult(c: Vector2i) -> bool:
	if has_flag(c, "difficult"):
		return true
	var sid := surface_id(c)
	return sid != "" and RulesDB.get_entry("surface", sid).get("difficult", false)


## 큰 생물까지 한 걸음 가능한지(점유 칸 모두가 같은 방향으로 걸을 수 있어야 한다).
func can_step_sized(from_anchor: Vector2i, to_anchor: Vector2i, creature_size: int, mover: Node = null,
		ignore: Array = []) -> bool:
	var d := to_anchor - from_anchor
	var climber: bool = mover != null and mover.is_climber() and not mover.has_flag("no_climb")
	var no_climb: bool = mover != null and mover.has_flag("no_climb")
	for c in footprint(from_anchor, creature_size):
		if not can_step(c, c + d, climber, no_climb):
			return false
	for c in footprint(to_anchor, creature_size):
		var other := creature_at(c)
		if other != null and other != mover and not ignore.has(other):
			return false
	return true


## 경로 탐색(A*). 결과: {"path": [칸...](출발 제외), "cost": int}. 길이 없으면 빈 Dictionary.
## max_cost를 넘는 길은 찾지 않는다(-1 = 제한 없음). 다른 생물 칸은 지나갈 수 없다(ignore로 예외).
## penalty: {칸: 추가 가중치} — AI가 위험한 표면을 돌아가게(실제 이동 비용 cost에는 넣지 않는다).
func find_path(mover: Node, to: Vector2i, max_cost: int = -1, ignore: Array = [], penalty: Dictionary = {}) -> Dictionary:
	var start := cell_of(mover)
	var sz := size_of(mover)
	if start == to:
		return {"path": [], "cost": 0}
	var open := {start: 0}
	var came := {}
	var g := {start: 0}
	var wg := {start: 0}  # 가중 비용(실제 비용 + 위험 가중치)
	while not open.is_empty():
		var cur: Vector2i = Vector2i.ZERO
		var best := 1 << 30
		for c: Vector2i in open.keys():
			if open[c] < best:
				best = open[c]
				cur = c
		if cur == to:
			var path: Array[Vector2i] = []
			var c := cur
			while c != start:
				path.push_front(c)
				c = came[c]
			return {"path": path, "cost": g[to]}
		open.erase(cur)
		for d in DIRS_8:
			var nxt := cur + d
			if not can_step_sized(cur, nxt, sz, mover, ignore):
				continue
			var cost: int = g[cur]
			for c in footprint(nxt, sz):
				cost = maxi(cost, g[cur] + step_cost(c - d, c, mover))
			if max_cost >= 0 and cost > max_cost:
				continue
			var wcost: int = int(wg[cur]) + (cost - int(g[cur])) + int(penalty.get(nxt, 0))
			if not wg.has(nxt) or wcost < int(wg[nxt]):
				g[nxt] = cost
				wg[nxt] = wcost
				came[nxt] = cur
				open[nxt] = wcost + distance(nxt, to)
	return {}


# ---------- 시야 ----------

## 두 칸 사이를 지나는 칸(양 끝 제외). 선이 칸 모서리를 정확히 지나면 양옆 두 칸을 짝으로 넣는다.
## 결과 항목: Vector2i 또는 [Vector2i, Vector2i](모서리 짝)
static func line_between(a: Vector2i, b: Vector2i) -> Array:
	var out: Array = []
	var dx := b.x - a.x
	var dy := b.y - a.y
	var nx := absi(dx)
	var ny := absi(dy)
	var sx := signi(dx)
	var sy := signi(dy)
	var p := a
	var ix := 0
	var iy := 0
	while ix < nx or iy < ny:
		var decision := (1 + 2 * ix) * ny - (1 + 2 * iy) * nx
		if decision == 0:
			out.append([p + Vector2i(sx, 0), p + Vector2i(0, sy)])
			p += Vector2i(sx, sy)
			ix += 1
			iy += 1
		elif decision < 0:
			p += Vector2i(sx, 0)
			ix += 1
		else:
			p += Vector2i(0, sy)
			iy += 1
		if p != b:
			out.append(p)
	return out


func _blocks_sight(c: Vector2i, walls_only: bool) -> bool:
	if not in_bounds(c) or has_flag(c, "wall") or has_flag(c, "blocks_sight"):
		return true
	if walls_only:
		return false
	var cid := cloud_id(c)
	return cid != "" and RulesDB.get_entry("surface", cid).get("blocks_sight", false)


## 시야선: 사이에 벽·시야 차단 칸, 시야를 끊는 구름이 없는가. 높이는 막지 않는다(changes.md).
## 모서리 짝은 둘 다 막혀야 막힌다. walls_only면 구름은 보지 않는다(범위 판정용).
func has_line_of_sight(a: Vector2i, b: Vector2i, walls_only: bool = false) -> bool:
	for item: Variant in line_between(a, b):
		if item is Array:
			if _blocks_sight(item[0], walls_only) and _blocks_sight(item[1], walls_only):
				return false
		elif _blocks_sight(item, walls_only):
			return false
	return true


# ---------- 빛·가려짐 ----------

## 칸의 빛 단계: 기본 빛과 광원(원형 마스크, 시야선이 닿는 칸) 중 밝은 쪽. 마법 어둠은 늘 어둠.
func light_at(c: Vector2i) -> int:
	if cloud_id(c) != "" and RulesDB.get_entry("surface", cloud_id(c)).get("ignores_darkvision", false):
		return Light.DARK
	var level := base_light(c)
	for src in light_sources:
		if level == Light.BRIGHT:
			break
		var src_cell: Vector2i = cell_of(src["creature"]) if src.get("creature") != null and _placement.has(src["creature"]) else src["cell"]
		var d: Vector2i = c - src_cell
		var r2 := d.x * d.x + d.y * d.y
		var bright: int = src["bright"]
		var dim: int = bright + int(src.get("dim", 0))
		if r2 <= bright * bright + bright and has_line_of_sight(src_cell, c, true):
			level = Light.BRIGHT
		elif r2 <= dim * dim + dim and has_line_of_sight(src_cell, c, true):
			level = maxi(level, Light.DIM)
	return level


## 관찰자가 칸을 볼 때의 가려짐: 0 없음, 1 가볍게, 2 심하게(4단계 빛, SRD Obscured).
## 암시야는 12칸 안에서 가려짐을 한 단계 낮춘다(마법 어둠 제외).
func obscurity_for(observer: Node, c: Vector2i) -> int:
	var cid := cloud_id(c)
	var cdef: Dictionary = RulesDB.get_entry("surface", cid) if cid != "" else {}
	if cdef.get("ignores_darkvision", false):
		return 2
	var level := 0
	match light_at(c):
		Light.DARK:
			level = 2
		Light.DIM:
			level = 1
	var dv: int = observer.darkvision_tiles if observer.darkvision_tiles > 0 else DARKVISION_TILES
	if level > 0 and observer.senses.has("darkvision") and distance(cell_of(observer), c) <= dv:
		level -= 1
	match cdef.get("obscurity", ""):
		"heavy":
			level = 2
		"light":
			level = maxi(level, 1)
	return level


## 관찰자가 생물을 볼 수 있는가: 실명이 아니고, 시야선이 있고, 대상이 심하게 가려지지 않았다.
## 투명 상태는 여기서 보지 않는다(상태 수정치가 따로 처리).
func can_see(observer: Node, target: Node) -> bool:
	if observer.has_condition("blinded"):
		return false
	var from := cell_of(observer)
	if cloud_id(from) != "" and RulesDB.get_entry("surface", cloud_id(from)).get("obscurity", "") == "heavy":
		return false  # 심하게 가려진 곳 안에서는 밖을 볼 수 없다
	for c in occupied_cells(target):
		if has_line_of_sight(from, c) and obscurity_for(observer, c) < 2:
			return true
	return false


# ---------- 판정 연결 ----------

## 생물의 높이 = 칸 높이 + 고도(비행·부양).
func elevation(c: Node) -> int:
	return height(cell_of(c)) + int(c.altitude)


## Resolver.attack에 넘길 상황(ctx)을 격자에서 계산한다.
## 거리, 높이 차, 볼 수 없는 대상·공격자(SRD Unseen Attackers and Targets), 공포 원인 시야.
func attack_context(attacker: Node, target: Node) -> Dictionary:
	var ctx := {"distance_tiles": distance_between(attacker, target),
		"height_diff": elevation(attacker) - elevation(target),
		"advantage": [], "disadvantage": []}
	if not can_see(attacker, target):
		ctx["disadvantage"].append("보이지 않는 대상")
	if not can_see(target, attacker):
		ctx["advantage"].append("대상이 공격자를 못 봄")
	var fear: Dictionary = attacker.condition_instance("frightened")
	if not fear.is_empty() and fear["source"] is Node and _placement.has(fear["source"]):
		ctx["source_in_sight"] = can_see(attacker, fear["source"])
	return ctx


## 사거리: 낮은 대상에게 높이 1단계마다 +1칸(4단계 높은 곳).
func effective_range(attacker: Node, target_cell: Vector2i, base_range: int) -> int:
	return base_range + maxi(height(cell_of(attacker)) - height(target_cell), 0)


func in_range(attacker: Node, target: Node, base_range: int) -> bool:
	return distance_between(attacker, target) <= effective_range(attacker, cell_of(target), base_range)
