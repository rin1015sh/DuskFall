extends "res://scripts/rules/effect_script.gd"
## 그림자 망토(그림자 5레벨, BG3): 행동, 가려진(밝지 않은) 칸에 있으면 10턴 투명(공격·주문으로 풀림, 밝은 칸에 들어가도 — 생략).
func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var grid: Node = ctx["world"]["grid"]
	if grid.light_at(grid.cell_of(c)) == grid.Light.BRIGHT:
		return {"ok": false, "reason": "가려진(어둑하거나 어두운) 곳에서만"}
	c.apply_condition("invisible", 10, "shadow_cloak", {"ends_on_attack": true})
	return {"ok": true}
