extends "res://scripts/rules/effect_script.gd"
## 혼돈의 물결(야생 마법 1레벨, BG3): 행동 없이, 긴 휴식 1회. 다음 공격·판정·내성 하나에 유리(상태 tides_of_chaos — 쓰면 끝).
## 쓴 뒤로는 레벨 주문의 급증 확률이 50%(d20 11 이상)가 된다 — 급증하면 원래대로.
func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	c.apply_condition("tides_of_chaos", -1, c)
	c.set_meta("tides_used", true)
	return {"ok": true}
