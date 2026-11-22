extends "res://scripts/rules/effect_script.gd"
## Mending(소마법): 부서진 퍼즐 물체(broken)를 고친다. 그 밖에는 효과 없음.

const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var obj: Dictionary = U.grid(ctx).object_at(U.aim_cell(ctx))
	if obj.get("broken", false):
		obj["broken"] = false
		return {"ok": true, "repaired": true}
	return {"ok": true}
