extends "res://scripts/rules/effect_script.gd"
## 원초의 쇄도(엘크의 심장, BG3): 행동, 곧은 선으로 6칸(9m)까지 기회 공격 없이 돌진(이동력은 쓰지 않음 — [변형]).
## 지나는 길 1칸 안 적마다 근접 비무장 공격 1d4 + 근력 타격, 맞으면 근력 내성(DC 10 + 근력) 실패 시 넘어짐.
const Combat := preload("res://scripts/rules/combat.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	var w: Dictionary = ctx["world"]
	var grid: Node = w["grid"]
	var goal: Vector2i = t if t is Vector2i else (grid.cell_of(t) if t is Node else Vector2i(-1, -1))
	var from: Vector2i = grid.cell_of(c)
	if goal == Vector2i(-1, -1) or goal == from:
		return {"ok": false, "reason": "방향을 골라야 한다"}
	var cur := from
	var passed: Array[Vector2i] = [from]
	while grid.distance(from, cur) < 6:
		var nxt := cur + Vector2i(signi(goal.x - cur.x), signi(goal.y - cur.y))
		if nxt == cur or not grid.can_step_sized(cur, nxt, grid.size_of(c), c, []) or grid.creature_at(nxt) != null:
			break
		cur = nxt
		passed.append(cur)
		if cur == goal:
			break
	var foes: Array = []
	for o: Node in grid.creatures():
		if o != c and not o.dead and o.is_hostile_to(c) and passed.any(func(p: Vector2i) -> bool: return grid.distance(p, grid.cell_of(o)) <= 1):
			foes.append(o)
	if cur != from:
		grid.move_creature(c, cur)
	var mod: int = c.ability_mod("str")
	var hits := 0
	for o: Node in foes:
		var atk := {"name": "원초의 쇄도", "bonus": mod + c.proficiency_bonus, "kind": "melee", "weapon": false, "ability": "str",
			"reach_tiles": 99, "damage": [{"dice": "1d4%+d" % mod if mod != 0 else "1d4", "damage_type": "bludgeoning"}]}
		var r := Combat._do_attack(w, c, o, atk, true)
		if r.get("hit", false) and not o.dead:
			hits += 1
			if not Resolver.saving_throw(o, "str", 10 + mod, {"source": c})["success"]:
				o.apply_condition("prone", -1, c)
	return {"ok": true, "targets": foes.size(), "hits": hits, "moved": cur != from}
