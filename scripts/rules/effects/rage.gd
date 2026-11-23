extends "res://scripts/rules/effect_script.gd"
## 분노(바바리안 1레벨, SRD 원문): 보너스 행동, 중갑이면 못 한다. 상태 raging — 다음 자기 턴 끝까지, 그 턴에 적을 공격하거나
## 내성을 강요하거나 보너스 행동(분노 연장)을 쓰면 한 턴 더(turn["rage_kept"] — turn_manager.end_turn이 본다). 최대 10분(100턴), 무력화되면 끝.
## 들어가면 집중이 끊긴다(분노 중 주문·집중 불가 — 상태 플래그 no_spellcasting). 광기 없는 분노(광전사 6레벨)는 매혹·공포를 푼다.

const TURNS := 100


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
	c.turn["rage_kept"] = true  # 들어간 턴은 다음 턴 끝까지 간다
	Dice.log_text("%s: 분노" % c.label())
	return {"ok": true}
