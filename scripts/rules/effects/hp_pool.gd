extends "res://scripts/rules/effect_script.gd"
## 체력 총량 주문(BG3 수치 — 수면·색 분사): 내성 없이 현재 HP가 낮은 생물부터, 합이 총량을 넘지 않는 만큼 상태를 건다.
## 주문 데이터 hp_pool {base, per_slot(상위 슬롯마다), condition, turns, ends_on_damage}.
## 범위 주문은 범위 안 생물, 범위가 없으면 opts.targets(고른 대상)이나 조준 칸의 생물과 그 둘레 2칸 적(여러 대상 고르기 UI 대신).
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Area := preload("res://scripts/rules/area.gd")
const U := preload("res://scripts/rules/spell_util.gd")

const AUTO_RADIUS := 2


func is_implemented() -> bool:
	return true


static func pool(spell: Dictionary, slot: int) -> int:
	var hp: Dictionary = spell.get("hp_pool", {})
	return int(hp.get("base", 0)) + int(hp.get("per_slot", 0)) * maxi(0, slot - int(spell.get("level", 1)))


static func immune(t: Node, cond: String) -> bool:
	if cond in ["unconscious", "asleep"] and (t.has_cap("immune_magic_sleep") or t.creature_type in ["undead", "construct"]):
		return true  # 잠들지 않는 생물(엘프 요정 혈통·언데드·구조물)
	return t.is_condition_immune(cond)


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var spell: Dictionary = ctx["spell"]
	var hp: Dictionary = spell.get("hp_pool", {})
	var cond := str(hp.get("condition", "unconscious"))
	var g := U.grid(ctx)
	var cands: Array = []
	if spell.get("area") != null:
		cands = Area.creatures_in(g, Spellcasting.area_cells(ctx["world"], c, spell, ctx["aim"]))
	else:
		cands = ctx["opts"].get("targets", []).duplicate()
		if cands.is_empty():
			var first: Node = g.creature_at(U.aim_cell(ctx))
			if first != null:
				cands.append(first)
				for o: Node in g.creatures():
					if o != first and o.is_hostile_to(c) and g.distance_between(first, o) <= AUTO_RADIUS:
						cands.append(o)
	cands = cands.filter(func(t: Node) -> bool: return not t.dead and t != c and not immune(t, cond))
	cands.sort_custom(func(a: Node, b: Node) -> bool: return a.hp < b.hp)
	var left := pool(spell, int(ctx["slot"]))
	var n := 0
	for t: Node in cands:
		if t.hp > left:
			continue
		left -= t.hp
		U.add_condition(ctx, t, cond, int(hp.get("turns", 0)), {"ends_on_damage": bool(hp.get("ends_on_damage", false))})
		n += 1
	Dice.log_text("%s %s: 총량 %d 중 %d 남음, %d명" % [c.label(), str(spell.get("id", "")), pool(spell, int(ctx["slot"])), left, n])
	return {"ok": true, "affected": n, "left": left}
