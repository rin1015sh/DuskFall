extends "res://scripts/rules/effect_script.gd"
## Power Word Kill(SRD 9레벨): 내성 없이 — HP 100 이하면 죽고, 아니면 12d12 정신 피해.

const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Node = ctx["world"]["grid"].creature_at(ctx["aim"])
	if t == null or t.dead:
		return {"ok": false, "reason": "대상이 없다"}
	if t.hp <= 100:
		Resolver._die(t, "권능의 말: 죽음")
		return {"ok": true, "killed": true}
	Resolver.apply_damage(t, [{"amount": Dice.roll("12d12", "권능의 말: 죽음")["total"], "damage_type": "psychic"}], {"attacker": c})
	return {"ok": true, "killed": false}
