extends "res://scripts/rules/effect_script.gd"
## 영감의 샘(바드 5레벨, SRD): 행동 없이 주문 슬롯 하나(가장 낮은 것)를 써서 바드의 영감 1회를 되찾는다.
## (짧은 휴식에 전부 회복은 자원 recharge 레벨표로.)


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var r: Dictionary = c.resources.get("bardic_inspiration", {})
	if r.is_empty() or int(r["current"]) >= int(r["max"]):
		return {"ok": false, "reason": "영감이 가득하다"}
	var slot: String = load("res://scripts/rules/reaction_queue.gd").lowest_slot(c, 1)
	if slot == "":
		return {"ok": false, "reason": "주문 슬롯이 없다"}
	c.spend_resource(slot)
	r["current"] = int(r["current"]) + 1
	Dice.log_text("%s: 영감의 샘(%s)" % [c.label(), slot])
	return {"ok": true}
