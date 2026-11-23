extends "res://scripts/rules/effect_script.gd"
## 땅의 도움(대지 회합 3레벨, SRD): 행동, 야생 변신 1회. 12칸 안 한 점의 반지름 2칸 구 — 안의 적은 건강 내성(주문 DC)
## 실패 2d6 사령·성공 절반, 안의 아군 하나(HP 비율이 가장 낮은)는 2d6 회복.

const Resolver := preload("res://scripts/rules/resolver.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Area := preload("res://scripts/rules/area.gd")
const RANGE := 12
const RADIUS := 2


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var w: Dictionary = ctx.get("world", {})
	if not w.has("grid"):
		return {"ok": false, "reason": "격자가 없다"}
	var grid: Node = w["grid"]
	var aim: Variant = ctx.get("opts", {}).get("cell", ctx.get("target"))
	var cell: Vector2i = aim if aim is Vector2i else (grid.cell_of(aim) if aim is Node else grid.cell_of(c))
	if grid.distance(grid.cell_of(c), cell) > RANGE:
		return {"ok": false, "reason": "12칸 안"}
	var inside := Area.creatures_in(grid, Area.circle(grid, cell, RADIUS))
	var foes: Array = inside.filter(func(o: Node) -> bool: return not o.dead and o.is_hostile_to(c))
	var friends: Array = inside.filter(func(o: Node) -> bool: return not o.dead and not o.is_hostile_to(c))
	if not foes.is_empty():
		Resolver.save_effect(foes, {"ability": "con", "dc": Spellcasting.spell_dc(c)},
			[{"type": "damage", "dice": "2d6", "damage_type": "necrotic"}],
			[{"type": "damage", "dice": "2d6", "damage_type": "necrotic", "scale": 0.5}], {"source": c, "attacker": c})
	if not friends.is_empty():
		friends.sort_custom(func(a: Node, b: Node) -> bool: return float(a.hp) / a.hp_max < float(b.hp) / b.hp_max)
		Resolver.heal(friends[0], Dice.roll("2d6", "땅의 도움")["total"], c)
	return {"ok": true, "foes": foes.size()}
