extends "res://scripts/rules/effect_script.gd"
## 불굴(전사 9레벨, SRD): 내성에 실패하면 다시 굴리고 전사 레벨을 더한다 — 새 굴림을 써야 한다.
## 긴 휴식마다 1회(13레벨 2회, 17레벨 3회 — 자원 indomitable). BG3식 자동: 다시 굴려 성공할 수 있을 때만 쓴다.


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var res: Dictionary = ctx["res"]
	var f: Dictionary = c.feature_data.get("indomitable", {})
	var pool := str(f.get("resource", "indomitable"))
	if res.get("success", true) or res.get("auto", false) or c.resource(pool) <= 0:
		return {"ok": false}
	var lv: int = c.feature_level("indomitable")
	var bonus: int = int(res["bonus"]) + lv
	if 20 + bonus < int(res["dc"]):
		return {"ok": false}  # 최대로 굴려도 안 되면 쓰지 않는다
	c.spend_resource(pool)
	var d: Dictionary = Dice.d20(int(res.get("mode", 0)), "%s 불굴" % c.label())
	res["natural"] = d["natural"]
	res["total"] = int(d["natural"]) + bonus
	res["success"] = res["total"] >= int(res["dc"])
	Dice.log_text("%s 불굴: %d + %d = %d → %s" % [c.label(), d["natural"], bonus, res["total"], "성공" if res["success"] else "실패"])
	return {"ok": true}
