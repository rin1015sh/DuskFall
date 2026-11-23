extends "res://scripts/rules/effect_script.gd"
## 이중 존재(기만 영역 2레벨, BG3): 행동 + 신성 변환. 6칸(9m) 안 칸에 환영 — 그 칸 2칸(3m) 안 적을 노린 나·아군의 공격 유리(10턴).
## 환영 자체(움직이기·주문 중계)는 단순화: 그 순간 둘레 적에게 '환영에 홀림' 상태(받는 공격 유리)를 건다.
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
	var n := 0
	for o: Node in grid.creatures():
		if not o.dead and c.is_hostile_to(o) and grid.distance(grid.cell_of(o), cell) <= 2:
			o.apply_condition("duplicity_distracted", 10, c)
			n += 1
	return {"ok": true, "affected": n}
