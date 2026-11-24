extends "res://scripts/rules/effect_script.gd"
## 적대의 맹세(복수의 맹세, BG3): 보너스 행동 + 신성 변환, 2칸(3m) 안 적 하나 — 10턴 동안 그 적을 공격할 때 유리.
## 자신에게 쓰면 모든 대상(BG3 그대로).
func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	if not (t is Node) or t.dead:
		return {"ok": false, "reason": "대상을 골라야 한다"}
	if t == c:
		c.apply_condition("vow_of_enmity_self", 10, c)
		return {"ok": true}
	if not t.is_hostile_to(c) or ctx["world"]["grid"].distance_between(c, t) > 2:
		return {"ok": false, "reason": "2칸 안 적"}
	t.apply_condition("vow_of_enmity", 10, c)
	return {"ok": true}
