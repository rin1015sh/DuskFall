extends "res://scripts/rules/effect_script.gd"
## 자연의 장막(레인저 14레벨, SRD): 보너스 행동, 다음 내 턴 끝까지 투명. 지혜 수정치(최소 1)회, 긴 휴식.


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	c.apply_condition("invisible", 2, c)
	Dice.log_text("%s: 자연의 장막" % c.label())
	return {"ok": true}
