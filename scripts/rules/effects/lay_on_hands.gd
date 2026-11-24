extends "res://scripts/rules/effect_script.gd"
## 신성한 손길(팔라딘 1레벨, BG3): 행동 + 신성한 손길 1회(1레벨 3회, 4레벨 4회, 10레벨 5회 — 긴 휴식). 근접 생물(자신 포함) —
## 중독이면 해독, 아니면 팔라딘 레벨 × 2 회복(BG3식 자동 선택 — 중독이면서 다쳤으면 둘 다).
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	if not (t is Node):
		t = c
	if t.dead:
		return {"ok": false, "reason": "대상이 없다"}
	if t != c and ctx.get("world", {}).has("grid") and ctx["world"]["grid"].distance_between(c, t) > 1:
		return {"ok": false, "reason": "옆의 생물만"}
	var cured := false
	if t.has_condition("poisoned"):
		t.remove_condition("poisoned")
		cured = true
	if t.hp >= t.hp_max and not cured:
		return {"ok": false, "reason": "회복할 것이 없다"}
	var n: int = Resolver.heal(t, 2 * c.feature_level("lay_on_hands"), c)
	Dice.log_text("%s: 신성한 손길 → %s %d 회복%s" % [c.label(), t.label(), n, ", 해독" if cured else ""])
	return {"ok": true, "healed": n, "cured": cured}
