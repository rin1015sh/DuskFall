extends "res://scripts/rules/effect_script.gd"
## 성스러운 후광(헌신의 맹세 20레벨, SRD): 보너스 행동, 10분(100턴) — 보호의 오라 안에서 턴을 시작하는 적은 매력 + 숙련 광휘(resolver.start_turn).
## 긴 휴식 1회, 없으면 5레벨 슬롯으로(기능 alt_cost). 악마·언데드 내성 유리·햇빛은 1차 생략.


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	c.apply_condition("holy_nimbus", 100, c)
	return {"ok": true}
