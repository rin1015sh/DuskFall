extends "res://scripts/rules/effect_script.gd"
## 짐승·식물 매혹(자연 영역 2레벨, BG3): 행동 + 신성 변환. 6칸(9m) 안 적 짐승·식물 지혜 내성, 실패하면 10턴 매혹(피해를 받으면 풀린다).
const Resolver := preload("res://scripts/rules/resolver.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var grid: Node = ctx["world"]["grid"]
	var n := 0
	for o: Node in grid.creatures():
		if o.dead or not c.is_hostile_to(o) or not str(o.creature_type) in ["beast", "plant"] or grid.distance_between(c, o) > 6:
			continue
		if not Resolver.saving_throw(o, "wis", Spellcasting.spell_dc(c), {"source": c, "magic": true})["success"]:
			if o.apply_condition("charmed", 10, c):
				o.set_meta("end_on_damage", ["charmed"])
				n += 1
	return {"ok": true, "charmed": n}
