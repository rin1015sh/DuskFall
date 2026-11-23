extends "res://scripts/rules/effect_script.gd"
## 무술 — 보너스 비무장 공격(몽크 1레벨, SRD): 갑옷·방패 없이 보너스 행동으로 비무장 공격 1회(무술 주사위 + 민첩/근력).

const Combat := preload("res://scripts/rules/combat.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	var w: Dictionary = ctx.get("world", {})
	if not (t is Node) or t.dead or not c.is_hostile_to(t):
		return {"ok": false, "reason": "적을 골라야 한다"}
	if not Combat.martial_arts_applies(c, Combat.weapon_data("unarmed")):
		return {"ok": false, "reason": "갑옷·방패 없이만"}
	if w.has("grid") and w["grid"].distance_between(c, t) > 1:
		return {"ok": false, "reason": "인접해야 한다"}
	var res := Combat._do_attack(w, c, t, Combat.build_weapon_attack(c, "unarmed"))
	res["ok"] = true
	return res
