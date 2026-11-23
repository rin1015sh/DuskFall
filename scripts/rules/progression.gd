extends RefCounted
## 경험치·레벨 업·동료 영입(룰북 7단계 '캠프와 동료': 영입한 동료 전원이 같은 경험치, 레벨업은 전투 밖 언제나,
## SRD 경험치 표·상한은 data/rules/progression.json). 경험치는 파티 공용 world["xp"].

const SpellPrep := preload("res://scripts/rules/spell_prep.gd")
const Builder := preload("res://scripts/rules/character_builder.gd")

const Levels := preload("res://scripts/rules/levels.gd")
const PARTY_MAX := 4


## 레벨 상한(data/rules/progression.json)
static func level_cap() -> int:
	return Levels.level_cap()


static func level_for(xp: int) -> int:
	return Levels.level_for(xp)


static func award(world: Dictionary, xp: int, why: String = "") -> void:
	world["xp"] = int(world.get("xp", 0)) + xp
	Dice.log_text("경험치 +%d%s (합계 %d)" % [xp, " — " + why if why != "" else "", world["xp"]])


## 쓰러뜨린 적의 경험치(몬스터 데이터 xp)를 모은다. 전투가 끝날 때 부른다.
static func award_defeated(world: Dictionary, foes: Array) -> int:
	var total := 0
	for f: Node in foes:
		if f.dead and not f.get_meta("xp_given", false):
			f.set_meta("xp_given", true)
			total += int(f.get_meta("monster", {}).get("xp", 0))
	if total > 0:
		award(world, total, "전투")
	return total


static func can_level_up(world: Dictionary, c: Node) -> bool:
	if not c.has_meta("spec") or c.dead:
		return false
	if world.get("turns") != null and world["turns"].in_combat:
		return false
	return c.level < level_for(int(world.get("xp", 0)))


## 한 레벨 올린다: 명세를 다시 적용하고, 잃은 HP는 그대로 둔다(최대치가 늘어난 만큼 현재 HP도 는다).
static func level_up(world: Dictionary, c: Node) -> bool:
	if not can_level_up(world, c):
		return false
	var spec: Dictionary = c.get_meta("spec").duplicate(true)
	spec["level"] = c.level + 1
	if not Builder.validate(spec).is_empty():
		return false
	Builder.reapply(c, spec)
	SpellPrep.open_window(c, "level_up")
	Dice.log_text("%s: %d레벨이 되었다" % [c.label(), c.level])
	return true


# ---------- 동료 영입 ----------

## 동료를 영입한다. 활성 파티가 4명이면 캠프에서 쉰다(world["roster"]).
static func recruit(world: Dictionary, c: Node) -> String:
	if c.team == "party" and (c in world.get("party", []) or c in world.get("roster", [])):
		return ""
	c.team = "party"
	c.awareness.clear()
	# 경험치는 모두 같다: 영입한 동료를 파티 레벨로 맞춘다
	while can_level_up(world, c):
		level_up(world, c)
	var party: Array = world.get("party", [])
	if party.size() < PARTY_MAX:
		party.append(c)
		world["party"] = party
		if world.get("explore") != null:
			var ex: Node = world["explore"]
			if not c in ex.party:
				ex.party.append(c)
			ex.linked[c] = true
		Dice.log_text("%s가 파티에 합류했다" % c.label())
		return "party"
	if not world.has("roster"):
		world["roster"] = []
	world["roster"].append(c)
	Dice.log_text("%s가 캠프에서 기다린다" % c.label())
	return "camp"


## 캠프에서 활성 파티 교체(캠프에서만 — world["at_camp"]).
static func swap(world: Dictionary, out_c: Node, in_c: Node) -> bool:
	if not world.get("at_camp", false):
		return false
	var party: Array = world.get("party", [])
	var roster: Array = world.get("roster", [])
	if not out_c in party or not in_c in roster:
		return false
	party[party.find(out_c)] = in_c
	roster[roster.find(in_c)] = out_c
	if world.get("explore") != null:
		var ex: Node = world["explore"]
		ex.party = party.duplicate()
		ex.linked[in_c] = true
	return true
