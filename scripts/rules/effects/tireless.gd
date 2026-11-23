extends "res://scripts/rules/effect_script.gd"
## 지치지 않음(레인저 10레벨, SRD): 마법 행동, 임시 HP 1d8 + 지혜 수정치(최소 1). 지혜 수정치(최소 1)회, 긴 휴식.
## 짧은 휴식 탈진 감소는 생략(탈진 규칙이 없음).


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var n: int = maxi(1, Dice.roll("1d8", "지치지 않음")["total"] + c.ability_mod("wis"))
	if n <= c.temp_hp:
		return {"ok": false, "reason": "임시 HP가 이미 더 많다"}
	load("res://scripts/rules/resolver.gd").grant_temp_hp(c, n)
	return {"ok": true, "temp_hp": n}
