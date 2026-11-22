extends "res://scripts/rules/effect_script.gd"
## 전술적 판단(전사 2레벨, SRD): 능력 판정 실패 → 재기의 숨결 1회로 +1d10. 그래도 실패면 소모하지 않는다.
## 숨은 판정은 자동, 보이는 판정은 6단계 굴림 창에서 선택지로(룰북 6단계).


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var res: Dictionary = ctx["res"]
	if res.get("success", true) or res.get("auto", false) or c.resource("second_wind") <= 0:
		return {"ok": false}
	if res["natural"] == 1:
		return {"ok": false}  # 자연 1은 자동 실패라 더해도 바뀌지 않는다
	if res["total"] + 10 < res["dc"]:
		return {"ok": false}  # 최대로 굴려도 안 되면 쓰지 않는다
	var roll: int = Dice.roll("1d10", "전술적 판단")["total"]
	if res["total"] + roll >= res["dc"]:
		c.spend_resource("second_wind")
		res["total"] += roll
		res["success"] = true
		Dice.log_text("%s 전술적 판단 +%d → 성공" % [c.label(), roll])
	return {"ok": true}
