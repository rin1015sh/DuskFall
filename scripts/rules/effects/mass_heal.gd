extends "res://scripts/rules/effect_script.gd"
## Mass Heal(SRD 9레벨): 12칸 안 보이는 생물에게 합계 700까지 나눠 회복하고 실명·중독을 푼다(귀먹음은 없는 상태).
## BG3식 자동 분배: 아군 중 HP 비율이 낮은 순으로 최대 HP까지.

const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var grid: Node = ctx["world"]["grid"]
	var allies: Array = grid.creatures().filter(func(o: Node) -> bool:
		return not o.dead and not o.is_hostile_to(c) and grid.distance_between(c, o) <= 12 and (o == c or grid.can_see(c, o)))
	allies.sort_custom(func(a: Node, b: Node) -> bool: return float(a.hp) / maxf(1.0, a.hp_max) < float(b.hp) / maxf(1.0, b.hp_max))
	var pool := 700
	var healed := 0
	for o: Node in allies:
		o.remove_condition("blinded")
		o.remove_condition("poisoned")
		var want: int = o.hp_max - o.hp
		if want <= 0 or pool <= 0:
			continue
		var n := mini(want, pool)
		Resolver.heal(o, n, c)
		pool -= n
		healed += 1
	return {"ok": true, "healed": healed}
