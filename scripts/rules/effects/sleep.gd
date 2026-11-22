extends "res://scripts/rules/effect_script.gd"
## Sleep(SRD 5.2.1): 반경 1칸 구 안 지혜 내성. 실패 → 다음 턴 끝까지 무력화, 그때 다시 내성 실패 → 지속 동안 무의식.
## 피해를 받으면 끝. 잠들지 않는 생물(엘프 트랜스 등)은 자동 성공.
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Area := preload("res://scripts/rules/area.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var cells := Spellcasting.area_cells(ctx["world"], c, ctx["spell"], ctx["aim"])
	var dc := Spellcasting.spell_dc(c)
	var id: int = ctx["instance"]["id"]
	var n := 0
	for t: Node in Area.creatures_in(ctx["world"]["grid"], cells):
		if t.dead or t == c or t.has_feature("trance") or t.creature_type in ["undead", "construct"]:
			continue
		var s := Resolver.saving_throw(t, "wis", dc, {"source": c})
		if s["success"]:
			continue
		t.apply_condition("incapacitated", -1, c, {"instance": id, "ends_on_damage": true,
			"repeat_save": {"ability": "wis", "dc": dc, "on_fail_apply": "unconscious"}})
		ctx["instance"]["targets"].append(t)
		n += 1
	return {"ok": true, "affected": n}
