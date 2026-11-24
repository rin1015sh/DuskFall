extends "res://scripts/rules/effect_script.gd"
## 최면 응시(환혹학파 2레벨, BG3): 행동, 곁(1칸)의 생물 지혜 내성 — 실패하면 2턴 동안 최면(매혹 + 무력화, 피해를 받으면 풀림). 긴 휴식 1회.
const Resolver := preload("res://scripts/rules/resolver.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	var grid: Node = ctx["world"]["grid"]
	if not (t is Node) or t.dead or t == c or grid.distance_between(c, t) > 1:
		return {"ok": false, "reason": "곁의 생물을 골라야 한다"}
	var sv := Resolver.saving_throw(t, "wis", Spellcasting.spell_dc(c), {"source": c, "magic": true})
	if not sv["success"]:
		t.apply_condition("hypnotized", 2, c)
		t.set_meta("end_on_damage", ["hypnotized"])
	return {"ok": true, "success": not sv["success"]}
