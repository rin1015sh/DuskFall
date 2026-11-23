extends RefCounted
## 몬스터 데이터(data/monsters/<id>.json) → Creature. /add-monster 변환 규칙(룰북 2·4·7단계).

const CreatureScript := preload("res://scripts/rules/creature.gd")

const SIZE_CELLS := {"tiny": 1, "small": 1, "medium": 1, "large": 2, "huge": 3, "gargantuan": 4}
## 재충전 → 고정 쿨다운(룰북 2단계): 5~6 → 3턴, 6 → 6턴
const RECHARGE_TURNS := {"5-6": 3, "6": 6}


static func spawn(id: String, team: String = "enemy") -> Node:
	var m := RulesDB.get_entry("monster", id)
	if m.is_empty():
		push_error("모르는 몬스터 '%s'" % id)
		return null
	var c: Node = CreatureScript.new()
	c.name = id
	c.display_name = m["name"].duplicate()
	c.team = team
	c.is_player_character = false
	c.size = m["size"]
	c.creature_type = m["creature_type"]
	c.abilities = m["abilities"].duplicate()
	c.proficiency_bonus = int(m["proficiency_bonus"])
	c.ac_base = int(m["ac"])
	c.hp_max = int(m["hp"])
	c.hp = c.hp_max
	c.speed_tiles = int(m["speed_tiles"])
	c.weight_kg = float(m["weight_kg"])
	c.darkvision_tiles = int(m.get("senses", {}).get("darkvision_tiles", 0))
	c.senses = ["darkvision"] if c.darkvision_tiles > 0 else []
	c.damage_resistances = m.get("resistances", []).duplicate()
	c.damage_vulnerabilities = m.get("vulnerabilities", []).duplicate()
	c.damage_immunities = m.get("immunities", []).duplicate()
	c.condition_immunities = m.get("condition_immunities", []).duplicate()
	c.save_overrides = m["saves"].duplicate()
	for s: String in m.get("skills", {}).keys():
		c.skill_bonuses[s] = int(m["skills"][s])
	c.features = []
	c.feature_hooks = {}
	for t: Dictionary in m.get("traits", []):
		c.features.append(t["id"])
		c.feature_data[t["id"]] = t
		if t.has("hook") and t.has("script"):
			if not c.feature_hooks.has(t["hook"]):
				c.feature_hooks[t["hook"]] = []
			c.feature_hooks[t["hook"]].append(t["script"])
	for b: Dictionary in m.get("bonus_actions", []):
		c.features.append(b["id"])
		c.feature_data[b["id"]] = b
	c.set_meta("monster", m)
	c.set_meta("cells", SIZE_CELLS.get(m["size"], 1))
	c.set_meta("art", m.get("art", {}))
	c.attacks_per_action = int(m.get("multiattack", {}).get("count", 1))
	c.weapon_sets = {"melee": {"main": "", "off": ""}, "ranged": {"main": ""}}
	c.known_reactions = ["opportunity_attack"]
	c.sight_tiles = int(m.get("sight_cone_tiles", 8))
	c.faction = id
	c.reset_turn()
	return c


static func actions(c: Node) -> Array:
	return c.get_meta("monster", {}).get("actions", []) if c.has_meta("monster") else []


static func action(c: Node, id: String) -> Dictionary:
	for a: Dictionary in actions(c):
		if a["id"] == id:
			return a
	return {}


## 행동 정의 → Resolver.attack 공격 정의. use = "melee" | "ranged"(근접·투척 겸용 무기)
static func to_attack(a: Dictionary, use: String = "") -> Dictionary:
	var kind: String = a.get("kind", "melee")
	if kind == "both":
		kind = use if use != "" else "melee"
	var rng: Variant = a.get("range_tiles", [a.get("reach_tiles", 1), a.get("reach_tiles", 1)])
	return {"name": a["name"]["en"], "bonus": int(a["bonus"]), "kind": kind, "weapon": true, "monster_action": a["id"],
		"damage": a["damage"].duplicate(true), "extra_if_advantage": a.get("extra_if_advantage", []).duplicate(true),
		"properties": ["reach"] if int(a.get("reach_tiles", 1)) >= 2 else [],
		"reach_tiles": int(a.get("reach_tiles", 1)),
		"range_tiles": rng if kind == "ranged" else [int(a.get("reach_tiles", 1)), int(a.get("reach_tiles", 1))]}


## 근접 도달(기회 공격용): 근접 행동 중 가장 긴 도달
static func melee_reach(c: Node) -> int:
	var best := 0
	for a: Dictionary in actions(c):
		if a["type"] == "attack" and a.get("kind", "melee") in ["melee", "both"]:
			best = maxi(best, int(a.get("reach_tiles", 1)))
	return best
