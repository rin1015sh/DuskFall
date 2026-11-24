extends "res://scripts/rules/effect_script.gd"
## 마법 인지(야생 마법 3레벨, BG3): 보너스 행동, 2칸(3m) 안 모든 생물(적 포함)이 1턴 동안 내성 +1d4. 짧은 휴식 1회.
func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var grid: Node = ctx["world"]["grid"]
	for o: Node in grid.creatures():
		if not o.dead and grid.distance_between(c, o) <= 2:
			o.apply_condition("magic_awareness", 0, c)
	return {"ok": true}
