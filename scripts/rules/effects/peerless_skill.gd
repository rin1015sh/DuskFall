extends "res://scripts/rules/effect_script.gd"
## 비할 데 없는 기술(지식 학파 14레벨, SRD): 능력 판정·공격 굴림에 실패하면 바드의 영감 1회를 써서 주사위를 더한다 — 그래도 실패면 쓰지 않는다.
## BG3식 자동: 최대로 굴려 성공할 수 있을 때만(훅 on_check_failed·on_attack_missed).


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var res: Dictionary = ctx["res"]
	if c.resource("bardic_inspiration") <= 0 or res.get("auto", false):
		return {"ok": false}
	var is_attack := res.has("ac")
	if is_attack and (res.get("hit", true) or res.get("preview", false)):
		return {"ok": false}
	if not is_attack and (res.get("success", true) or int(res.get("natural", 0)) == 1):
		return {"ok": false}
	var need: int = (int(res["ac"]) + int(res.get("ac_bonus", 0))) if is_attack else int(res["dc"])
	var die: String = _die(c)
	var top := int(die.get_slice("d", 1))
	if int(res["total"]) + top < need:
		return {"ok": false}
	var roll: int = Dice.roll(die, "비할 데 없는 기술")["total"]
	if int(res["total"]) + roll < need:
		return {"ok": true}
	c.spend_resource("bardic_inspiration")
	res["total"] = int(res["total"]) + roll
	if not is_attack:
		res["success"] = true
	Dice.log_text("%s 비할 데 없는 기술 +%d" % [c.label(), roll])
	return {"ok": true}


func _die(c: Node) -> String:
	var table: Dictionary = c.feature_data.get("bardic_inspiration", {}).get("dice_by_level", {"1": "1d6"})
	var best := "1d6"
	var best_lv := 0
	for k: String in table:
		if c.feature_level("bardic_inspiration") >= int(k) and int(k) >= best_lv:
			best_lv = int(k)
			best = str(table[k])
	return best
