extends "res://scripts/rules/effect_script.gd"
## 인내의 방어(몽크 2레벨, BG3): 보너스 행동 + 기 1, 다음 자기 턴 시작까지 나를 노리는 공격 불리·민첩 내성 유리.
func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	c.extra_modifiers.append({"effect": {"type": "advantage", "roll": "attack", "side": "against", "value": "disadvantage"}, "source": "dodge", "until_turn_start_of": c})
	c.extra_modifiers.append({"effect": {"type": "advantage", "roll": "save", "side": "self", "value": "advantage", "ability": ["dex"]}, "source": "dodge", "until_turn_start_of": c})
	Dice.log_text("%s 인내의 방어" % c.label())
	return {"ok": true}
