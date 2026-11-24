extends "res://scripts/rules/effect_script.gd"
## 급강하 일격(독수리의 심장, BG3): 행동, 나보다 1단계 이상 낮은 도약 거리 안 적에게 뛰어내려(기회 공격 없이 옆 칸으로)
## 무기 공격, 맞으면 넘어짐. 높이 차 명중 보너스는 그대로.
const Combat := preload("res://scripts/rules/combat.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	var w: Dictionary = ctx["world"]
	var grid: Node = w["grid"]
	if not (t is Node) or t.dead or not t.is_hostile_to(c):
		return {"ok": false, "reason": "적을 골라야 한다"}
	var me: Vector2i = grid.cell_of(c)
	var at: Vector2i = grid.cell_of(t)
	if grid.height(me) - grid.height(at) < 1:
		return {"ok": false, "reason": "나보다 낮은 대상만"}
	if grid.distance(me, at) > Combat.jump_distance(c) + 1:
		return {"ok": false, "reason": "도약 거리 밖"}
	if grid.distance(me, at) > 1:
		var best := Vector2i(-9999, -9999)
		for d: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]:
			var cell := at + d
			if grid.creature_at(cell) == null and not grid.blocks_movement(cell) \
					and (best.x == -9999 or grid.distance(me, cell) < grid.distance(me, best)):
				best = cell
		if best.x == -9999:
			return {"ok": false, "reason": "내려설 자리가 없다"}
		grid.move_creature(c, best)
	if c.active_set != "melee":
		Combat.switch_weapon_set(c)
	var atk := Combat.build_weapon_attack(c, c.weapon("main"))
	atk["name"] = "급강하 일격"
	var r := Combat._do_attack(w, c, t, atk)
	if r.get("hit", false) and not t.dead:
		t.apply_condition("prone", -1, c)
	r["ok"] = true
	return r
