extends "res://scripts/rules/effect_script.gd"
## Elementalism(소마법, 자체 변환): 조준 칸에 광원이 있으면 켜고 끄고, 불 표면이면 끄고, 아니면 1칸을 적신다(물).

const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var g := U.grid(ctx)
	var cell := U.aim_cell(ctx)
	for src: Dictionary in g.light_sources:
		if src.get("cell") == cell and not src.has("creature"):
			src["off"] = not src.get("off", false)
			Dice.log_text("광원을 %s" % ("껐다" if src["off"] else "켰다"))
			return {"ok": true, "toggled": true}
	if ctx["world"].get("surfaces") != null:
		ctx["world"]["surfaces"].apply_water([cell])
	return {"ok": true}
