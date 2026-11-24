extends "res://scripts/rules/effect_script.gd"
## 서리 갑주(자체 이름, BG3 수치): 임시 HP 5 × 슬롯 레벨, 긴 휴식까지. 임시 HP가 남아 있는 동안 근접으로 나를 맞힌 생물에게 5 × 슬롯 냉기.
const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var n := 5 * maxi(1, int(ctx["slot"]))
	Resolver.grant_temp_hp(c, n)
	U.add_condition(ctx, c, "rime_mantle", -1, {"retaliate_dice": str(n)})
	return {"ok": true, "temp_hp": n}
