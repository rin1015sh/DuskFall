extends "res://scripts/rules/effect_script.gd"
## 그림자 걸음(그림자 6레벨, BG3): 보너스 행동, 밝지 않은 칸에서 12칸(18m) 안 밝지 않은 빈 칸으로 순간 이동, 1턴 동안 다음 근접 공격 유리.
func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	var grid: Node = ctx["world"]["grid"]
	if not (t is Vector2i):
		return {"ok": false, "reason": "칸을 골라야 한다"}
	var me: Vector2i = grid.cell_of(c)
	if grid.light_at(me) == grid.Light.BRIGHT or grid.light_at(t) == grid.Light.BRIGHT:
		return {"ok": false, "reason": "그림자에서 그림자로만"}
	if grid.distance(me, t) > 12 or grid.creature_at(t) != null or grid.blocks_movement(t):
		return {"ok": false, "reason": "12칸 안 빈 칸"}
	grid.move_creature(c, t)
	c.apply_condition("shadow_stepped", 1, c)
	return {"ok": true}
