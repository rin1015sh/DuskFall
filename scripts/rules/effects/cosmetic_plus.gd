extends "res://scripts/rules/effect_script.gd"
## Thaumaturgy(소마법): 연출 + 데이터 효과(대화 위협 판정 유리).

const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	return load("res://scripts/rules/spellcasting.gd").resolve_effects(ctx)
