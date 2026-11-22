extends "res://scripts/rules/effect_script.gd"
## Levitate(2레벨, SRD): 생물 하나를 고도 4(20피트)로 띄운다. 원치 않으면 건강 내성. 떠 있는 동안 스스로 걷지 못한다. 끝나면 천천히 내려온다(피해 없음).

const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var t := U.target(ctx)
	if t == null:
		return {"ok": false, "reason": "대상이 없다"}
	if t.is_hostile_to(ctx["self"]) and Resolver.saving_throw(t, "con", U.dc(ctx))["success"]:
		return {"ok": true, "saved": true}
	U.add_condition(ctx, t, "levitating")
	U.set_until_end(ctx, t, "altitude", 4)
	return {"ok": true}
