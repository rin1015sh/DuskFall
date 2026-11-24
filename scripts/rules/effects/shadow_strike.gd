extends "res://scripts/rules/effect_script.gd"
## 그림자 일격(그림자 11레벨, BG3): 행동 + 기 3, 숨은(투명) 상태에서 6칸(9m) 안 적 옆으로 순간 이동해 무기 공격 + 3d8 정신.
const Combat := preload("res://scripts/rules/combat.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	var w: Dictionary = ctx["world"]
	var grid: Node = w["grid"]
	if not c.has_condition("invisible"):
		return {"ok": false, "reason": "숨은 상태에서만"}
	if not (t is Node) or t.dead or not t.is_hostile_to(c) or grid.distance_between(c, t) > 6:
		return {"ok": false, "reason": "6칸 안 적"}
	if grid.distance_between(c, t) > 1:
		var at: Vector2i = grid.cell_of(t)
		var me: Vector2i = grid.cell_of(c)
		var best := Vector2i(-9999, -9999)
		for d: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]:
			var cell := at + d
			if grid.creature_at(cell) == null and not grid.blocks_movement(cell) and (best.x == -9999 or grid.distance(me, cell) < grid.distance(me, best)):
				best = cell
		if best.x == -9999:
			return {"ok": false, "reason": "설 자리가 없다"}
		grid.move_creature(c, best)
	var main: String = c.weapon_sets.get("melee", {}).get("main", "")
	var atk := Combat.build_weapon_attack(c, main if main != "" else "unarmed")
	atk["name"] = "그림자 일격"
	var r := Combat._do_attack(w, c, t, atk)
	if r.get("hit", false) and not t.dead:
		load("res://scripts/rules/resolver.gd").apply_damage(t, [{"amount": Dice.roll("3d8", "그림자 일격")["total"], "damage_type": "psychic"}], {"attacker": c})
	r["ok"] = true
	return r
