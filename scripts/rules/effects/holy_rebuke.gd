extends "res://scripts/rules/effect_script.gd"
## 신성한 질책(헌신의 맹세, BG3): 행동 + 신성 변환, 12칸 안 나나 아군 2턴 — 근접 공격으로 맞힌 생물 1d4 광휘.
func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	if not (t is Node):
		t = c
	if t.dead or t.is_hostile_to(c) or (t != c and ctx["world"]["grid"].distance_between(c, t) > 12):
		return {"ok": false, "reason": "12칸 안 나나 아군"}
	t.apply_condition("holy_rebuke", 2, c)
	return {"ok": true}
