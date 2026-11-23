extends "res://scripts/rules/effect_script.gd"
## 분노 연장(바바리안, SRD): 보너스 행동으로 이번 턴 분노를 잇는다. 이미 공격·내성 강요로 이어졌으면 쓰지 않는다(AI는 턴 끝에 필요할 때만).


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	if not c.has_condition("raging"):
		return {"ok": false, "reason": "분노 중이 아니다"}
	if c.turn.get("rage_kept", false):
		return {"ok": false, "reason": "이미 이어진다"}
	c.turn["rage_kept"] = true
	Dice.log_text("%s: 분노 연장" % c.label())
	return {"ok": true}
