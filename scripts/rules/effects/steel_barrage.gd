extends "res://scripts/rules/effect_script.gd"
## 강철 세례(자체 이름, BG3 수치): 원뿔 6칸(9m) 민첩 내성 — 주무기 피해 주사위 + 2d8(무기 피해 유형), 성공 절반.
const U := preload("res://scripts/rules/spell_util.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Area := preload("res://scripts/rules/area.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var w := Combat.weapon_data(c.weapon("main") if c.weapon("main") != "" else "unarmed")
	var dtype := str(w.get("damage_type", "piercing"))
	var dice := "%s+2d8" % str(w.get("damage", "1d4")) if c.weapon("main") != "" else "2d8"
	var cells := Spellcasting.area_cells(ctx["world"], c, ctx["spell"], ctx["aim"])
	var r := Resolver.save_effect(Area.creatures_in(U.grid(ctx), cells).filter(func(o: Node) -> bool: return not o.dead and o != c),
		{"ability": "dex", "dc": U.dc(ctx)}, [{"type": "damage", "dice": dice, "damage_type": dtype}],
		[{"type": "damage", "dice": dice, "damage_type": dtype, "scale": 0.5}], {"source": c})
	return {"ok": true, "results": r}
