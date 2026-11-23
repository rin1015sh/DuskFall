extends "res://scripts/rules/effect_script.gd"
## 끈질긴 분노(바바리안 11레벨, SRD): 분노 중 0 HP가 되고 즉사하지 않으면 건강 내성 DC 10 — 성공하면 HP = 바바리안 레벨 × 2.
## 쓸 때마다 DC +5, 짧은·긴 휴식에 10으로(자원 relentless_rage: 최대 20에서 쓴 횟수만큼 줄어든다 — 짧은 휴식 회복).

const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var info: Dictionary = ctx["res"]
	if info.get("prevented", false) or not c.has_condition("raging") or not c.resources.has("relentless_rage"):
		return {"ok": false}
	if int(info.get("remainder", 0)) >= c.hp_max:
		return {"ok": false}  # 즉사
	var r: Dictionary = c.resources["relentless_rage"]
	var dc: int = 10 + 5 * (int(r["max"]) - int(r["current"]))
	r["current"] = maxi(0, int(r["current"]) - 1)
	var s := Resolver.saving_throw(c, "con", dc, {"natural_rules": true})
	if not s["success"]:
		return {"ok": false}
	c.hp = 2 * c.feature_level("relentless_rage")
	info["prevented"] = true
	Dice.log_text("%s 끈질긴 분노: HP %d" % [c.label(), c.hp])
	return {"ok": true}
