extends "res://scripts/rules/effect_script.gd"
## 언데드 퇴치(클레릭 2레벨 신성 변환, SRD): 6칸 안 언데드 지혜 내성. 실패 → 공포 + 무력화 10턴(피해를 받으면 끝 — 6단계).
## 언데드 소각(5레벨): 실패한 언데드에게 지혜 수정치(최소 1)만큼 d8 광휘.

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
			t.apply_condition("frightened", 10, c)
			t.apply_condition("incapacitated", 10, c)
			t.set_meta("turned_by", c)
			failed.append(t)
	if c.has_feature("sear_undead") and not failed.is_empty():
		var n := maxi(c.ability_mod("wis"), 1)
		var dmg: int = Dice.roll("%dd8" % n, "언데드 소각")["total"]
		for t: Node in failed:
			Resolver.apply_damage(t, [{"amount": dmg, "damage_type": "radiant"}])
	return {"ok": true, "turned": failed.size()}
