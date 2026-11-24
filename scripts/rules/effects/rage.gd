extends "res://scripts/rules/effect_script.gd"
## 분노(바바리안 1레벨, BG3): 보너스 행동, 중갑이면 못 한다. 상태 raging 10턴 — 턴마다 적을 공격·내성 강요하거나(turn["rage_kept"])
## 지난 턴 뒤 피해를 받았으면(meta rage_damaged) 이어지고, 아니면 턴 끝에 끝난다(turn_manager.end_turn). 무력화되면 끝. 긴 휴식에 회복.
## 벌꿀오소리(짐승의 면모)는 ctx free = 자원 없이(행동도 쓰지 않음 — primal.turn_start가 직접 부른다).
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
	if ctx.get("free", false) and not c.resources.has("rage"):
		return {"ok": false}
	if not c.concentration.is_empty():
		c.break_concentration("분노")
	if c.has_cap("mindless_rage"):
		c.remove_condition("charmed")
		c.remove_condition("frightened")
	c.apply_condition("raging", TURNS, c)
	# 분노 변형(BG3 하위 클래스): 기능 rage_variants {능력 태그: 상태} — 분노와 함께 끝난다(상태 ends_with raging)
	var f: Dictionary = c.feature_data.get("rage", {})
	for cap: String in f.get("rage_variants", {}):
		if c.has_cap(cap):
			c.apply_condition(str(f["rage_variants"][cap]), -1, c)
	if c.has_cap("wild_magic_rage"):
		load("res://scripts/rules/primal.gd").surge(ctx.get("world", {}), c)  # 야생 마법 분노: 무작위 효과
	c.turn["rage_kept"] = true  # 들어간 턴은 다음 턴 끝까지 간다
	Dice.log_text("%s: 분노" % c.label())
	return {"ok": true}
