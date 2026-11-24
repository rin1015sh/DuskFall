extends "res://scripts/rules/effect_script.gd"
## 몸의 완전함(열린 손 6레벨, BG3): 행동, 긴 휴식 1회. HP 몽크 레벨 × 3 회복, 기 최대치 절반(내림)회복,
## 3턴 동안 '완전함'(턴 시작마다 기 1 회복 + 보너스 행동 1 더 — 상태 wholeness).
func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var got: int = load("res://scripts/rules/resolver.gd").heal(c, 3 * c.feature_level("martial_arts"), c)
	if c.resources.has("focus"):
		var mx := int(c.resources["focus"]["max"])
		c.resources["focus"]["current"] = mini(mx, c.resource("focus") + mx / 2)
	c.apply_condition("wholeness", 3, c)
	return {"ok": true, "healed": got}
