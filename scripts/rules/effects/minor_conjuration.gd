extends "res://scripts/rules/effect_script.gd"
## 하급 소환: 물 만들기(소환학파 2레벨, BG3): 행동, 6칸 안 칸 둘레 3칸에 비 — 불을 끄고 물 표면·젖음. 짧은 휴식 1회.
const Area := preload("res://scripts/rules/area.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var w: Dictionary = ctx["world"]
	var grid: Node = w["grid"]
	var cell: Variant = ctx.get("target")
	if cell is Node:
		cell = grid.cell_of(cell)
	if not (cell is Vector2i) or grid.distance(grid.cell_of(c), cell) > 6:
		return {"ok": false, "reason": "6칸 안 칸을 골라야 한다"}
	var cells := Area.circle(grid, cell, 3)
	if w.get("surfaces") != null:
		w["surfaces"].apply_water(cells)
	for o: Node in Area.creatures_in(grid, cells):
		o.apply_condition("wet", 0, c)
	return {"ok": true}
