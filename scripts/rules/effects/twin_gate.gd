extends "res://scripts/rules/effect_script.gd"
## 쌍둥이 관문(자체 이름, BG3 수치): 12칸 안 두 칸에 이어진 관문(집중 10턴). 첫 관문 = 겨눈 칸, 둘째 = opts.second_cell(없으면 시전자 칸).
## 어느 생물이든(적 포함) 한 관문 칸에 들어서면 다른 관문 칸(비어 있으면)으로 옮겨 간다 — 한 턴에 한 번.
const U := preload("res://scripts/rules/spell_util.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var g := U.grid(ctx)
	var a := U.aim_cell(ctx)
	var b: Vector2i = ctx["opts"].get("second_cell", g.cell_of(c))
	if a == b:
		return {"ok": false, "reason": "두 관문은 다른 칸이어야 한다"}
	U.entity(ctx, "portal", a)
	ctx["instance"]["portals"] = [a, b]
	var used := {}
	var hop := func(world: Dictionary, o: Node) -> void:
		var grid: Node = world["grid"]
		var here: Vector2i = grid.cell_of(o)
		var to := b if here == a else (a if here == b else Vector2i(-1, -1))
		if to == Vector2i(-1, -1) or o.dead:
			return
		var key := "%d:%d" % [o.get_instance_id(), world["turns"].round_number if world.get("turns") != null else 0]
		if used.has(key) or grid.creature_at(to) != null:
			return
		used[key] = true
		grid.move_creature(o, to)
		Dice.log_text("%s: 관문을 지나 %s로" % [o.label(), str(to)])
	ctx["instance"]["auras"].append({"on_enter": hop})
	return {"ok": true, "portals": [a, b]}
