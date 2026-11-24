extends "res://scripts/rules/effect_script.gd"
## 전세 역전(왕관의 맹세, BG3): 보너스 행동 + 신성 변환, 6칸 안 적 아닌 생물 1d6 + 팔라딘 레벨 + 매력 회복(한 번 굴려 모두).
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var grid: Node = ctx["world"]["grid"]
	var n: int = maxi(1, Dice.roll("1d6", "전세 역전")["total"] + c.feature_level("lay_on_hands") + c.ability_mod("cha"))
	for o: Node in grid.creatures():
		if not o.dead and not o.is_hostile_to(c) and grid.distance_between(c, o) <= 6:
			Resolver.heal(o, n, c)
	return {"ok": true, "amount": n}
