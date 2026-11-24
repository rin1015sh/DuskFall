extends "res://scripts/rules/effect_script.gd"
## 용의 날개(용의 혈통 11레벨, BG3 — 비행): 보너스 행동으로 날기 시작하거나 내려온다(긴 휴식까지 켜 둠).
func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	if c.has_condition("flying"):
		c.remove_condition("flying")
		c.altitude = 0
		return {"ok": true, "flying": false}
	c.apply_condition("flying", -1, c)
	c.altitude = maxi(c.altitude, 1)
	return {"ok": true, "flying": true}
