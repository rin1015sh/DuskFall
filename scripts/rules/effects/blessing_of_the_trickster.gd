extends "res://scripts/rules/effect_script.gd"
## 사기꾼의 축복(기만 영역 1레벨, BG3): 행동. 곁(1칸)의 다른 생물이 긴 휴식까지 은신 판정 유리.
func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	var grid: Node = ctx["world"]["grid"]
	if not (t is Node) or t == c or t.dead or grid.distance_between(c, t) > 1:
		return {"ok": false, "reason": "곁의 다른 생물을 골라야 한다"}
	t.apply_condition("tricksters_blessing", -1, c)
	return {"ok": true}
