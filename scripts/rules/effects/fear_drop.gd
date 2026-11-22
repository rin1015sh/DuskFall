extends "res://scripts/rules/effect_script.gd"
## Fear(SRD): 원뿔 6칸 지혜 내성. 실패 → 쥔 것을 떨어뜨리고(1차: 무기 세트가 빈손이 됨) 공포.
## 공포 동안 질주로 멀어진다(AI). 턴 끝에 시전자가 보이지 않으면 다시 내성.
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Area := preload("res://scripts/rules/area.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var grid: Node = ctx["world"]["grid"]
	var cells := Spellcasting.area_cells(ctx["world"], c, ctx["spell"], ctx["aim"])
	var dc := Spellcasting.spell_dc(c)
	var id: int = ctx["instance"]["id"]
	var n := 0
	for t: Node in Area.creatures_in(grid, cells):
		if t.dead or t == c:
			continue
		if Resolver.saving_throw(t, "wis", dc, {"source": c, "against_conditions": ["frightened"]})["success"]:
			continue
		t.apply_condition("frightened", -1, c, {"instance": id, "flee": true})
		var dropped: Dictionary = t.weapon_sets.duplicate(true)
		t.weapon_sets[t.active_set]["main"] = ""
		ctx["instance"]["reverts"].append({"creature": t, "field": "weapon_sets_note", "value": dropped})
		ctx["instance"]["targets"].append(t)
		n += 1
	return {"ok": true, "affected": n}
