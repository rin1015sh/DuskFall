extends "res://scripts/rules/effect_script.gd"
## 퍼지는 포자(포자 회합 10레벨, BG3): 보너스 행동, 공생체 중. 6칸 안 칸 둘레 1칸의 적 건강 내성 — 실패 사령 2d8.
## (BG3는 남는 포자 구름 — 지금은 한 번 터지는 것으로 단순화)
const Resolver := preload("res://scripts/rules/resolver.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var grid: Node = ctx["world"]["grid"]
	if not c.has_condition("symbiotic_entity"):
		return {"ok": false, "reason": "공생체일 때만"}
	var cell: Variant = ctx.get("target")
	if cell is Node:
		cell = grid.cell_of(cell)
	if not (cell is Vector2i) or grid.distance(grid.cell_of(c), cell) > 6:
		return {"ok": false, "reason": "6칸 안 칸을 골라야 한다"}
	var targets: Array = grid.creatures().filter(func(o: Node) -> bool:
		return not o.dead and c.is_hostile_to(o) and grid.distance(grid.cell_of(o), cell) <= 1)
	Resolver.save_effect(targets, {"ability": "con", "dc": Spellcasting.spell_dc(c)}, [{"type": "damage", "dice": "2d8", "damage_type": "necrotic"}], [],
		{"source": c, "magic": true})
	return {"ok": true}
