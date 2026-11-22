extends "res://scripts/rules/effect_script.gd"
## Druidcraft(소마법): 연출 전용, 규칙 효과 없음(주문 변환표).

const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	Dice.log_text("%s: 작은 자연 현상" % ctx["self"].label())
	return {"ok": true}
