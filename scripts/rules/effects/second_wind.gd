extends "res://scripts/rules/effect_script.gd"
## 재기의 숨결(전사 1레벨, SRD): 보너스 행동, 1d10 + 전사 레벨 회복.
## 전술적 이동(5레벨): 속도 절반을 기회 공격 없이 움직일 수 있다.

const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var healed := Resolver.heal(c, Dice.roll("1d10", "재기의 숨결")["total"] + c.feature_level("second_wind"), c)
	if c.has_feature("tactical_shift"):
		c.turn["free_move_no_oa"] = maxi(int(c.turn.get("free_move_no_oa", 0)), c.speed() / 2)
	return {"ok": true, "healed": healed}
