extends "res://scripts/rules/effect_script.gd"
## 선동의 울부짖음(늑대의 심장, BG3): 행동, 6칸(9m) 안 아군(나 빼고)이 다음 턴에 2칸(3m) 더 이동(상태 incited).
func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var grid: Node = ctx["world"]["grid"]
	var n := 0
	for o: Node in grid.creatures():
		if o != c and not o.dead and not o.is_hostile_to(c) and grid.distance_between(c, o) <= 6:
			o.apply_condition("incited", 0, c)
			n += 1
	return {"ok": true, "targets": n}
