extends "res://scripts/rules/effect_script.gd"
## 야생 마법: 순간 이동(BG3): 효과 중 매 턴 보너스 행동, 12칸(18m) 안 보이는 빈 칸으로 순간 이동.
func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	var grid: Node = ctx["world"]["grid"]
	if not (t is Vector2i):
		return {"ok": false, "reason": "칸을 골라야 한다"}
	var me: Vector2i = grid.cell_of(c)
	if grid.distance(me, t) > 12 or grid.creature_at(t) != null or grid.blocks_movement(t) or not grid.has_line_of_sight(me, t):
		return {"ok": false, "reason": "12칸 안 보이는 빈 칸"}
	grid.move_creature(c, t)
	return {"ok": true}
