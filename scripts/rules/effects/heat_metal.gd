extends "res://scripts/rules/effect_script.gd"
## Heat Metal(BG3 수치): 12칸 생물 하나에 2d8 화염(+1d8/슬롯, 내성 없음). 건강 내성 실패 → 무기를 놓친다(무기 놓침),
## 성공해도 1턴 동안 공격·능력 판정 불리(달군 금속). 다시 쓰기(보너스 행동, 슬롯 없음): 같은 대상에 다시.
const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")


func is_implemented() -> bool:
	return true


func _burn(ctx: Dictionary, t: Node) -> void:
	var c: Node = ctx["self"]
	var dice := Spellcasting.damage_dice(c, ctx["spell"], "2d8", int(ctx["slot"]), "fire")
	Resolver.apply_damage(t, [{"amount": Dice.roll(dice, "달군 금속")["total"], "damage_type": "fire"}], {"attacker": c})
	if t.dead:
		return
	if not Resolver.saving_throw(t, "con", U.dc(ctx), {"source": c})["success"]:
		U.add_condition(ctx, t, "disarmed", 2)
	else:
		U.add_condition(ctx, t, "heated", 1)


func apply(ctx: Dictionary) -> Dictionary:
	var t: Node = U.target(ctx)
	if t == null or t == ctx["self"]:
		return {"ok": false, "reason": "대상이 없다"}
	ctx["instance"]["heated"] = t
	_burn(ctx, t)
	return {"ok": true}


func recast(ctx: Dictionary) -> Dictionary:
	var t: Variant = ctx["instance"].get("heated")
	if not (t is Node) or not is_instance_valid(t) or t.dead:
		return {"ok": false, "reason": "대상이 없다"}
	_burn(ctx, t)
	return {"ok": true}
