extends "res://scripts/rules/effect_script.gd"
## 야생의 부활(드루이드 5레벨, SRD): 행동 없이 — 야생 변신이 없으면 주문 슬롯(가장 낮은 것)으로 1회 얻기(턴당 1회),
## 또는 opts.mode = "slot"이면 야생 변신 1회로 1레벨 슬롯 하나(긴 휴식마다 1회 — 자원 wild_resurgence).


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	if str(ctx.get("opts", {}).get("mode", "shape")) == "slot":
		if c.resource("wild_resurgence") <= 0 or c.resource("wild_shape") <= 0:
			return {"ok": false, "reason": "쓸 수 없다"}
		c.spend_resource("wild_resurgence")
		c.spend_resource("wild_shape")
		c.resources["spell_slot_1"]["current"] = int(c.resources["spell_slot_1"]["current"]) + 1
		return {"ok": true, "slot": 1}
	if c.resource("wild_shape") > 0 or c.turn.get("resurgence_used", false):
		return {"ok": false, "reason": "야생 변신이 남아 있다"}
	var slot: String = load("res://scripts/rules/reaction_queue.gd").lowest_slot(c, 1)
	if slot == "":
		return {"ok": false, "reason": "주문 슬롯이 없다"}
	c.spend_resource(slot)
	c.resources["wild_shape"]["current"] = 1
	c.turn["resurgence_used"] = true
	return {"ok": true}
