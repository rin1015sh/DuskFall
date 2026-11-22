extends "res://scripts/rules/effect_script.gd"
## Blink(3레벨, SRD): 1분 동안 자기 턴이 끝날 때마다 1d6, 4~6이면 에테르계로(공격·범위 대상 아님), 다음 자기 턴 시작에 돌아온다.

const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var inst: Dictionary = ctx["instance"]
	inst["auras"].append({"on_turn_end": func(_w: Dictionary, who: Node) -> void:
		if who != c or c.dead:
			return
		if Dice.roll("1d6", "Blink")["total"] >= 4:
			c.apply_condition("ethereal", -1, c, {"instance": inst["id"]})
			Dice.log_text("%s가 에테르계로 사라졌다" % c.label()),
		"on_turn_start": func(_w: Dictionary, who: Node) -> void:
			if who == c:
				c.remove_condition("ethereal")})
	if not c in inst["targets"]:
		inst["targets"].append(c)
	return {"ok": true}
