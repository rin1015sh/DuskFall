extends RefCounted
## 4단계 시험 전투 편성: 1레벨 파티 4명(캐릭터 생성기 기본 명세 — 룰북 9단계 예시 전투 1의 구성)
## + 고블린 전사 4(data/monsters/goblin_warrior.json). 그림은 임시(assets/actors).

const GridWorldScript := preload("res://scripts/rules/grid_world.gd")
const SurfaceSystemScript := preload("res://scripts/rules/surface_system.gd")
const ReactionQueueScript := preload("res://scripts/rules/reaction_queue.gd")
const TurnManagerScript := preload("res://scripts/rules/turn_manager.gd")
const MapLoader := preload("res://scripts/rules/map_loader.gd")
const Builder := preload("res://scripts/rules/character_builder.gd")
const MonsterFactory := preload("res://scripts/rules/monster_factory.gd")

## 파티 그림(임시): 클래스 → 걷기 시트
const PARTY_ART := {
	"fighter": "res://assets/actors/human.webp", "rogue": "res://assets/actors/barbarian.webp",
	"cleric": "res://assets/actors/dwarf.webp", "wizard": "res://assets/actors/elf.webp"}


## 시험 전투 세계를 만든다. 결과: {"world", "party": [...], "foes": [...], "nodes": [만든 노드]}
static func build(map_id: String = "test_arena", level: int = 1, monster: String = "goblin_warrior") -> Dictionary:
	var grid: Node = GridWorldScript.new()
	var surfaces: Node = SurfaceSystemScript.new()
	surfaces.setup(grid)
	var world := {"grid": grid, "surfaces": surfaces}
	var loaded := MapLoader.load_into(grid, surfaces, MapLoader.load_map(map_id))
	var rq: Node = ReactionQueueScript.new().setup(world)
	var tm: Node = TurnManagerScript.new().setup(world)
	var party: Array = []
	var foes: Array = []
	for sid: String in loaded["spawns"].keys():
		var c: Node
		if sid.begins_with("goblin"):
			c = MonsterFactory.spawn(monster)
		else:
			var spec := Builder.default_spec(sid, level)
			c = Builder.build(spec)["creature"]
			c.set_meta("art", {"sheet": PARTY_ART.get(sid, "")})
		c.name = sid
		var info: Dictionary = loaded["spawn_info"].get(sid, {})
		if info.has("facing"):
			c.facing = info["facing"]
		if info.has("team"):
			c.team = info["team"]
		if info.has("dialogue"):
			c.set_meta("dialogue", info["dialogue"])
		grid.place(c, loaded["spawns"][sid], int(c.get_meta("cells", 1)))
		(party if c.team == "party" else foes).append(c)
	world["traps"] = loaded["traps"]
	world["examines"] = loaded["examines"]
	world["map_id"] = map_id
	# 시작 소지품(시험용): 도둑 도구·함정 해체 도구·식량·골드
	world["inventory"] = {"thieves_tools": 1, "trap_disarm_kit": 1, "rations": 4, "gold": 40}
	world["inspiration"] = 0
	world["party"] = party
	return {"world": world, "party": party, "foes": foes, "nodes": [grid, surfaces, rq, tm] + party + foes}
