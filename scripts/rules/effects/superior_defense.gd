extends "res://scripts/rules/effect_script.gd"
## 탁월한 방어(몽크 18레벨, SRD): 내 턴에 기 3 — 1분(10턴) 동안 역장 외 모든 피해 저항(무력화되면 끝). 비용은 기능 resource·cost.


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	if c.resource("focus") < 3:
		return {"ok": false, "reason": "기가 모자란다"}
	if c.has_condition("superior_defense"):
		return {"ok": false, "reason": "이미 켜져 있다"}
	for i in 3:
		c.spend_resource("focus")
	c.apply_condition("superior_defense", 10, c)
	return {"ok": true}
