extends "res://scripts/rules/effect_script.gd"
## Invisibility(SRD): 접촉한 생물 투명(집중). 공격 굴림·피해·주문 시전을 하면 바로 끝난다.
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Area := preload("res://scripts/rules/area.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var grid: Node = ctx["world"]["grid"]
	var targets: Array = ctx["opts"].get("targets", [])
	if targets.is_empty() and grid.creature_at(ctx["aim"]) != null:
		targets = [grid.creature_at(ctx["aim"])]
	targets = targets.slice(0, Spellcasting.max_targets(ctx["spell"], ctx["slot"]))
	for t: Node in targets:
		t.apply_condition("invisible", -1, ctx["self"], {"instance": ctx["instance"]["id"], "ends_on_attack": true, "ends_on_cast": true})
		ctx["instance"]["targets"].append(t)
	return {"ok": true, "targets": targets.size()}
