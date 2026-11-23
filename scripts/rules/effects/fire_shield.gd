extends "res://scripts/rules/effect_script.gd"
## Fire Shield(SRD, 4레벨): 10분(100턴) 동안 따뜻한 방패(냉기 저항, 근접 명중한 1칸 안 공격자 2d8 화염) 또는
## 차가운 방패(화염 저항, 2d8 냉기). 고르기 opts.choice("warm"·"chill", 피해 종류 "cold"·"fire"도 받음) — 없으면 따뜻한 방패.


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var pick := str(ctx.get("opts", {}).get("choice", "warm"))
	var id := "fire_shield_chill" if pick in ["chill", "fire"] else "fire_shield_warm"
	c.remove_condition("fire_shield_warm")
	c.remove_condition("fire_shield_chill")
	c.apply_condition(id, 100, c, {"instance": ctx["instance"]["id"]})
	return {"ok": true, "shield": id}
