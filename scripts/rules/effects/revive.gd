extends "res://scripts/rules/effect_script.gd"
## Revivify(SRD): 죽은 지 10턴(1분) 안의 생물을 HP 1로 되살린다(룰북 7단계). 300gp 다이아몬드 소모는 인벤토리(6단계)에서.
## Raise Dead(5레벨): 시간 제한 없이(탐험 전용).
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Area := preload("res://scripts/rules/area.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var grid: Node = ctx["world"]["grid"]
	var t: Node = grid.creature_at(ctx["aim"])
	if t == null or not t.dead:
		return {"ok": false, "reason": "죽은 생물만"}
	var tm: Variant = ctx["world"].get("turns")
	var limit: bool = ctx["spell"]["id"] != "raise_dead"  # Raise Dead: 10일 — 게임 안 날짜가 없어 제한 없음
	if limit and tm != null and t.has_meta("died_round") and tm.round_number - int(t.get_meta("died_round")) > 10:
		return {"ok": false, "reason": "죽은 지 10턴이 넘었다"}
	t.dead = false
	t.hp = 1
	t.death_saves = {"successes": 0, "failures": 0}
	t.stable = false
	t.remove_condition("unconscious")
	t.remove_meta("died_round")
	Dice.log_text("%s 부활(HP 1)" % t.label())
	return {"ok": true}
