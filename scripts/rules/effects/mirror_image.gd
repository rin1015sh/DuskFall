extends "res://scripts/rules/effect_script.gd"
## Mirror Image(SRD): 분신 3개(10턴). 맞을 때마다 남은 분신마다 d6, 3 이상이 하나라도 있으면 분신이 대신 맞는다(판정 엔진).
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Area := preload("res://scripts/rules/area.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	c.set_meta("mirror_images", 3)
	c.extra_modifiers.append({"effect": {"type": "modify", "stat": "mirror_image"}, "source": "mirror_image",
		"instance": ctx["instance"]["id"], "turns_left": 10})
	ctx["instance"]["targets"].append(c)
	ctx["instance"]["on_end"] = func() -> void:
		if is_instance_valid(c):
			c.set_meta("mirror_images", 0)
	return {"ok": true}
