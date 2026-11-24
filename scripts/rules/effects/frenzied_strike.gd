extends "res://scripts/rules/effect_script.gd"
## 광란의 일격(광전사 3레벨, BG3): 광란 중 보너스 행동으로 근접 무기 공격(턴당 1회). 쓸 때마다 광란의 긴장 1층(명중 −1, 광란이 끝나면 사라짐).
const Combat := preload("res://scripts/rules/combat.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	if not (t is Node) or t.dead or not t.is_hostile_to(c):
		return {"ok": false, "reason": "적을 골라야 한다"}
	if c.turn.get("frenzied_strike_used", false):
		return {"ok": false, "reason": "이번 턴에 이미 썼다"}
	if c.active_set != "melee":
		Combat.switch_weapon_set(c)
	var atk := Combat.build_weapon_attack(c, c.weapon("main"))
	atk["name"] = "광란의 일격"
	var r := Combat._do_attack(ctx["world"], c, t, atk)
	if not r.get("ok", true):
		return r
	c.turn["frenzied_strike_used"] = true
	var inst: Dictionary = c.condition_instance("frenzied_strain")
	var n := int(inst.get("params", {}).get("n", 0)) + 1
	c.remove_condition("frenzied_strain")
	c.apply_condition("frenzied_strain", -1, c, {"n": n})
	r["ok"] = true
	return r
