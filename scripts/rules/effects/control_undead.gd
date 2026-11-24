extends "res://scripts/rules/effect_script.gd"
## 언데드 조종(맹세 파기자, BG3): 행동 + 신성 변환, 4칸(6m) 안 언데드 지혜 내성 실패 시 긴 휴식까지 내 편(팀이 바뀐다).
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	if not (t is Node) or t.dead or str(t.creature_type) != "undead" or not t.is_hostile_to(c):
		return {"ok": false, "reason": "적 언데드만"}
	if ctx["world"]["grid"].distance_between(c, t) > 4:
		return {"ok": false, "reason": "4칸 안"}
	if Resolver.saving_throw(t, "wis", 8 + c.proficiency_bonus + c.ability_mod("cha"), {"source": c})["success"]:
		return {"ok": true, "controlled": false}
	t.set_meta("controlled_from_team", t.team)
	t.team = c.team
	Dice.log_text("%s: %s 조종" % [c.label(), t.label()])
	return {"ok": true, "controlled": true}
