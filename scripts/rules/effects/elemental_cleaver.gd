extends "res://scripts/rules/effect_script.gd"
## 원소 쪼개기(거인 6레벨, BG3): 분노 중 행동 없이, 분노가 끝날 때까지 무기 공격 +1d6(설정 elemental_cleaver: 산·냉기·화염·번개·천둥).
## [변형] 던지기 속성·되돌아오기는 생략.
const TYPES := ["acid", "cold", "fire", "lightning", "thunder"]


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var kind := str(c.options.get("elemental_cleaver", "fire"))
	if not kind in TYPES:
		kind = "fire"
	for k: String in TYPES:
		c.remove_condition("elemental_cleaver_" + k)
	c.apply_condition("elemental_cleaver_" + kind, -1, c)
	return {"ok": true, "damage_type": kind}
