extends "res://scripts/rules/effect_script.gd"
## 빛의 화살(별 궁수 형상): 보너스 행동, 12칸 원거리 주문 공격 — 광휘 1d8(10레벨 2d8) + 지혜.
const Resolver := preload("res://scripts/rules/resolver.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	var w: Dictionary = ctx["world"]
	if not c.has_condition("starry_archer"):
		return {"ok": false, "reason": "궁수 형상일 때만"}
	if not (t is Node) or t.dead or not c.is_hostile_to(t) or w["grid"].distance_between(c, t) > 12:
		return {"ok": false, "reason": "12칸 안 적을 골라야 한다"}
	var n := 2 if c.has_cap("twinkling_constellations") else 1
	var atk := {"name": "빛의 화살", "bonus": c.proficiency_bonus + c.ability_mod("wis"), "kind": "ranged", "weapon": false, "spell": "luminous_arrow",
		"damage": [{"dice": "%dd8%+d" % [n, c.ability_mod("wis")], "damage_type": "radiant"}], "magical": true}
	var r := Resolver.attack(c, t, atk, w["grid"].attack_context(c, t))
	if w.get("turns") != null:
		w["turns"].notify_hostile_action(c)
	r["ok"] = true
	return r
