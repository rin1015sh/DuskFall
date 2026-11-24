extends "res://scripts/rules/effect_script.gd"
## 선한 자리바꿈(소환학파 6레벨, BG3): 행동, 6칸 안 빈 칸으로 순간 이동하거나 아군과 자리를 바꾼다. 긴 휴식 1회(소환학파 주문을 쓰면 되찾음).
func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var grid: Node = ctx["world"]["grid"]
	var cell: Variant = ctx.get("target")
	if cell is Node:
		cell = grid.cell_of(cell)
	if not (cell is Vector2i) or grid.distance(grid.cell_of(c), cell) > 6:
		return {"ok": false, "reason": "6칸 안 칸을 골라야 한다"}
	var other: Node = grid.creature_at(cell)
	var from: Vector2i = grid.cell_of(c)
	if other != null and other != c:
		if c.is_hostile_to(other):
			return {"ok": false, "reason": "아군과만 자리를 바꾼다"}
		var osz: int = grid.size_of(other)
		grid.remove(other)
		grid.move_creature(c, cell)
		grid.place(other, from, osz)
	elif grid.blocks_movement(cell):
		return {"ok": false, "reason": "갈 수 없는 칸"}
	else:
		grid.move_creature(c, cell)
	return {"ok": true}
