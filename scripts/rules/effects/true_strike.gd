extends "res://scripts/rules/effect_script.gd"
## True Strike(BG3 수치): 행동, 12칸 안 생물 하나를 노린다. 집중 2턴 동안 그 생물에게 하는 다음 공격 굴림 1회 유리.
const U := preload("res://scripts/rules/spell_util.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Node = U.target(ctx)
	if t == null or t == c:
		return {"ok": false, "reason": "대상이 없다"}
	c.extra_modifiers.append({"effect": {"type": "advantage", "roll": "attack", "side": "self", "value": "advantage"},
		"source": "true_strike", "instance": ctx["instance"]["id"], "turns_left": -1,
		"consume_on_attack": true, "target_only": t})
	ctx["instance"]["targets"].append(c)
	return {"ok": true}
