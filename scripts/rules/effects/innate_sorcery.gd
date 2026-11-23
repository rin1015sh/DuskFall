extends "res://scripts/rules/effect_script.gd"
## 타고난 마법(소서러 1레벨, SRD): 보너스 행동, 1분(10턴) 동안 주문 DC +1, 주문 공격 유리(상태 innate_sorcery). 긴 휴식마다 2회.


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	c.apply_condition("innate_sorcery", 10, c)
	Dice.log_text("%s: 타고난 마법" % c.label())
	return {"ok": true}
