extends "res://scripts/rules/effect_script.gd"
## 전설적 저항(SRD 몬스터 특성, 하루 3회): 내성에 실패하면 성공으로 바꾼다. 특성 데이터 uses(기본 3) — 남은 횟수는 meta legendary_left.
## 1차: 실패하면 곧바로 쓴다(남아 있는 동안).


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var res: Dictionary = ctx["res"]
	if res.get("success", true):
		return {"ok": false}
	var uses := int(c.feature_data.get("legendary_resistance", {}).get("uses", 3))
	var left := int(c.get_meta("legendary_left", uses))
	if left <= 0:
		return {"ok": false}
	c.set_meta("legendary_left", left - 1)
	res["success"] = true
	res["auto"] = false
	Dice.log_text("%s 전설적 저항(남은 %d)" % [c.label(), left - 1])
	return {"ok": true}
