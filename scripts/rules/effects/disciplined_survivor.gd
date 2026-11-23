extends "res://scripts/rules/effect_script.gd"
## 수련된 생존자(몽크 14레벨, SRD): 내성에 실패하면 기 1로 다시 굴린다(새 굴림을 쓴다). BG3식 자동: 다시 굴려 성공할 수 있을 때만.


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var res: Dictionary = ctx["res"]
	if res.get("success", true) or res.get("auto", false) or c.resource("focus") <= 0:
		return {"ok": false}
	if 20 + int(res["bonus"]) < int(res["dc"]):
		return {"ok": false}
	c.spend_resource("focus")
	var d: Dictionary = Dice.d20(int(res.get("mode", 0)), "%s 수련된 생존자" % c.label())
	res["natural"] = d["natural"]
	res["total"] = int(d["natural"]) + int(res["bonus"])
	res["success"] = res["total"] >= int(res["dc"])
	return {"ok": true}
