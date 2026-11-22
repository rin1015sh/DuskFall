extends "res://scripts/rules/effect_script.gd"
## 행동 연쇄(전사 2레벨, SRD): 이번 턴 행동 1회 추가(마법 행동 제외 — 주문 시전 쪽이 확인한다).


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	c.turn["action"] = int(c.turn.get("action", 0)) + 1
	c.turn["surge_actions"] = int(c.turn.get("surge_actions", 0)) + 1
	c.turn["surged"] = true
	return {"ok": true}
