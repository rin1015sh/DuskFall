extends "res://scripts/rules/effect_script.gd"
## 주술검사의 저주(주술검사 1레벨, BG3): 보너스 행동, 짧은 휴식 1회, 12칸 안 적 — 내 피해 굴림 + 숙련, 치명타 범위 −1.
## 저주받은 대상이 죽으면 워락 레벨 + 매력 회복(Resolver — 상태 hexblades_curse).
func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	if not (t is Node) or t.dead or not t.is_hostile_to(c) or ctx["world"]["grid"].distance_between(c, t) > 12:
		return {"ok": false, "reason": "12칸 안 적"}
	t.apply_condition("hexblades_curse", -1, c)
	return {"ok": true}
