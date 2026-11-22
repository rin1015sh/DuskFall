extends "res://scripts/rules/effect_script.gd"
## Spider Climb(2레벨): 대상이 오르기 지점이 아닌 높은 칸도 오르내린다(등반 속도).

const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var t := U.target(ctx)
	if t == null:
		return {"ok": false, "reason": "대상이 없다"}
	U.add_condition(ctx, t, "spider_climbing")
	return {"ok": true}
