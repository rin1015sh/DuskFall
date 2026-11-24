extends "res://scripts/rules/effect_script.gd"
## 바드의 영감(바드 1레벨, SRD): 보너스 행동, 12칸 안 다른 생물에게 영감 주사위(1~4레벨 d6, 5레벨 d8 — 기능 dice_by_level).
## 한 번에 하나. 받은 생물이 d20 시험에 실패하면 자동으로 굴려 더한다(BG3식 — resolver.inspire). 1시간 → 긴 휴식까지.

const RANGE := 12


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	if not (t is Node) or t == c or t.dead or t.is_hostile_to(c):
		return {"ok": false, "reason": "다른 아군을 골라야 한다"}
	var w: Dictionary = ctx.get("world", {})
	if w.has("grid") and w["grid"].creatures().has(c) and w["grid"].distance_between(c, t) > RANGE:
		return {"ok": false, "reason": "12칸 안"}
	if t.has_condition("bardic_inspiration"):
		return {"ok": false, "reason": "이미 영감을 받았다"}
	var die: String = load("res://scripts/rules/reaction_queue.gd")._feature_die(c, ctx.get("feature", {}))
	t.apply_condition("bardic_inspiration", -1, c, {"die": die, "combat": c.has_cap("combat_inspiration")})  # 전투 영감(용맹 학파): AC에도
	Dice.log_text("%s: %s에게 바드의 영감(%s)" % [c.label(), t.label(), die])
	return {"ok": true, "die": die}
