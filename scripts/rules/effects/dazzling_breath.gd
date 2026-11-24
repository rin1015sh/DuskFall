extends "res://scripts/rules/effect_script.gd"
## 눈부신 숨결(별 용 형상): 보너스 행동, 앞쪽 3칸 원뿔 적 민첩 내성 — 광휘 2d6(5레벨 3d6, 10레벨 4d6) + 지혜, 성공 절반.
const Resolver := preload("res://scripts/rules/resolver.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var grid: Node = ctx["world"]["grid"]
	if not c.has_condition("starry_dragon"):
		return {"ok": false, "reason": "용 형상일 때만"}
	var cell: Variant = ctx.get("target")
	if cell is Node:
		cell = grid.cell_of(cell)
	if not (cell is Vector2i):
		return {"ok": false, "reason": "방향(칸)을 골라야 한다"}
	var lv: int = c.feature_level("starry_form")
	var n := 4 if lv >= 10 else (3 if lv >= 5 else 2)
	var me: Vector2i = grid.cell_of(c)
	var dir := Vector2i(signi(cell.x - me.x), signi(cell.y - me.y))
	var targets: Array = grid.creatures().filter(func(o: Node) -> bool:
		if o.dead or not c.is_hostile_to(o) or grid.distance_between(c, o) > 3:
			return false
		var v: Vector2i = grid.cell_of(o) - me
		return v.x * dir.x + v.y * dir.y > 0)
	var dice := "%dd6%+d" % [n, c.ability_mod("wis")]
	Resolver.save_effect(targets, {"ability": "dex", "dc": Spellcasting.spell_dc(c)}, [{"type": "damage", "dice": dice, "damage_type": "radiant"}],
		[{"type": "damage", "dice": dice, "damage_type": "radiant", "scale": 0.5}], {"source": c, "magic": true})
	return {"ok": true, "targets": targets.size()}
