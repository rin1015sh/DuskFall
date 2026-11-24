extends "res://scripts/rules/effect_script.gd"
## 불뱀의 송곳니(4원소, BG3): 행동 + 기 1, 비무장 공격(도달 +2칸) + 맞으면 1d10 화염, 이번 턴 남은 근접 공격 +1d4 화염(상태 fire_snake_fangs).
const Combat := preload("res://scripts/rules/combat.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	if not (t is Node) or t.dead or not t.is_hostile_to(c):
		return {"ok": false, "reason": "적을 골라야 한다"}
	var atk := Combat.build_weapon_attack(c, "unarmed")
	atk["name"] = "불뱀의 송곳니"
	atk["reach_tiles"] = 3
	var r := Combat._do_attack(ctx["world"], c, t, atk)
	if not r.get("ok", true):
		return r
	if r.get("hit", false) and not t.dead:
		load("res://scripts/rules/resolver.gd").apply_damage(t, [{"amount": Dice.roll("1d10", "불뱀의 송곳니")["total"], "damage_type": "fire"}], {"attacker": c})
	c.apply_condition("fire_snake_fangs", 1, c)
	r["ok"] = true
	return r
