extends "res://scripts/rules/effect_script.gd"
## 운명 개선(서사 은혜 — 운명의 은혜): d20 시험에 2d4를 더하거나 뺀다, 이니셔티브·휴식마다 1회.
## 1차: 자신의 실패한 내성·능력 판정·공격에 더하기만(2d4로 성공할 수 있을 때 자동). 남·빼기는 생략. 사용 표시 meta fate_used(이니셔티브 때 초기화).


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var res: Dictionary = ctx["res"]
	if c.has_meta("fate_used") or res.get("auto", false) or res.get("preview", false):
		return {"ok": false}
	var is_attack := res.has("ac")
	if is_attack and (res.get("hit", true) or res.get("attacker") != c):
		return {"ok": false}
	if not is_attack and res.get("success", true):
		return {"ok": false}
	var need: int = (int(res["ac"]) + int(res.get("ac_bonus", 0))) if is_attack else int(res["dc"])
	if int(res["total"]) + 8 < need:
		return {"ok": false}
	c.set_meta("fate_used", true)
	var n: int = Dice.roll("2d4", "운명 개선")["total"]
	res["total"] = int(res["total"]) + n
	if not is_attack:
		res["success"] = res["total"] >= need
	return {"ok": true}
