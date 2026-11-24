extends "res://scripts/rules/effect_script.gd"
## 급증: 순간 이동(야생 마법 급증 효과 중) — 보너스 행동, 6칸(9m) 안 보이는 빈 칸으로. 폭풍 마법 비행(tempest 기능 값)은 레벨 주문 뒤 6칸.
func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	var grid: Node = ctx["world"]["grid"]
	var f: Dictionary = ctx.get("feature", {})
	if f.get("tempest", false) and not c.turn.get("tempest_ready", false):
		return {"ok": false, "reason": "레벨 주문을 쓴 턴에만"}
	if not (t is Vector2i):
		return {"ok": false, "reason": "칸을 골라야 한다"}
	var me: Vector2i = grid.cell_of(c)
	var rng := int(f.get("range_tiles", 6))
	if f.get("shadow", false) and grid.light_at(t) == grid.Light.BRIGHT:
		return {"ok": false, "reason": "가려진(밝지 않은) 칸으로만"}
	if grid.distance(me, t) > rng or grid.creature_at(t) != null or grid.blocks_movement(t) or not grid.has_line_of_sight(me, t):
		return {"ok": false, "reason": "%d칸 안 보이는 빈 칸" % rng}
	grid.move_creature(c, t)
	c.turn["tempest_ready"] = false
	return {"ok": true}
