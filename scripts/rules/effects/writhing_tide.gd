extends "res://scripts/rules/effect_script.gd"
## 꿈틀대는 물결(무리지기 7레벨, BG3): 보너스 행동 + 꿈틀대는 흐름 1, 10턴 비행(표면 효과 면역은 비행이 땅 표면을 피함).
func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	c.apply_condition("flying", 10, c)
	c.altitude = maxi(c.altitude, 1)
	return {"ok": true}
