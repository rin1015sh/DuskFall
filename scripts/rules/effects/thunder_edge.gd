extends "res://scripts/rules/effects/blade_cantrip.gd"
## 우레 칼날(자체 이름, BG3 수치): 근접 무기 공격 + 명중 시 울림 1턴 — 대상이 스스로 움직이면 1d8 천둥(5레벨 2d8, 10레벨 3d8).
## 5레벨부터 명중 때 바로 1d8(10레벨 2d8) 천둥도 더한다.


func rider(ctx: Dictionary, c: Node, t: Node) -> void:
	var n := tier(c)
	if n > 0:
		Resolver.apply_damage(t, [{"amount": Dice.roll("%dd8" % n, "우레 칼날")["total"], "damage_type": "thunder"}], {"attacker": c})
	if not t.dead:
		U.add_condition(ctx, t, "thunder_echo", 1, {"move_dice": "%dd8" % (n + 1)})
