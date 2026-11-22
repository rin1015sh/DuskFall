extends "res://scripts/rules/effect_script.gd"
## Fly(3레벨, SRD): 대상 1(+슬롯당 1)이 비행 — 비행 속도 12칸, 높이·지형·바닥 표면 무시, 고도 2. 끝날 때 공중이면 떨어진다.

const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var t := U.target(ctx)
	if t == null:
		return {"ok": false, "reason": "대상이 없다"}
	U.add_condition(ctx, t, "flying")
	U.set_until_end(ctx, t, "altitude", 2)
	t.extra_modifiers.append({"effect": {"type": "modify", "stat": "speed_tiles", "add": maxi(12 - t.speed_tiles, 0)}, "instance": ctx["instance"]["id"], "source": "spell"})
	U.on_end(ctx, func() -> void:
		if is_instance_valid(t) and not t.dead:
			preload("res://scripts/rules/physics.gd").fall(t, 2))
	return {"ok": true}
