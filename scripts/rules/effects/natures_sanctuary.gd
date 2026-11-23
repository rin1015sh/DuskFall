extends "res://scripts/rules/effect_script.gd"
## 자연의 성소(대지 회합 14레벨, SRD): 행동, 야생 변신 1회. 24칸 안 3×3칸에 유령 나무 10턴 — 그 안 자신·아군은 반엄폐(AC +2·민첩 내성 +2)와
## 자연의 수호 저항. 1차: 시전할 때 안에 있는 자신·아군에게 상태(sanctuary_grove)를 건다(옮기기·드나들기 생략).

const Area := preload("res://scripts/rules/area.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var w: Dictionary = ctx.get("world", {})
	if not w.has("grid"):
		return {"ok": false, "reason": "격자가 없다"}
	var grid: Node = w["grid"]
	var t: Variant = ctx.get("target")
	var center: Vector2i = t if t is Vector2i else (grid.cell_of(t) if t is Node else grid.cell_of(c))
	if grid.distance(grid.cell_of(c), center) > 24:
		return {"ok": false, "reason": "사거리 밖"}
	var res_types: Array = c.damage_resistances.filter(func(x: String) -> bool: return x in ["fire", "cold", "lightning", "poison"])
	var n := 0
	for o: Node in grid.creatures():
		if o.dead or o.is_hostile_to(c):
			continue
		var cell: Vector2i = grid.cell_of(o)
		if absi(cell.x - center.x) <= 1 and absi(cell.y - center.y) <= 1:
			o.apply_condition("sanctuary_grove", 10, c, {"resist": res_types})
			for r: String in res_types:
				o.extra_modifiers.append({"effect": {"type": "modify", "stat": "damage_resistance", "damage_types": [r]},
					"source": "sanctuary_grove", "turn_ends_left": 10})
			n += 1
	return {"ok": true, "covered": n}
