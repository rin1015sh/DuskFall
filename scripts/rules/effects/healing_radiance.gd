extends "res://scripts/rules/effect_script.gd"
## 치유의 광휘(고대인의 맹세, BG3): 보너스 행동 + 신성 변환, 나와 6칸 안 아군 숙련 + 팔라딘 레벨 + 매력 회복, 다음 턴에 한 번 더(상태 healing_radiance).
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var grid: Node = ctx["world"]["grid"]
	var n: int = maxi(1, c.proficiency_bonus + c.feature_level("lay_on_hands") + c.ability_mod("cha"))
	for o: Node in grid.creatures():
		if not o.dead and not o.is_hostile_to(c) and grid.distance_between(c, o) <= 6:
			Resolver.heal(o, n, c)
			o.apply_condition("healing_radiance", 2, c, {"heal": n})
	return {"ok": true, "amount": n}
