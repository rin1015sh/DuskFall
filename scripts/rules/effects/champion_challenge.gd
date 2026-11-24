extends "res://scripts/rules/effect_script.gd"
## 투사의 도전(왕관의 맹세, BG3): 보너스 행동 + 신성 변환, 6칸(9m) 안 적 지혜 내성 실패 시 10턴 — 나 말고 다른 대상 공격 불리.
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var grid: Node = ctx["world"]["grid"]
	var dc: int = 8 + c.proficiency_bonus + c.ability_mod("cha")
	var n := 0
	for o: Node in grid.creatures():
		if not o.dead and o.is_hostile_to(c) and grid.distance_between(c, o) <= 6:
			if not Resolver.saving_throw(o, "wis", dc, {"source": c})["success"]:
				o.apply_condition("champion_challenged", 10, c)
				n += 1
	return {"ok": true, "targets": n}
