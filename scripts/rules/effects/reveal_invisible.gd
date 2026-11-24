extends "res://scripts/rules/effect_script.gd"
## 투명 간파(환영학파 6레벨, BG3): 행동, 12칸 안 투명한 적 민첩 내성 — 실패하면 투명이 풀리고 2턴 윤곽. 짧은 휴식 1회.
const Resolver := preload("res://scripts/rules/resolver.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var grid: Node = ctx["world"]["grid"]
	var n := 0
	for o: Node in grid.creatures():
		if o.dead or not c.is_hostile_to(o) or not o.has_condition("invisible") or grid.distance_between(c, o) > 12:
			continue
		if not Resolver.saving_throw(o, "dex", Spellcasting.spell_dc(c), {"source": c, "magic": true})["success"]:
			o.remove_condition("invisible")
			o.apply_condition("outlined", 2, c)
			n += 1
	return {"ok": true, "revealed": n}
