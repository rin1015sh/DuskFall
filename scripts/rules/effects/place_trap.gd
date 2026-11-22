extends "res://scripts/rules/effect_script.gd"
## Glyph of Warding(3레벨, SRD): 폭발 룬 — 반경 4칸, 민첩 내성 5d8(성공 절반, 종류 opts.damage_type 기본 천둥). 시전자 편이 아닌 생물이 밟으면 터진다. 파티는 위치를 안다.

const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var cell := U.aim_cell(ctx)
	var dtype: String = ctx.get("opts", {}).get("damage_type", "thunder")
	var t := {"id": "glyph_of_warding", "cell": [cell.x, cell.y], "dc_find": U.dc(ctx), "dc_disarm": U.dc(ctx),
		"save": {"ability": "dex", "dc": U.dc(ctx)}, "half_on_save": true, "radius": 4, "state": "armed", "found": true,
		"owner_team": ctx["self"].team, "art": "glow_rune.a_blue",
		"effects": [{"type": "damage", "dice": "%dd8" % (5 + maxi(int(ctx.get("slot", 3)) - 3, 0)), "damage_type": dtype}]}
	if not ctx["world"].has("traps"):
		ctx["world"]["traps"] = []
	ctx["world"]["traps"].append(t)
	return {"ok": true}
