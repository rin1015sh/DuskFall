extends "res://scripts/rules/effect_script.gd"
## 일제 사격(사냥꾼 11레벨, BG3): 행동, 원거리 무기 사거리 안 칸 — 그 칸 2칸(3m) 안 아군 아닌 생물마다 원거리 무기 공격(따로 굴림).
## 소용돌이 공격(whirlwind 기능 값): 1칸 안 적마다 근접 무기 공격.
const Combat := preload("res://scripts/rules/combat.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	var w: Dictionary = ctx["world"]
	var grid: Node = w["grid"]
	var whirl: bool = ctx.get("feature", {}).get("whirlwind", false)
	var set_name := "melee" if whirl else "ranged"
	var wid: String = c.weapon_sets.get(set_name, {}).get("main", "")
	if wid == "":
		return {"ok": false, "reason": "근접 무기가 없다" if whirl else "원거리 무기가 없다"}
	var center: Vector2i = grid.cell_of(c)
	if not whirl:
		center = t if t is Vector2i else (grid.cell_of(t) if t is Node else Vector2i(-1, -1))
		if center.x < 0:
			return {"ok": false, "reason": "칸을 골라야 한다"}
	if c.active_set != set_name:
		Combat.switch_weapon_set(c)
	var foes: Array = []
	for o: Node in grid.creatures():
		if o == c or o.dead:
			continue
		if whirl and o.is_hostile_to(c) and grid.distance_between(c, o) <= 1:
			foes.append(o)
		elif not whirl and o.is_hostile_to(c) and grid.distance(center, grid.cell_of(o)) <= 2:
			foes.append(o)
	if foes.is_empty():
		return {"ok": false, "reason": "대상이 없다"}
	var hits := 0
	for o: Node in foes:
		var atk := Combat.build_weapon_attack(c, wid)
		atk["name"] = "소용돌이 공격" if whirl else "일제 사격"
		var r := Combat._do_attack(w, c, o, atk)
		if not r.get("ok", true):
			continue
		if r.get("hit", false):
			hits += 1
	return {"ok": true, "targets": foes.size(), "hits": hits}
