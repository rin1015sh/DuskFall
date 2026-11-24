extends "res://scripts/rules/effect_script.gd"
## Call Lightning(BG3 수치): 겨눈 칸 반경 1칸 민첩 내성 3d10 번개(+1d10/슬롯), 성공 절반. 집중 10턴 동안 다시 쓰기(행동, 슬롯 없음)로 다른 칸에 다시 내리친다.
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var r := Spellcasting.resolve_effects(ctx)
	r["ok"] = true
	return r


func recast(ctx: Dictionary) -> Dictionary:
	var g: Node = ctx["world"]["grid"]
	if g.distance(g.cell_of(ctx["self"]), ctx["aim"]) > Spellcasting.range_tiles(ctx["spell"]):
		return {"ok": false, "reason": "사거리 밖"}
	var r := Spellcasting.resolve_effects(ctx)
	r["ok"] = true
	return r
