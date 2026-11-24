extends "res://scripts/rules/effect_script.gd"
## 영감의 망토(매혹 학파 3레벨, BG3): 보너스 행동 + 바드의 영감. 6칸 안 아군 2명(6레벨 3, 10레벨 4)(가까운 순, 나 포함)에게
## 임시 HP 5(6레벨 8, 10레벨 11)와 '영감의 망토'(근접 공격으로 맞힌 생물은 1턴 매혹, 긴 휴식까지).
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var grid: Node = ctx["world"]["grid"]
	var lv: int = c.feature_level("mantle_of_inspiration")
	var n := 4 if lv >= 10 else (3 if lv >= 6 else 2)
	var hp := 11 if lv >= 10 else (8 if lv >= 6 else 5)
	var allies: Array = grid.creatures().filter(func(o: Node) -> bool:
		return not o.dead and not o.is_hostile_to(c) and grid.distance_between(c, o) <= 6)
	allies.sort_custom(func(a: Node, b: Node) -> bool: return grid.distance_between(c, a) < grid.distance_between(c, b))
	for o: Node in allies.slice(0, n):
		Resolver.grant_temp_hp(o, hp)
		o.apply_condition("mantle_of_inspiration", -1, c)
	return {"ok": true, "targets": mini(n, allies.size())}
