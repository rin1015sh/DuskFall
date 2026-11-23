extends "res://scripts/rules/effect_script.gd"
## Divine Word(SRD 7레벨): 보너스 행동, 6칸 안 고른 생물(적 전부 — BG3식 자동) 매력 내성. 실패하고 지금 HP 50 이하면:
## 20 이하 죽음, 30 이하 실명·기절 1시간(긴 휴식까지), 40 이하 실명 10분(100턴), 50 이하 효과 없음(귀먹음 — 없는 상태).
## 천상체·정령·요정·악마는 실패하면 추방(긴 휴식까지 — 원문: 24시간 자기 세계로).

const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const EXTRAPLANAR := ["celestial", "elemental", "fey", "fiend"]


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var grid: Node = ctx["world"]["grid"]
	var dc: int = Spellcasting.spell_dc(c)
	var n := 0
	for o: Node in grid.creatures().filter(func(x: Node) -> bool: return not x.dead and x.is_hostile_to(c) and grid.distance_between(c, x) <= 6):
		var s := Resolver.saving_throw(o, "cha", dc, {"source": c, "magic": true})
		if s["success"]:
			continue
		n += 1
		if o.creature_type in EXTRAPLANAR:
			o.apply_condition("banished", -1, c)
			continue
		if o.hp <= 20:
			Resolver._die(o, "신성한 말")
		elif o.hp <= 30:
			o.apply_condition("blinded", -1, c)
			o.apply_condition("stunned", -1, c)
		elif o.hp <= 40:
			o.apply_condition("blinded", 100, c)
	return {"ok": true, "affected": n}
