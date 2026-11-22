extends "res://scripts/rules/effect_script.gd"
## Mind Spike(SRD): 지혜 내성 3d8 정신(성공 절반). 실패하면 집중 동안 위치를 안다: 숨거나 투명해도 시전자에겐 효과 없음.
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Area := preload("res://scripts/rules/area.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var r := Spellcasting.resolve_effects(ctx)
	for t: Node in r.get("affected", []):
		c.senses.append("track_%d" % t.get_instance_id())
		t.extra_modifiers.append({"effect": {"type": "modify", "stat": "tracked_by", "by": c}, "source": "mind_spike",
			"instance": ctx["instance"]["id"], "turns_left": -1})
	return {"ok": true}
