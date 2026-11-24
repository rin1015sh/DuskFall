extends "res://scripts/rules/effect_script.gd"
## 그림자 기술: 숨기(그림자 3레벨, BG3): 보너스 행동으로 숨기.
func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var r: Dictionary = load("res://scripts/rules/combat.gd").hide(ctx["world"], ctx["self"], "free")
	return r
