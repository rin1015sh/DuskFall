extends "res://scripts/rules/effect_script.gd"
## 술 깨는 깨달음(술 취한 달인 9레벨, BG3): 행동 + 기 1, 취한 대상에게 비무장 공격 — 맞으면 2d8 + 지혜 정신, 취함이 풀리고 나는 파티의 주인공을 잃는다.
const Combat := preload("res://scripts/rules/combat.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	if not (t is Node) or t.dead or not t.has_condition("drunk"):
		return {"ok": false, "reason": "취한 대상만"}
	var atk := Combat.build_weapon_attack(c, "unarmed")
	atk["name"] = "술 깨는 깨달음"
	var r := Combat._do_attack(ctx["world"], c, t, atk)
	if not r.get("ok", true):
		return r
	if r.get("hit", false):
		var wm: int = c.ability_mod("wis")
		if not t.dead:
			load("res://scripts/rules/resolver.gd").apply_damage(t, [{"amount": maxi(Dice.roll("2d8", "술 깨는 깨달음")["total"] + wm, 0), "damage_type": "psychic"}], {"attacker": c})
		t.remove_condition("drunk")
		c.remove_condition("life_of_the_party")
	r["ok"] = true
	return r
