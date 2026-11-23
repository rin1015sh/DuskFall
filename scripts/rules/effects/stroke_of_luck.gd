extends "res://scripts/rules/effect_script.gd"
## 행운의 일격(로그 20레벨, SRD): 실패한 d20 시험을 20으로. 짧은·긴 휴식 1회(자원 stroke_of_luck).
## BG3식 자동: 20이면 성공할 때만(공격은 자연 20 — 치명타).


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var res: Dictionary = ctx["res"]
	if c.resource("stroke_of_luck") <= 0 or res.get("auto", false) or res.get("preview", false):
		return {"ok": false}
	if res.has("ac"):
		if res.get("hit", true) or res.get("attacker") != c:
			return {"ok": false}
		res["natural"] = 20
		res["total"] = 20 + int(res["attack_bonus"])
	else:
		if res.get("success", true):
			return {"ok": false}
		var total20: int = 20 + int(res["bonus"])
		if total20 < int(res["dc"]) and not res.has("skill"):
			return {"ok": false}  # 내성: 20이어도 실패면 쓰지 않는다(능력 판정은 자연 20 자동 성공)
		res["natural"] = 20
		res["total"] = total20
		res["success"] = true
	c.spend_resource("stroke_of_luck")
	Dice.log_text("%s 행운의 일격: 20" % c.label())
	return {"ok": true}
