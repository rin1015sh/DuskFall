extends "res://scripts/rules/effect_script.gd"
## 몸의 완전함(열린 손 6레벨, SRD): 보너스 행동, 무술 주사위 + 지혜 수정치(최소 1) 회복. 지혜 수정치(최소 1)회, 긴 휴식.


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	if c.hp >= c.hp_max:
		return {"ok": false, "reason": "HP가 가득하다"}
	var die: String = load("res://scripts/rules/combat.gd").martial_arts_die(c)
	var n: int = maxi(1, Dice.roll(die, "몸의 완전함")["total"] + c.ability_mod("wis"))
	var got: int = load("res://scripts/rules/resolver.gd").heal(c, n, c)
	return {"ok": true, "healed": got}
