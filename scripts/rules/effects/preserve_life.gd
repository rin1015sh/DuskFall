extends "res://scripts/rules/effect_script.gd"
## 생명 보존(생명 영역 2레벨, BG3): 행동 + 신성 변환. 6칸(9m) 안 아군 각자 클레릭 레벨 × 3 회복(최대 HP 절반까지 — 그보다 많으면 안 채운다).

const Resolver := preload("res://scripts/rules/resolver.gd")
const RANGE := 6


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var w: Dictionary = ctx.get("world", {})
	if not w.has("grid"):
		return {"ok": false, "reason": "격자가 없다"}
	var grid: Node = w["grid"]
	var amount: int = c.feature_level("preserve_life") * 3
	var total := 0
	for o: Node in grid.creatures():
		if o.dead or o.is_hostile_to(c) or o.team != c.team or grid.distance_between(c, o) > RANGE:
			continue
		var give := mini(amount, maxi(0, o.hp_max / 2 - o.hp))
		if give > 0:
			total += Resolver.heal(o, give, c)
	if total == 0:
		return {"ok": false, "reason": "회복할 아군이 없다(최대 HP 절반 아래만)"}
	return {"ok": true, "healed": total}
