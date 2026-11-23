extends "res://scripts/rules/effect_script.gd"
## 마법적 기지(워락 2레벨, SRD): 1분 의식(탐험 중) — 계약 마법 슬롯을 최대치 절반(올림)까지 되찾는다. 긴 휴식마다 1회.


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var regained := 0
	for id: String in c.resources:
		if not id.begins_with("spell_slot_"):
			continue
		var r: Dictionary = c.resources[id]
		var mx := int(r["max"])
		if mx <= 0:
			continue
		var n := mini(mx - int(r["current"]), (mx + 1) / 2)
		r["current"] = int(r["current"]) + n
		regained += n
	if regained <= 0:
		return {"ok": false, "reason": "되찾을 슬롯이 없다"}
	Dice.log_text("%s: 마법적 기지 — 슬롯 %d개" % [c.label(), regained])
	return {"ok": true, "regained": regained}
