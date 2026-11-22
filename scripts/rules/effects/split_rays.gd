extends "res://scripts/rules/effect_script.gd"
## Scorching Ray(SRD): 광선 3개(슬롯 2레벨 위마다 +1), 광선마다 원거리 주문 공격, 명중 2d6 화염.
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Area := preload("res://scripts/rules/area.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var grid: Node = ctx["world"]["grid"]
	var rays := 3 + maxi(int(ctx["slot"]) - 2, 0)
	var targets: Array = ctx["opts"].get("targets", [])
	if targets.is_empty():
		var t: Node = grid.creature_at(ctx["aim"])
		if t == null:
			return {"ok": false, "reason": "대상이 없다"}
		targets = [t]
	var c: Node = ctx["self"]
	var hits := 0
	for i in rays:
		var t: Node = targets[i % targets.size()]
		if t.dead:
			continue
		var atk := {"name": "Scorching Ray", "bonus": Spellcasting.spell_attack_bonus(c), "kind": "ranged", "weapon": false,
			"damage": [{"dice": "2d6", "damage_type": "fire"}]}
		if Resolver.attack(c, t, atk, grid.attack_context(c, t))["hit"]:
			hits += 1
	return {"ok": true, "hits": hits}
