extends "res://scripts/rules/effect_script.gd"
## 최상급 은신(도둑형 9레벨, BG3): 행동, 10턴 동안 투명(공격하거나 주문을 쓰면 풀린다). 짧은 휴식마다 1회.


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	c.apply_condition("invisible", 10, "supreme_sneak", {"ends_on_attack": true})
	Dice.log_text("%s: 최상급 은신 — 투명" % c.label())
	return {"ok": true}
