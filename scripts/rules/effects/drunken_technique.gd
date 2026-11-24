extends "res://scripts/rules/effect_script.gd"
## 취권(술 취한 달인 3레벨, BG3): 보너스 행동 + 기 1, 비무장 공격 2회, 이동 +2칸(3m)과 이탈.
const Combat := preload("res://scripts/rules/combat.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	var w: Dictionary = ctx["world"]
	if not (t is Node) or t.dead or not t.is_hostile_to(c) or w["grid"].distance_between(c, t) > 1:
		return {"ok": false, "reason": "옆의 적을 골라야 한다"}
	var hits := 0
	for i in 2:
		if t.dead:
			break
		if Combat._do_attack(w, c, t, Combat.build_weapon_attack(c, "unarmed")).get("hit", false):
			hits += 1
	c.turn["movement"] = int(c.turn.get("movement", 0)) + 2
	c.turn["disengaged"] = true
	return {"ok": true, "hits": hits}
