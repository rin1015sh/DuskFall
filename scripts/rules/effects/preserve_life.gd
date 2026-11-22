extends "res://scripts/rules/effect_script.gd"
## 생명 보존(생명 영역 3레벨, SRD): 클레릭 레벨 × 5 HP를 6칸 안 '피투성이'(HP 절반 이하) 생물에게 나눈다.
## 한 생물은 최대 HP 절반까지만. 분배는 자동: HP 비율이 낮은 쪽부터(룰북 6단계).

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
	var pool: int = c.level * 5
	var hurt: Array = grid.creatures().filter(func(o: Node) -> bool:
		return not o.dead and not o.is_hostile_to(c) and o.team == c.team and grid.distance_between(c, o) <= RANGE \
			and o.hp <= o.hp_max / 2)
	hurt.sort_custom(func(a: Node, b: Node) -> bool: return float(a.hp) / a.hp_max < float(b.hp) / b.hp_max)
	var total := 0
	for o: Node in hurt:
		var room: int = o.hp_max / 2 - o.hp
		var give := mini(room, pool)
		if give > 0:
			Resolver.heal(o, give, c)
			pool -= give
			total += give
	if total == 0:
		return {"ok": false, "reason": "피투성이 아군이 없다"}
	return {"ok": true, "healed": total}
