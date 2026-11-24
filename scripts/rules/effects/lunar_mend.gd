extends "res://scripts/rules/effect_script.gd"
## 달빛 치유(달 회합 2레벨, BG3): 보너스 행동, 야생 변신 중 가장 낮은 주문 슬롯을 써서 슬롯 레벨 × 1d8 회복.
const Resolver := preload("res://scripts/rules/resolver.gd")
const RQ := preload("res://scripts/rules/reaction_queue.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	if not c.has_meta("beast_form"):
		return {"ok": false, "reason": "야생 변신 중에만"}
	var slot := RQ.lowest_slot(c, 1)
	if slot == "":
		return {"ok": false, "reason": "주문 슬롯이 없다"}
	c.spend_resource(slot)
	var lv := int(slot.get_slice("_", 2))
	var n: int = Resolver.heal(c, Dice.roll("%dd8" % lv, "달빛 치유")["total"], c)
	return {"ok": true, "healed": n}
