extends "res://scripts/rules/effect_script.gd"
## Protection from Evil and Good(1레벨, SRD): 대상에게 이형·천상·원소·요정·마족·언데드의 공격 굴림이 불리(매혹·공포 면역은 1차 생략).

const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var t := U.target(ctx)
	if t == null:
		return {"ok": false, "reason": "대상이 없다"}
	U.add_condition(ctx, t, "protected_from_types")
	return {"ok": true}
