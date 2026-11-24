extends "res://scripts/rules/effect_script.gd"
## 맹세의 퇴치(헌신: 부정한 것 퇴치 — 언데드·악마 / 고대인: 신앙 없는 자 퇴치 — 요정·악마, BG3): 행동 + 신성 변환,
## 6칸(9m) 안 기능 turn_types 종류 적 지혜 내성(DC 8 + 숙련 + 매력) 실패 시 3턴 퇴치(공포 + 무력화, 피해를 받으면 끝).
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var grid: Node = ctx["world"]["grid"]
	var types: Array = ctx.get("feature", {}).get("turn_types", ["undead", "fiend"])
	var dc: int = 8 + c.proficiency_bonus + c.ability_mod("cha")
	var n := 0
	for o: Node in grid.creatures():
		if o.dead or not o.is_hostile_to(c) or not str(o.creature_type) in types or grid.distance_between(c, o) > 6:
			continue
		if not Resolver.saving_throw(o, "wis", dc, {"source": c})["success"]:
			o.apply_condition("frightened", 3, c)
			o.apply_condition("incapacitated", 3, c)
			o.set_meta("end_on_damage", ["frightened", "incapacitated"])
			n += 1
	return {"ok": true, "turned": n}
