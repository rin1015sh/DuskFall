extends "res://scripts/rules/effect_script.gd"
## Beacon of Hope(SRD): 사거리 안 원하는 만큼의 생물. 지혜 내성·사망 내성 유리, 회복은 최대값.
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Area := preload("res://scripts/rules/area.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var grid: Node = ctx["world"]["grid"]
	var targets: Array = ctx["opts"].get("targets", [])
	if targets.is_empty():
		targets = grid.creatures().filter(func(o: Node) -> bool:
			return not o.dead and o.team == c.team and grid.distance_between(c, o) <= 6)
	var id: int = ctx["instance"]["id"]
	for t: Node in targets:
		for e: Dictionary in [{"type": "advantage", "roll": "save", "side": "self", "value": "advantage", "ability": ["wis"]},
				{"type": "advantage", "roll": "death_save", "side": "self", "value": "advantage"},
				{"type": "modify", "stat": "max_healing"}]:
			t.extra_modifiers.append({"effect": e, "source": "beacon_of_hope", "instance": id, "turns_left": -1})
		ctx["instance"]["targets"].append(t)
	return {"ok": true, "targets": targets.size()}
