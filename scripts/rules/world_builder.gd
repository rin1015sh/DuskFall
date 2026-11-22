extends RefCounted
## 맵 데이터로 세계를 만든다(격자·표면·반응·턴 + 생물). 화면을 모른다 — 그림 메타는 표현 계층이 붙인다.
## 생물 배치(spawns): "monster" = 몬스터 ID, "companion" = {class, name}(영입 동료, 중립), 그 밖에는 ID가 클래스(시작 파티).
## 결과: {"world", "party", "foes"(적·중립 NPC 포함 비파티 생물), "nodes"}

const GridWorldScript := preload("res://scripts/rules/grid_world.gd")
const SurfaceSystemScript := preload("res://scripts/rules/surface_system.gd")
const ReactionQueueScript := preload("res://scripts/rules/reaction_queue.gd")
const TurnManagerScript := preload("res://scripts/rules/turn_manager.gd")
const MapLoader := preload("res://scripts/rules/map_loader.gd")
const Builder := preload("res://scripts/rules/character_builder.gd")
const MonsterFactory := preload("res://scripts/rules/monster_factory.gd")


## opts: {"level": 시작 레벨, "monster_for": Callable(spawn id) -> 몬스터 ID(시험용 덮어쓰기)}
static func build(map_id: String, opts: Dictionary = {}) -> Dictionary:
	var level := int(opts.get("level", 1))
	var grid: Node = GridWorldScript.new()
	var surfaces: Node = SurfaceSystemScript.new()
	surfaces.setup(grid)
	var world := {"grid": grid, "surfaces": surfaces}
	var loaded := MapLoader.load_into(grid, surfaces, MapLoader.load_map(map_id))
	var rq: Node = ReactionQueueScript.new().setup(world)
	var tm: Node = TurnManagerScript.new().setup(world)
	var party: Array = []
	var others: Array = []
	var spawn_cells := {}
	for sid: String in loaded["spawns"].keys():
		spawn_cells[sid] = loaded["spawns"][sid]
		if sid in opts.get("skip", []) or sid.ends_with("_entry") or sid == "return":
			continue  # 이미 있는 파티·동료(맵 이동), 들어오는 자리 표시
		var info: Dictionary = loaded["spawn_info"].get(sid, {})
		var c: Node
		var mid: String = info.get("monster", "")
		if opts.has("monster_for"):
			mid = opts["monster_for"].call(sid, mid)
		if mid != "":
			c = MonsterFactory.spawn(mid)
		elif info.has("companion"):
			var spec := Builder.default_spec(info["companion"]["class"], level)
			spec["name"] = info["companion"]["name"]
			c = Builder.build(spec)["creature"]
			c.team = "neutral"
		else:
			c = Builder.build(Builder.default_spec(sid, level))["creature"]
		c.name = sid
		if info.has("facing"):
			c.facing = info["facing"]
		if info.has("team"):
			c.team = info["team"]
		if info.has("faction"):
			c.faction = info["faction"]
		if info.has("dialogue"):
			c.set_meta("dialogue", info["dialogue"])
		grid.place(c, loaded["spawns"][sid], int(c.get_meta("cells", 1)))
		var zs: PackedStringArray = grid.zones(loaded["spawns"][sid])
		if not zs.is_empty():
			c.set_meta("home_zone", zs[0])  # 구역 보상은 배치된 구역으로 센다(쫓아 나가 죽어도)
		if info.has("light"):
			# 들고 다니는 광원(횃불 등): 생물을 따라 움직인다
			grid.light_sources.append({"id": "carried_" + sid, "cell": loaded["spawns"][sid], "creature": c,
				"bright": int(info["light"]["bright"]), "dim": int(info["light"].get("dim", 0))})
		(party if c.team == "party" else others).append(c)
	world["spawn_cells"] = spawn_cells
	world["transitions"] = RulesDB.get_entry("map", map_id).get("transitions", []).duplicate(true)
	world["traps"] = loaded["traps"]
	world["examines"] = loaded["examines"]
	world["zone_rewards"] = loaded.get("zone_rewards", {})
	world["map_id"] = map_id
	world["inventory"] = {"thieves_tools": 1, "trap_disarm_kit": 1, "rations": 4, "gold": 40, "potion_of_healing": 2}
	world["inspiration"] = 0
	world["xp"] = int(Progression_xp(level))
	world["party"] = party
	world["roster"] = []
	return {"world": world, "party": party, "foes": others, "nodes": [grid, surfaces, rq, tm] + party + others}


static func Progression_xp(level: int) -> int:
	return int(load("res://scripts/rules/progression.gd").XP_TABLE.get(level, 0))
