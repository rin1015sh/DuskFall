extends "res://scripts/rules/effect_script.gd"
## 독수리의 심장(BG3): 분노 중 질주를 보너스 행동으로.
func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	c.turn["movement"] = int(c.turn.get("movement", 0)) + c.speed()
	c.turn["dashed"] = true
	if c.has_cap("dash_temp_hp"):
		load("res://scripts/rules/resolver.gd").grant_temp_hp(c, 2 * c.feature_level("rage"))
	return {"ok": true}
