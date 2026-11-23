extends "res://scripts/rules/effect_script.gd"
## Chain Lightning(SRD 6레벨): 첫 대상 + 그 6칸 안의 다른 대상 최대 3(올린 슬롯마다 +1)에게 민첩 내성 10d8 번개(성공 절반).
## 다른 대상은 가까운 적부터 자동(BG3식). 피해는 한 번만 굴린다.

const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var grid: Node = ctx["world"]["grid"]
	var first: Node = grid.creature_at(ctx["aim"])
	if first == null:
		return {"ok": false, "reason": "대상이 없다"}
	var extra: int = 3 + maxi(0, int(ctx["slot"]) - 6)
	var others: Array = grid.creatures().filter(func(o: Node) -> bool:
		return o != first and o != c and not o.dead and o.is_hostile_to(c) and grid.distance_between(first, o) <= 6)
	others.sort_custom(func(a: Node, b: Node) -> bool: return grid.distance_between(first, a) < grid.distance_between(first, b))
	var targets: Array = [first] + others.slice(0, extra)
	var spell: Dictionary = ctx["spell"]
	var fail: Array = Spellcasting._scaled(c, spell, spell["effects"]["fail"], int(ctx["slot"]), ctx.get("opts", {}))
	var success: Array = Spellcasting._scaled(c, spell, spell["effects"]["success"], int(ctx["slot"]), ctx.get("opts", {}))
	var r := Resolver.save_effect(targets, {"ability": "dex", "dc": Spellcasting.spell_dc(c)}, fail, success, {"source": c, "magic": true})
	return {"ok": true, "results": r}
