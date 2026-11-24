extends "res://scripts/rules/effect_script.gd"
## 취하게 하는 일격(술 취한 달인 4레벨, BG3): 행동(또는 보너스 행동판) + 기 1, 비무장 공격 — 맞으면 건강 내성(DC 8 + 숙련 + 지혜)
## 실패 시 5턴 취함. 맞히면 나는 1턴 '파티의 주인공'(취한 대상에게 AC +1·명중 + 지혜).
const Combat := preload("res://scripts/rules/combat.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	if not (t is Node) or t.dead or not t.is_hostile_to(c):
		return {"ok": false, "reason": "적을 골라야 한다"}
	var atk := Combat.build_weapon_attack(c, "unarmed")
	atk["name"] = "취하게 하는 일격"
	var r := Combat._do_attack(ctx["world"], c, t, atk)
	if not r.get("ok", true):
		return r
	if r.get("hit", false):
		if c.has_cap("life_of_the_party"):
			c.apply_condition("life_of_the_party", 1, c)
		if not t.dead and not Resolver.saving_throw(t, "con", 8 + c.proficiency_bonus + c.ability_mod("wis"), {"source": c})["success"]:
			t.apply_condition("drunk", 5, c)
	r["ok"] = true
	return r
