extends "res://scripts/rules/effect_script.gd"
## 분노(바바리안 1레벨, SRD): 보너스 행동, 중갑이면 못 한다. 상태 raging 10턴(BG3식 — 원문은 매 턴 연장, 최대 10분).
## 들어가면 집중이 끊긴다(분노 중 주문·집중 불가 — 상태 플래그 no_spellcasting). 광기 없는 분노(광전사 6레벨)는 매혹·공포를 푼다.

const TURNS := 10


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var armor := str(c.get_meta("armor", ""))
	if armor != "" and str(RulesDB.get_entry("armor", armor).get("category", "")) == "heavy":
		return {"ok": false, "reason": "중갑을 입고는 분노할 수 없다"}
	if c.has_condition("raging"):
		return {"ok": false, "reason": "이미 분노 중"}
	if not c.concentration.is_empty():
		c.break_concentration("분노")
	c.apply_condition("raging", TURNS, c)
	Dice.log_text("%s: 분노" % c.label())
	return {"ok": true}
