extends "res://scripts/rules/effect_script.gd"
## Spirit Guardians(SRD): 시전자를 따라다니는 반경 3칸 발산. 적이 들어오거나 그 안에서 턴을 끝내면 지혜 내성,
## 실패 3d8 광휘(성공 절반), 한 턴에 한 번. 안의 적은 속도 절반(1차는 피해만 — 속도 절반은 이동 비용 작업에서).
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Area := preload("res://scripts/rules/area.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var inst: Dictionary = ctx["instance"]
	var spell: Dictionary = ctx["spell"]
	var dice := Spellcasting.scaled_dice(c, spell, "3d8", int(ctx["slot"]))
	var dc := Spellcasting.spell_dc(c)
	var hit_marks := {}
	var trigger := func(world: Dictionary, o: Node) -> void:
		if o.dead or o == c or not o.is_hostile_to(c) or c.dead:
			return
		var grid: Node = world["grid"]
		if grid.distance_between(c, o) > 3 and not (Area.circle(grid, grid.cell_of(c), 3).has(grid.cell_of(o))):
			return
		if not Area.circle(grid, grid.cell_of(c), 3).has(grid.cell_of(o)):
			return
		var key: String = "%d:%d" % [o.get_instance_id(), world["turns"].round_number if world.get("turns") != null else 0]
		if hit_marks.has(key):
			return
		hit_marks[key] = true
		Resolver.save_effect([o], {"ability": "wis", "dc": dc},
			[{"type": "damage", "dice": dice, "damage_type": "radiant"}],
			[{"type": "damage", "dice": dice, "damage_type": "radiant", "scale": 0.5}], {"source": c})
	inst["auras"].append({"on_enter": trigger, "on_turn_end": trigger})
	return {"ok": true}
