extends "res://scripts/rules/effect_script.gd"
## Spare the Dying(룰북 주문 변환표): 3칸 밖에서 쓰는 돕기. 쓰러진 아군을 HP 1로 일으킨다(7단계).
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Area := preload("res://scripts/rules/area.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var t: Node = ctx["world"]["grid"].creature_at(ctx["aim"])
	if t == null or not t.is_down():
		return {"ok": false, "reason": "쓰러진 생물만"}
	Resolver.heal(t, 1, ctx["self"])
	return {"ok": true}
