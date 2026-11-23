extends "res://scripts/rules/effect_script.gd"
## 교활한 일격(로그 5레벨, SRD): 급소 공격 주사위 1개로 효과 하나. DC 8 + 민첩 + 숙련.
## 독: 건강 내성, 실패 시 중독 10턴(독살자 도구 요구 삭제 — 룰북 6단계). 넘어뜨리기: 큼 이하, 민첩 내성 → 넘어짐.
## 물러나기: 속도 절반을 기회 공격 없이.

const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Node = ctx.get("target")
	var option: String = ctx.get("opts", {}).get("option", "")
	var dc: int = 8 + c.ability_mod("dex") + c.proficiency_bonus
	match option:
		"poison":
			if t != null and not t.dead:
				var s := Resolver.saving_throw(t, "con", dc, {"source": c, "against_conditions": ["poisoned"]})
				if not s["success"]:
					t.apply_condition("poisoned", 10, c)
		"trip":
			if t != null and not t.dead and t.size != "huge" and t.size != "gargantuan":
				var s := Resolver.saving_throw(t, "dex", dc, {"source": c, "against_conditions": ["prone"]})
				if not s["success"]:
					t.apply_condition("prone", -1, c)
		"withdraw":
			c.turn["free_move_no_oa"] = maxi(int(c.turn.get("free_move_no_oa", 0)), c.speed() / 2)
		_:
			return {"ok": false}
	if option == str(c.turn.get("cunning_strike", "")):
		c.turn["cunning_strike"] = ""
	return {"ok": true, "option": option}
