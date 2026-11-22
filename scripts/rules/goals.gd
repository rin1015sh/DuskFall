extends RefCounted
## 배경 영감 목표(룰북 5단계 '영감 획득'): 활성 파티원의 배경 목표를 처음 달성하면 공용 영감 +1(최대 4).
## 이미 4점이면 경험치만 받는다. 목표마다 한 번(world["goals_done"]).

const INSPIRATION_MAX := 4
## 영감이 가득할 때 대신 받는 경험치 [확인 필요: changes.md]
const OVERFLOW_XP := 50


static func party_of(world: Dictionary) -> Array:
	if world.has("party"):
		return world["party"]
	if world.get("explore") != null:
		return world["explore"].party
	return []


## 목표 달성 알림. 결과: "inspiration" | "xp" | ""(해당 배경 없음·이미 달성)
static func complete(world: Dictionary, goal: String) -> String:
	if not world.has("goals_done"):
		world["goals_done"] = {}
	if world["goals_done"].has(goal):
		return ""
	var owner: Node = null
	for c: Node in party_of(world):
		if c.dead or c.background_id == "":
			continue
		var bg := RulesDB.get_entry("background", c.background_id)
		if goal in bg.get("inspiration_goals", []):
			owner = c
			break
	if owner == null:
		return ""
	world["goals_done"][goal] = owner.name
	var cur := int(world.get("inspiration", 0))
	if cur >= INSPIRATION_MAX:
		world["xp"] = int(world.get("xp", 0)) + OVERFLOW_XP
		Dice.log_text("%s의 목표 달성(%s): 영감이 가득해 경험치 %d" % [owner.label(), goal, OVERFLOW_XP])
		return "xp"
	world["inspiration"] = cur + 1
	Dice.log_text("%s의 목표 달성(%s): 영감 +1" % [owner.label(), goal])
	return "inspiration"
