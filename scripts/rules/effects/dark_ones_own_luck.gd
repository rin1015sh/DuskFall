extends "res://scripts/rules/effect_script.gd"
## 어둠의 자의 행운(악마 후원자 6레벨, SRD): 능력 판정·내성 굴림에 d10을 더한다. 매력 수정치(최소 1)회, 긴 휴식.
## BG3식 자동: 실패했고 d10으로 성공할 수 있을 때만 굴린다(훅 on_check_failed·on_save_failed). 그래도 실패하면 소모하지 않는다(전술적 판단과 같은 방식).


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var res: Dictionary = ctx["res"]
	var pool := str(c.feature_data.get("dark_ones_own_luck", {}).get("resource", "dark_ones_own_luck"))
	if res.get("success", true) or res.get("auto", false) or c.resource(pool) <= 0:
		return {"ok": false}
	if res.has("skill") and int(res.get("natural", 0)) == 1:
		return {"ok": false}  # 능력 판정 자연 1은 자동 실패
	if int(res["total"]) + 10 < int(res["dc"]):
		return {"ok": false}
	var roll: int = Dice.roll("1d10", "어둠의 자의 행운")["total"]
	if int(res["total"]) + roll >= int(res["dc"]):
		c.spend_resource(pool)
		res["total"] = int(res["total"]) + roll
		res["success"] = true
		Dice.log_text("%s 어둠의 자의 행운 +%d → 성공" % [c.label(), roll])
	return {"ok": true}
