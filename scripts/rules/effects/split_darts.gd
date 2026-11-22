extends "res://scripts/rules/effect_script.gd"
## Magic Missile(SRD): 자동 명중 다트 3개(슬롯 1레벨 위마다 +1), 다트마다 1d4+1 역장.
## opts.targets에 대상을 나눠 준다(같은 생물 여러 번 가능). 없으면 조준 칸의 생물에게 모두.
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Area := preload("res://scripts/rules/area.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var grid: Node = ctx["world"]["grid"]
	var darts := 3 + maxi(int(ctx["slot"]) - 1, 0)
	var targets: Array = ctx["opts"].get("targets", [])
	if targets.is_empty():
		var t: Node = grid.creature_at(ctx["aim"])
		if t == null:
			return {"ok": false, "reason": "대상이 없다"}
		targets = [t]
	for i in darts:
		var t: Node = targets[i % targets.size()]
		if t.dead:
			continue
		Resolver.apply_damage(t, [{"amount": Dice.roll("1d4+1", "Magic Missile")["total"], "damage_type": "force"}],
			{"attacker": ctx["self"]})
	return {"ok": true, "darts": darts}
