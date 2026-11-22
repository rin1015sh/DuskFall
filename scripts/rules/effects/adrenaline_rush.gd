extends "res://scripts/rules/effect_script.gd"
## 아드레날린(오크, SRD): 보너스 행동으로 질주 + 임시 HP(숙련 보너스). 숙련 보너스 횟수, 짧은·긴 휴식에 회복.

const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	c.turn["movement"] = int(c.turn.get("movement", 0)) + c.speed()
	Resolver.grant_temp_hp(c, c.proficiency_bonus)
	return {"ok": true}
