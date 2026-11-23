extends "res://scripts/rules/effect_script.gd"
## 야생 변신 풀기(보너스 행동).


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	if not c.has_meta("beast_form"):
		return {"ok": false, "reason": "변신 중이 아니다"}
	load("res://scripts/rules/effects/wild_shape.gd").revert(c)
	return {"ok": true}
