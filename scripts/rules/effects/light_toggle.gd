extends "res://scripts/rules/effect_script.gd"
## Prestidigitation(소마법): 연출 + 조준 칸의 촛불·횃불 켜기·끄기.

const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var g := U.grid(ctx)
	for src: Dictionary in g.light_sources:
		if src.get("cell") == U.aim_cell(ctx) and not src.has("creature"):
			src["off"] = not src.get("off", false)
			return {"ok": true, "toggled": true}
	return {"ok": true}
