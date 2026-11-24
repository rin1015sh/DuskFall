extends "res://scripts/rules/effect_script.gd"
## 언데드 퇴치(클레릭 2레벨 신성 변환, BG3): 6칸 안 언데드 지혜 내성. 실패 → 공포 + 무력화 3턴(피해를 받으면 끝 — 6단계).
## 언데드 파괴(5레벨, BG3): 퇴치된 언데드에게 4d6 광휘.

const Resolver := preload("res://scripts/rules/resolver.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const RANGE := 6


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var w: Dictionary = ctx.get("world", {})
	if not w.has("grid"):
		return {"ok": false, "reason": "격자가 없다"}
	var grid: Node = w["grid"]
	var targets: Array = grid.creatures().filter(func(o: Node) -> bool:
		return not o.dead and o.creature_type == "undead" and o.is_hostile_to(c) and grid.distance_between(c, o) <= RANGE)
	var failed: Array = []
	for t: Node in targets:
		var s := Resolver.saving_throw(t, "wis", Spellcasting.spell_dc(c), {"source": c})
		if not s["success"]:
			t.apply_condition("frightened", 3, c)
			t.apply_condition("incapacitated", 3, c)
			failed.append(t)
	if c.has_feature("destroy_undead") and not failed.is_empty():
		var dmg: int = Dice.roll("4d6", "언데드 파괴")["total"]  # BG3: 퇴치된 언데드 4d6 광휘
		for t: Node in failed:
			Resolver.apply_damage(t, [{"amount": dmg, "damage_type": "radiant"}])
	for t: Node in failed:
		t.set_meta("end_on_damage", ["frightened", "incapacitated"])  # 피해를 받으면 끝(소각 피해는 퇴치를 끝내지 않는다 — SRD)
	return {"ok": true, "turned": failed.size()}
