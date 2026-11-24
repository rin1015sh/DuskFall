extends "res://scripts/rules/effect_script.gd"
## 무덤의 힘(그림자 마법 1레벨, BG3): 0 HP가 되면 쓰러지는 대신 HP 1(긴 휴식 1회, 즉사 피해 제외).
func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var info: Dictionary = ctx.get("res", {})
	if info.get("prevented", false) or c.dead or not c.resources.has("strength_of_the_grave") or c.resource("strength_of_the_grave") <= 0:
		return {"ok": false}
	c.spend_resource("strength_of_the_grave")
	info["prevented"] = true
	c.hp = 1
	Dice.log_text("%s 무덤의 힘: HP 1로 버틴다" % c.label())
	return {"ok": true}
