extends "res://scripts/rules/effect_script.gd"
## 격노의 투척(광전사 3레벨, BG3): 광란 중 보너스 행동, 12칸(18m) 안 적에게 즉석 물건을 던진다 — 근력 + 숙련 명중,
## 1d4 + 근력 타격 + 분노 피해, 맞으면 내성 없이 넘어짐. [변형] 주변 물건·생물을 집지 않는다(던질 거리·무게 생략).
const Combat := preload("res://scripts/rules/combat.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	var w: Dictionary = ctx["world"]
	if not (t is Node) or t.dead or not t.is_hostile_to(c):
		return {"ok": false, "reason": "적을 골라야 한다"}
	if w["grid"].distance_between(c, t) > 12:
		return {"ok": false, "reason": "12칸 안"}
	var mod: int = c.ability_mod("str")
	var rb := Resolver.rage_bonus(c) * (2 if c.has_flag("throw_rage_double") else 1)
	var atk := {"name": "격노의 투척", "bonus": mod + c.proficiency_bonus, "kind": "ranged", "weapon": false, "ability": "str",
		"range_tiles": [12, 12], "damage": [{"dice": "1d4%+d" % (mod + rb) if mod + rb != 0 else "1d4", "damage_type": "bludgeoning"}]}
	var r := Combat._do_attack(w, c, t, atk)
	if r.get("hit", false) and not t.dead:
		t.apply_condition("prone", -1, c)
	r["ok"] = true
	return r
