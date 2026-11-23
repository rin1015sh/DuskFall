extends "res://scripts/rules/effect_script.gd"
## 적 퇴치(팔라딘 9레벨 신성 변환, SRD): 행동. 12칸 안 보이는 적 매력 수정치(최소 1)명이 지혜 내성.
## 실패 → 공포 10턴(피해를 받으면 끝). 원문의 '이동·행동·보너스 행동 중 하나만'은 생략(공포만 — 룰북 6단계).
## 대상: 고른 적 + 가까운 적 순(BG3식 자동 채우기).

const Resolver := preload("res://scripts/rules/resolver.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const RANGE := 12


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var w: Dictionary = ctx.get("world", {})
	if not w.has("grid"):
		return {"ok": false, "reason": "격자가 없다"}
	var grid: Node = w["grid"]
	var foes: Array = grid.creatures().filter(func(o: Node) -> bool:
		return not o.dead and o.is_hostile_to(c) and grid.distance_between(c, o) <= RANGE and grid.can_see(c, o))
	if foes.is_empty():
		return {"ok": false, "reason": "12칸 안에 보이는 적이 없다"}
	foes.sort_custom(func(a: Node, b: Node) -> bool: return grid.distance_between(c, a) < grid.distance_between(c, b))
	var t: Variant = ctx.get("target")
	if t is Node and t in foes:
		foes.erase(t)
		foes.push_front(t)
	var n := maxi(1, c.ability_mod("cha"))
	var dc: int = Spellcasting.spell_dc(c)
	var hit := 0
	for o: Node in foes.slice(0, n):
		var s := Resolver.saving_throw(o, "wis", dc, {"source": c, "against_conditions": ["frightened"]})
		if not s["success"] and o.apply_condition("frightened", 10, c):
			o.set_meta("end_on_damage", ["frightened"])
			hit += 1
	return {"ok": true, "frightened": hit}
