extends "res://scripts/rules/effect_script.gd"
## 교묘한 회피(로그 5레벨, SRD): 볼 수 있는 공격자에게 맞으면 반응으로 그 공격 피해 절반(내림).
## 반응 설정 대상(룰북 6단계). 자동이면 늘 쓴다.

const Features := preload("res://scripts/rules/features.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var res: Dictionary = ctx["res"]
	if res.get("target") != c or not res.get("hit", false) or res.get("preview", false):
		return {"ok": false}
	if c.has_condition("blinded"):
		return {"ok": false}
	var used := Features.offer_reaction(c, "uncanny_dodge", {"attack": res}, func() -> void:
		c.turn["reaction"] = int(c.turn.get("reaction", 1)) - 1
		res["damage_multiplier"] = float(res.get("damage_multiplier", 1.0)) * 0.5
		Dice.log_text("%s 교묘한 회피: 피해 절반" % c.label()))
	return {"ok": used}
