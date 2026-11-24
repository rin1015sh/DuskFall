extends "res://scripts/rules/effect_script.gd"
## 용의 숨결(드래곤본, BG3): 행동, 짧은 휴식 1회. 혈통 기능 값 shape(line 6칸 / cone 3칸)·damage_type·save(민첩, 독·냉기는 건강).
## 2d6(5레벨 3d6, 11레벨 4d6 — 캐릭터 레벨), DC 8 + 건강 + 숙련, 성공 절반.
const Area := preload("res://scripts/rules/area.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var f: Dictionary = ctx.get("feature", {})
	var t: Variant = ctx.get("target")
	var grid: Node = ctx["world"]["grid"]
	var me: Vector2i = grid.cell_of(c)
	var aim: Vector2i = t if t is Vector2i else (grid.cell_of(t) if t is Node else me)
	if aim == me:
		return {"ok": false, "reason": "방향을 골라야 한다"}
	var cells: Array[Vector2i] = Area.line(grid, me, aim, 6) if str(f.get("shape", "line")) == "line" \
		else Area.cone(grid, me, Vector2i(signi(aim.x - me.x), signi(aim.y - me.y)), 3)
	var dice := "4d6" if c.level >= 11 else ("3d6" if c.level >= 5 else "2d6")
	var n: int = Dice.roll(dice, "용의 숨결")["total"]
	var dc: int = 8 + c.ability_mod("con") + c.proficiency_bonus
	var hit := 0
	for o: Node in Area.creatures_in(grid, cells):
		if o == c or o.dead:
			continue
		var ok: bool = Resolver.saving_throw(o, str(f.get("save", "dex")), dc, {"source": c})["success"]
		Resolver.apply_damage(o, [{"amount": n / 2 if ok else n, "damage_type": str(f.get("damage_type", "fire"))}], {"attacker": c})
		hit += 1
	if world_surfaces(ctx) != null:
		ctx["world"]["surfaces"].tile_damage(cells, str(f.get("damage_type", "fire")), n, c)
	return {"ok": true, "targets": hit}


func world_surfaces(ctx: Dictionary) -> Variant:
	return ctx["world"].get("surfaces")
