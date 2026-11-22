extends "res://scripts/rules/effect_script.gd"
## Tiny Hut(3레벨): 캠프 불가 구역에서도 긴 휴식(룰북 7단계). 시전 자리에 오두막을 세운다(긴 휴식까지).

const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	ctx["world"]["tiny_hut"] = {"cell": U.grid(ctx).cell_of(ctx["self"]), "instance": ctx["instance"]["id"]}
	U.entity(ctx, "tiny_hut", U.grid(ctx).cell_of(ctx["self"]))
	U.on_end(ctx, func() -> void: ctx["world"].erase("tiny_hut"))
	return {"ok": true}
