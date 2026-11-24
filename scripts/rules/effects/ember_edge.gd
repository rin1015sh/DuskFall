extends "res://scripts/rules/effects/blade_cantrip.gd"
## 잉걸 칼날(자체 이름, BG3 수치): 근접 무기 공격 + 명중 시 불꽃이 대상 옆 2칸 안 다른 적 하나에게 튄다 — 시전 능력 수정치 화염.
## 5레벨: 대상 +1d8 화염, 튄 불꽃 1d8 + 수정치. 10레벨: 2d8, 2d8 + 수정치.
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")


func rider(ctx: Dictionary, c: Node, t: Node) -> void:
	var n := tier(c)
	if n > 0:
		Resolver.apply_damage(t, [{"amount": Dice.roll("%dd8" % n, "잉걸 칼날")["total"], "damage_type": "fire"}], {"attacker": c})
	var g := U.grid(ctx)
	var best: Node = null
	for o: Node in g.creatures():
		if o == t or o == c or o.dead or not o.is_hostile_to(c) or g.distance_between(t, o) > 2:
			continue
		if best == null or g.distance_between(t, o) < g.distance_between(t, best):
			best = o
	if best != null:
		var amount: int = maxi(0, Spellcasting.spell_mod(c)) + (Dice.roll("%dd8" % n, "잉걸 칼날 불꽃")["total"] if n > 0 else 0)
		Resolver.apply_damage(best, [{"amount": amount, "damage_type": "fire"}], {"attacker": c})
