extends "res://scripts/rules/effect_script.gd"
## 칼날노래(칼날노래 2레벨, BG3): 보너스 행동, 10턴 — AC·건강 내성 +2(9레벨 +4), 속도 +2칸(3m), 곡예 유리. 중갑·중형 갑옷·방패면 못 쓴다.
func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var armor := str(c.get_meta("armor", ""))
	if bool(c.get_meta("shield", false)) or (armor != "" and str(RulesDB.get_entry("armor", armor).get("category", "")) in ["medium", "heavy"]):
		return {"ok": false, "reason": "중형·중갑 갑옷이나 방패를 들면 쓸 수 없다"}
	c.apply_condition("bladesong_greater" if c.feature_level("bladesong") >= 9 else "bladesong", 10, c)
	return {"ok": true}
