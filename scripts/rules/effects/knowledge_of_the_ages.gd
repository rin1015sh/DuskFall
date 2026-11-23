extends "res://scripts/rules/effect_script.gd"
## 시대의 지식(지식 영역 2레벨, BG3): 행동 + 신성 변환. 고른 능력(상시 설정 knowledge_of_the_ages)의 모든 기능에 긴 휴식까지 숙련.
const SKILLS := {"str": ["athletics"], "dex": ["acrobatics", "sleight_of_hand", "stealth"],
	"int": ["arcana", "history", "investigation", "nature", "religion"], "wis": ["animal_handling", "insight", "medicine", "perception", "survival"],
	"cha": ["deception", "intimidation", "performance", "persuasion"]}


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var ab := str(c.options.get("knowledge_of_the_ages", "int"))
	var added: Array = c.get_meta("temp_skills", []).duplicate()
	for sk: String in SKILLS.get(ab, []):
		if not c.skill_bonuses.has(sk):
			c.skill_bonuses[sk] = c.proficiency_bonus
			added.append(sk)
	c.set_meta("temp_skills", added)  # 긴 휴식(rest.gd)에 지운다
	Dice.log_text("%s 시대의 지식: %s 기능 숙련" % [c.label(), ab])
	return {"ok": true, "skills": added}
