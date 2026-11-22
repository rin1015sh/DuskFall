extends "res://scripts/rules/effect_script.gd"
## Sanctuary(SRD): 보호받는 생물을 공격 굴림·피해 주문으로 노리면 지혜 내성, 실패하면 그 공격을 잃는다(10턴).
## 보호받는 생물이 공격하거나 주문을 시전하면 끝.
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Area := preload("res://scripts/rules/area.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var grid: Node = ctx["world"]["grid"]
	var t: Node = grid.creature_at(ctx["aim"])
	if t == null:
		return {"ok": false, "reason": "대상이 없다"}
	var id: int = ctx["instance"]["id"]
	t.extra_modifiers.append({"effect": {"type": "modify", "stat": "sanctuary", "dc": Spellcasting.spell_dc(ctx["self"])},
		"source": "sanctuary", "instance": id, "turns_left": 10})
	t.apply_condition("sanctuary_ward", 10, ctx["self"], {"instance": id, "ends_on_attack": true, "ends_on_cast": true})
	ctx["instance"]["targets"].append(t)
	return {"ok": true}
