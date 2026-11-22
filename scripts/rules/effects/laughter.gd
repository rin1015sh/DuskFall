extends "res://scripts/rules/effect_script.gd"
## Hideous Laughter(SRD): 지혜 내성 실패 → 넘어짐 + 무력화(스스로 일어나지 못함). 턴 끝마다, 피해를 받을 때마다(유리) 다시 내성.
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Area := preload("res://scripts/rules/area.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var grid: Node = ctx["world"]["grid"]
	var targets: Array = ctx["opts"].get("targets", [])
	if targets.is_empty() and grid.creature_at(ctx["aim"]) != null:
		targets = [grid.creature_at(ctx["aim"])]
	targets = targets.slice(0, Spellcasting.max_targets(ctx["spell"], ctx["slot"]))
	var dc := Spellcasting.spell_dc(c)
	var id: int = ctx["instance"]["id"]
	for t: Node in targets:
		if Resolver.saving_throw(t, "wis", dc, {"source": c})["success"]:
			continue
		var rs := {"ability": "wis", "dc": dc}
		t.apply_condition("prone", -1, c, {"instance": id})
		t.apply_condition("incapacitated", -1, c, {"instance": id, "repeat_save": rs, "save_on_damage": rs})
		ctx["instance"]["targets"].append(t)
	return {"ok": true}
