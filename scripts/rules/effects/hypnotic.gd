extends "res://scripts/rules/effect_script.gd"
## Hypnotic Pattern(SRD): 30피트 정육면체(6×6칸) 안 패턴을 보는 생물 지혜 내성. 실패 → 매혹 + 무력화 + 속도 0.
## 피해를 받으면 끝(다른 생물이 행동으로 깨우는 것은 6단계).
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
		if t.dead or t == c or t.has_condition("blinded"):
			continue
		if Resolver.saving_throw(t, "wis", dc, {"source": c, "against_conditions": ["charmed"]})["success"]:
			continue
		var p := {"instance": id, "ends_on_damage": true}
		t.apply_condition("charmed", -1, c, p)
		t.apply_condition("incapacitated", -1, c, p)
		t.extra_modifiers.append({"effect": {"type": "modify", "stat": "speed_tiles", "add": -99}, "source": "hypnotic", "instance": id, "turns_left": -1})
		ctx["instance"]["targets"].append(t)
		n += 1
	return {"ok": true, "affected": n}
