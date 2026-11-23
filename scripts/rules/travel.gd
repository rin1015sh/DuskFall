extends RefCounted
## 맵 이동(구현 어려운 것 묶음 3): 파티·소지품·진행 상태를 들고 다른 맵으로. 떠난 맵의 상태는 저장해 두고
## 돌아오면 되살린다(쓰러뜨린 적·연 상자·함정). 캠프(camp 맵)는 들어가면 긴 휴식, 쉬는 동료와 교체(룰북 7단계).

const WorldBuilder := preload("res://scripts/rules/world_builder.gd")
const SaveGame := preload("res://scripts/rules/save_game.gd")

## 맵을 넘어 들고 가는 세계 값
const CARRY := ["stash", "inspiration", "short_rests_left", "party_resources", "dialogue_tags", "flags",
	"goals_done", "xp", "options", "roster", "map_states", "shop_stock", "return_to"]


## 떠나기: 지금 맵 상태를 map_states에 넣고 들고 갈 값을 돌려준다.
static func leave(world: Dictionary) -> Dictionary:
	var carry := {}
	for k: String in CARRY:
		if world.has(k):
			carry[k] = world[k]
	if not carry.has("map_states"):
		carry["map_states"] = {}
	carry["map_states"][world["map_id"]] = SaveGame.snapshot(world)
	return carry


## 들어가기: 파티(노드 그대로)를 새 맵의 spawn 칸 근처에 놓는다. spawn이 "return"이면 떠날 때 자리(return_to).
## 결과: WorldBuilder.build 결과({world, party, foes, nodes})
static func enter(map_id: String, party: Array, carry: Dictionary, spawn: String) -> Dictionary:
	var names: Array = party.map(func(c: Node) -> String: return str(c.name))
	for c: Node in carry.get("roster", []):
		names.append(str(c.name))
	var b := WorldBuilder.build(map_id, {"skip": names})
	var w: Dictionary = b["world"]
	var grid: Node = w["grid"]
	# 전에 와 본 맵이면 상태를 되살린다(파티는 빼고)
	var states: Dictionary = carry.get("map_states", {})
	if states.has(map_id):
		SaveGame.restore(w, states[map_id], {"skip": names})
	for k: String in carry:
		w[k] = carry[k]
	w["map_id"] = map_id
	var at := Vector2i(-1, -1)
	if spawn == "return" and carry.get("return_to", {}).get("map", "") == map_id:
		at = Vector2i(int(carry["return_to"]["cell"][0]), int(carry["return_to"]["cell"][1]))
	else:
		var sp: Dictionary = w.get("spawn_cells", {})
		if sp.has(spawn):
			at = sp[spawn]
	if at.x < 0:
		at = grid.size / 2
	var placed: Array = []
	for c: Node in party + (carry.get("roster", []) if RulesDB.get_entry("map", map_id).get("camp", false) else []):
		if c.dead and not c in party:
			continue
		var cell := _free_near(grid, at, placed)
		placed.append(cell)
		c.altitude = 0
		c.awareness.clear()
		grid.place(c, cell, 1)
	w["party"] = party
	b["party"] = party
	b["foes"] = b["foes"]
	return b


static func _free_near(grid: Node, at: Vector2i, taken: Array) -> Vector2i:
	for r in range(0, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := at + Vector2i(dx, dy)
				if grid.in_bounds(c) and not grid.blocks_movement(c) and grid.creature_at(c) == null and not c in taken:
					return c
	return at


## 캠프로: 돌아올 자리를 적어 둔다. 캠프 불가 구역이면 못 간다(Tiny Hut 예외는 Rest가 판단).
static func can_go_camp(world: Dictionary, leader: Node) -> String:
	if world.get("turns") != null and world["turns"].in_combat:
		return "전투 중에는 쉴 수 없다"
	var why: String = load("res://scripts/rules/rest.gd").blocked_reason(world, world.get("party", []))
	if why != "":
		return why
	var g: Node = world["grid"]
	if g.has_flag(g.cell_of(leader), "no_camp") and world.get("tiny_hut", {}).is_empty():
		return "여기서는 캠프를 칠 수 없다"
	return ""
