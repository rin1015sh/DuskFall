extends "res://scripts/rules/effect_script.gd"
## Water Breathing(3레벨): 6칸 안 아군 최대 10명 수중 호흡(긴 휴식까지).

const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var g := U.grid(ctx)
	var c: Node = ctx["self"]
	for t: Node in g.creatures():
		if not t.dead and t.team == c.team and g.distance_between(c, t) <= 6:
			U.add_condition(ctx, t, "water_breathing")
	return {"ok": true}
