extends "res://scripts/rules/effect_script.gd"
## 마법의 샘 — 슬롯을 마법 점수로(소서러 2레벨, SRD): 행동 없이 주문 슬롯 하나(opts.level, 없으면 가장 낮은 것)를
## 그 레벨만큼의 마법 점수로. 점수는 최대치를 넘지 못한다.


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var sp: Dictionary = c.resources.get("sorcery_points", {})
	if sp.is_empty() or int(sp["current"]) >= int(sp["max"]):
		return {"ok": false, "reason": "마법 점수가 가득하다"}
	var lv := int(ctx.get("opts", {}).get("level", 0))
	var slot: String = "spell_slot_%d" % lv if lv > 0 else load("res://scripts/rules/reaction_queue.gd").lowest_slot(c, 1)
	if slot == "" or c.resource(slot) <= 0:
		return {"ok": false, "reason": "주문 슬롯이 없다"}
	c.spend_resource(slot)
	var n := int(slot.get_slice("_", 2))
	sp["current"] = mini(int(sp["max"]), int(sp["current"]) + n)
	Dice.log_text("%s: %d레벨 슬롯 → 마법 점수 %d" % [c.label(), n, n])
	return {"ok": true, "points": n}
