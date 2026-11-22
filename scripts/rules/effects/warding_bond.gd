extends "res://scripts/rules/effect_script.gd"
## Warding Bond(2레벨, SRD): 대상 AC +1·내성 +1·모든 피해 저항. 대상이 피해를 받으면 시전자도 같은 양을 받는다. 시전자가 0 HP가 되거나 12칸 넘게 떨어지면 끝난다.

const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var t := U.target(ctx)
	var c: Node = ctx["self"]
	if t == null or t == c:
		return {"ok": false, "reason": "다른 생물에게만"}
	U.add_condition(ctx, t, "warded")
	var id: int = ctx["instance"]["id"]
	t.extra_modifiers.append({"effect": {"type": "modify", "stat": "saving_throw", "add": "1"}, "instance": id, "source": "spell"})
	var g := U.grid(ctx)
	var cb := func(info: Dictionary) -> void:
		if info.get("target") != t or info.get("opts", {}).get("bond", false):
			return
		if c.dead or c.is_down() or g.distance_between(c, t) > 12:
			load("res://scripts/rules/spellcasting.gd").end_instance(id)
			return
		Resolver.apply_damage(c, [{"amount": int(info.get("amount", 0)), "damage_type": "force"}], {"bond": true})
	EventBus.on_damage_taken.connect(cb)
	U.on_end(ctx, func() -> void:
		if EventBus.on_damage_taken.is_connected(cb):
			EventBus.on_damage_taken.disconnect(cb))
	return {"ok": true}
