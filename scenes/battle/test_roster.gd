extends RefCounted
## 4단계 시험 전투 편성: 1레벨 파티 4명(룰북 9단계 예시 전투 1의 수치) + 고블린 전사 4(SRD 5.2.1 Goblin Warrior).
## 5단계에서 /add-class·/add-monster 데이터로 바꾼다. 그림은 임시(assets/actors 걷기 시트).

const CreatureScript := preload("res://scripts/rules/creature.gd")
const GridWorldScript := preload("res://scripts/rules/grid_world.gd")
const SurfaceSystemScript := preload("res://scripts/rules/surface_system.gd")
const ReactionQueueScript := preload("res://scripts/rules/reaction_queue.gd")
const TurnManagerScript := preload("res://scripts/rules/turn_manager.gd")
const MapLoader := preload("res://scripts/rules/map_loader.gd")

const ROSTER := {
	"fighter": {"display_name": {"ko": "전사", "en": "Fighter"}, "team": "party", "is_player_character": true,
		"abilities": {"str": 17, "dex": 12, "con": 15, "int": 8, "wis": 12, "cha": 10}, "ac_base": 19, "hp_max": 12,
		"save_proficiencies": ["str", "con"], "weapon_proficiencies": ["simple", "martial"],
		"weapon_masteries": ["longsword", "greatsword", "shortbow"], "weight_kg": 80.0,
		"weapon_sets": {"melee": {"main": "longsword", "off": ""}, "ranged": {"main": "shortbow"}},
		"art": {"sheet": "res://assets/actors/human.webp"}},
	"rogue": {"display_name": {"ko": "로그", "en": "Rogue"}, "team": "party", "is_player_character": true,
		"abilities": {"str": 10, "dex": 16, "con": 12, "int": 12, "wis": 13, "cha": 14}, "ac_base": 14, "hp_max": 9,
		"save_proficiencies": ["dex", "int"], "weapon_proficiencies": ["simple", "martial"],
		"weapon_masteries": ["shortsword", "dagger"], "weight_kg": 25.0, "skill_bonuses": {"stealth": 5},
		"weapon_sets": {"melee": {"main": "shortsword", "off": "dagger"}, "ranged": {"main": "shortbow"}},
		"art": {"sheet": "res://assets/actors/barbarian.webp"}},
	"cleric": {"display_name": {"ko": "클레릭", "en": "Cleric"}, "team": "party", "is_player_character": true,
		"abilities": {"str": 14, "dex": 10, "con": 14, "int": 10, "wis": 16, "cha": 12}, "ac_base": 18, "hp_max": 11,
		"save_proficiencies": ["wis", "cha"], "weapon_proficiencies": ["simple"], "weight_kg": 75.0,
		"senses": ["darkvision"], "spellcasting_ability": "wis", "spells": ["sacred_flame", "healing_word", "cure_wounds"],
		"resources": {"spell_slot_1": {"current": 2, "max": 2}},
		"weapon_sets": {"melee": {"main": "mace", "off": ""}, "ranged": {"main": "light_crossbow"}},
		"art": {"sheet": "res://assets/actors/dwarf.webp"}},
	"wizard": {"display_name": {"ko": "위저드", "en": "Wizard"}, "team": "party", "is_player_character": true,
		"abilities": {"str": 8, "dex": 14, "con": 12, "int": 16, "wis": 12, "cha": 10}, "ac_base": 12, "hp_max": 7,
		"save_proficiencies": ["int", "wis"], "weapon_proficiencies": ["simple"], "weight_kg": 60.0,
		"senses": ["darkvision"], "spellcasting_ability": "int", "spells": ["fire_bolt", "ray_of_frost", "burning_hands"],
		"known_reactions": ["opportunity_attack", "shield"], "reaction_settings": {"shield": "auto"},
		"resources": {"spell_slot_1": {"current": 2, "max": 2}},
		"weapon_sets": {"melee": {"main": "quarterstaff", "off": ""}, "ranged": {"main": "dagger"}},
		"art": {"sheet": "res://assets/actors/elf.webp"}},
	"goblin_warrior": {"display_name": {"ko": "고블린 전사", "en": "Goblin Warrior"}, "team": "enemy",
		"abilities": {"str": 8, "dex": 15, "con": 10, "int": 10, "wis": 8, "cha": 8}, "ac_base": 15, "hp_max": 10,
		"weapon_proficiencies": ["simple", "martial"], "weight_kg": 20.0, "senses": ["darkvision"],
		"skill_bonuses": {"stealth": 4}, "attack_riders": [{"dice": "1d4", "when": "advantage"}],
		"weapon_sets": {"melee": {"main": "scimitar", "off": ""}, "ranged": {"main": "shortbow"}},
		"art": {"image": "res://assets/actors/monsters/goblin.webp"}},
}


## 시험 전투 세계를 만든다. 결과: {"world", "party": [...], "foes": [...], "nodes": [만든 노드]}
static func build(map_id: String = "test_arena") -> Dictionary:
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
		var key := "goblin_warrior" if sid.begins_with("goblin") else sid
		var spec: Dictionary = ROSTER[key].duplicate(true)
		var art: Dictionary = spec["art"]
		spec.erase("art")
		var c: Node = CreatureScript.new()
		c.name = sid
		c.setup(spec)
		c.set_meta("art", art)
		grid.place(c, loaded["spawns"][sid])
		(party if c.team == "party" else foes).append(c)
	return {"world": world, "party": party, "foes": foes, "nodes": [grid, surfaces, rq, tm] + party + foes}
