extends "res://scripts/rules/effect_script.gd"
## 안정된 조준(로그 3레벨, SRD): 보너스 행동. 이번 턴에 이동하지 않았으면 이번 턴 다음 공격 유리, 그 뒤 속도 0.


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	if c.turn.get("moved", false):
		return {"ok": false, "reason": "이번 턴에 이미 움직였다"}
	c.extra_modifiers.append({"effect": {"type": "advantage", "roll": "attack", "side": "self", "value": "advantage"},
		"source": "steady_aim", "consume_on_attack": true, "turn_ends_left": 1})
	c.turn["movement"] = 0
	c.turn["free_move_no_oa"] = 0
	return {"ok": true}
