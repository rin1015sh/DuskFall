extends "res://scripts/rules/effect_script.gd"
## 위엄의 망토(매혹 학파 6레벨, BG3): 보너스 행동, 10턴 동안 매 턴 보너스 행동으로 명령(슬롯 없이). 긴 휴식 1회.
func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	c.apply_condition("mantle_of_majesty", 10, c)
	return {"ok": true}
