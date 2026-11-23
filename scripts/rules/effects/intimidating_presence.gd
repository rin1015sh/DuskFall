extends "res://scripts/rules/effect_script.gd"
## 위협적인 존재감(광전사 14레벨, SRD): 보너스 행동, 6칸 발산 안 적이 지혜 내성(DC 8 + 근력 + 숙련), 실패 시 공포 10턴(턴 끝 내성).
## 긴 휴식 1회 — 횟수가 없으면 분노 1회로(기능 alt_cost).

const Resolver := preload("res://scripts/rules/resolver.gd")
const RANGE := 6


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var w: Dictionary = ctx.get("world", {})
	if not w.has("grid"):
		return {"ok": false, "reason": "격자가 없다"}
	var grid: Node = w["grid"]
	var foes: Array = grid.creatures().filter(func(o: Node) -> bool:
		return not o.dead and o.is_hostile_to(c) and grid.distance_between(c, o) <= RANGE)
	if foes.is_empty():
		return {"ok": false, "reason": "6칸 안에 적이 없다"}
	var dc: int = 8 + c.ability_mod("str") + c.proficiency_bonus
	var n := 0
	for o: Node in foes:
		var s := Resolver.saving_throw(o, "wis", dc, {"source": c, "against_conditions": ["frightened"]})
		if not s["success"] and o.apply_condition("frightened", 10, c, {"repeat_save": {"ability": "wis", "dc": dc}}):
			n += 1
	return {"ok": true, "frightened": n}
