extends "res://scripts/rules/effect_script.gd"
## 공격 쳐내기(몽크 3레벨, SRD): 타격·관통·참격이 섞인 공격에 맞으면 반응으로 그 공격 피해를 1d10 + 민첩 + 몽크 레벨만큼 줄인다.
## 반응 설정 대상. 0으로 줄였을 때 기 1로 되돌려 보내기는 1차 생략.

const Features := preload("res://scripts/rules/features.gd")
const PHYSICAL := ["bludgeoning", "piercing", "slashing"]


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var res: Dictionary = ctx["res"]
	if res.get("target") != c or not res.get("hit", false) or res.get("preview", false):
		return {"ok": false}
	var physical := false
	for d: Dictionary in res.get("attack", {}).get("damage", []):
		if str(d.get("damage_type", "")) in PHYSICAL:
			physical = true
	if not physical:
		return {"ok": false}
	var used := Features.offer_reaction(c, "deflect_attacks", {"attack": res}, func() -> void:
		c.turn["reaction"] = int(c.turn.get("reaction", 1)) - 1
		var n: int = Dice.roll("1d10", "공격 쳐내기")["total"] + c.ability_mod("dex") + c.feature_level("deflect_attacks")
		res["damage_reduction"] = int(res.get("damage_reduction", 0)) + n
		Dice.log_text("%s 공격 쳐내기: 피해 −%d" % [c.label(), n]))
	return {"ok": used}
