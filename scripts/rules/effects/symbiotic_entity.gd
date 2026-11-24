extends "res://scripts/rules/effect_script.gd"
## 공생체(포자 회합 2레벨, BG3): 행동 + 야생 변신 1회. 임시 HP 드루이드 레벨 × 4, 긴 휴식까지(임시 HP가 다 하면 끝)
## 무기·맨손 명중에 사령 1d6, 포자 후광 피해 두 배.
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	Resolver.grant_temp_hp(c, 4 * c.feature_level("symbiotic_entity"))
	c.apply_condition("symbiotic_entity", -1, c)
	return {"ok": true}
