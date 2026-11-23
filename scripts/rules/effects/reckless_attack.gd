extends "res://scripts/rules/effect_script.gd"
## 무모한 공격(바바리안 2레벨, SRD): 턴의 첫 공격 전에(행동 없음) 다음 자기 턴 시작까지 근력 공격 유리, 나를 노리는 공격 유리.
## turn["reckless"]는 광란(광전사)이 본다.


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	if c.turn.get("reckless", false):
		return {"ok": false, "reason": "이미 무모하게 공격 중"}
	if int(c.turn.get("attacks_made", 0)) > 0:
		return {"ok": false, "reason": "턴의 첫 공격 전에만"}
	c.turn["reckless"] = true
	c.extra_modifiers.append({"effect": {"type": "advantage", "roll": "attack", "side": "self", "value": "advantage", "ability": ["str"]},
		"source": "reckless_attack", "until_turn_start_of": c})
	c.extra_modifiers.append({"effect": {"type": "advantage", "roll": "attack", "side": "against", "value": "advantage"},
		"source": "reckless_attack", "until_turn_start_of": c})
	Dice.log_text("%s: 무모한 공격" % c.label())
	return {"ok": true}
