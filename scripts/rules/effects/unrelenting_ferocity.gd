extends "res://scripts/rules/effect_script.gd"
## 굽히지 않는 흉포함(곰의 심장, BG3): 분노 중 행동으로 1d8 + 건강 수정치 회복, 분노 한 번에 1회.
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var inst: Dictionary = c.condition_instance("raging")
	if inst.is_empty() or inst.get("params", {}).get("ferocity_used", false):
		return {"ok": false, "reason": "이번 분노에 이미 썼다"}
	if not inst.has("params"):
		inst["params"] = {}
	inst["params"]["ferocity_used"] = true
	var n: int = Dice.roll("1d8", "굽히지 않는 흉포함")["total"] + c.ability_mod("con")
	Resolver.heal(c, maxi(n, 1), c)
	return {"ok": true, "healed": n}
