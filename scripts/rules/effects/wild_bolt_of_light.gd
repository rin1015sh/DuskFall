extends "res://scripts/rules/effect_script.gd"
## 야생 마법: 빛의 화살(BG3): 효과 중 매 턴 보너스 행동, 6칸 안 대상 1d6 광휘 + 건강 내성(DC 8 + 숙련 + 건강) 실패 시 1턴 실명.
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	var grid: Node = ctx["world"]["grid"]
	if not (t is Node) or t.dead or t == c:
		return {"ok": false, "reason": "대상을 골라야 한다"}
	if grid.distance_between(c, t) > 6:
		return {"ok": false, "reason": "6칸 안"}
	Resolver.apply_damage(t, [{"amount": Dice.roll("1d6", "빛의 화살")["total"], "damage_type": "radiant"}], {"attacker": c, "magic": true})
	if not t.dead and not Resolver.saving_throw(t, "con", 8 + c.proficiency_bonus + c.ability_mod("con"), {"source": c, "magic": true})["success"]:
		t.apply_condition("blinded", 1, c)
	return {"ok": true}
