extends "res://scripts/rules/effect_script.gd"
## 자연의 마법사(대드루이드 20레벨, SRD): 남은 야생 변신 횟수를 한 슬롯으로(횟수당 2레벨, 최대 9레벨). 긴 휴식 1회.
## 1차: 쓴 슬롯 중 가장 높은 레벨부터 채울 수 있는 만큼 자동.


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var uses: int = c.resource("wild_shape")
	if uses <= 0:
		return {"ok": false, "reason": "야생 변신 횟수가 없다"}
	for lv in range(9, 0, -1):
		var id := "spell_slot_%d" % lv
		if not c.resources.has(id) or int(c.resources[id]["current"]) >= int(c.resources[id]["max"]):
			continue
		var need: int = int(ceil(lv / 2.0))
		if need > uses:
			continue
		c.resources["wild_shape"]["current"] = uses - need
		c.resources[id]["current"] = int(c.resources[id]["current"]) + 1
		Dice.log_text("%s 자연의 마법사: 야생 변신 %d회 → %d레벨 슬롯" % [c.label(), need, lv])
		return {"ok": true, "slot": lv}
	return {"ok": false, "reason": "채울 슬롯이 없다"}
