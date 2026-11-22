extends "res://scripts/rules/effect_script.gd"
## Dispel Magic(SRD): 대상에 걸린 3레벨 이하 주문(쓴 슬롯 레벨 이하)을 끝낸다. 4레벨 이상은 주문 시전 능력 판정 DC 10 + 주문 레벨.
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Area := preload("res://scripts/rules/area.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var t: Node = ctx["world"]["grid"].creature_at(ctx["aim"])
	if t == null:
		return {"ok": false, "reason": "대상이 없다"}
	var ids := {}
	for cond in t.conditions:
		var id: Variant = cond.get("params", {}).get("instance")
		if id != null:
			ids[id] = true
	for m in t.extra_modifiers:
		if m.get("instance") != null:
			ids[m["instance"]] = true
	var ended := 0
	for id: Variant in ids.keys():
		if not Spellcasting.instances.has(id):
			continue
		var lv := int(Spellcasting.instances[id]["slot"])
		var ok := lv <= maxi(3, int(ctx["slot"]))
		if not ok:
			ok = Resolver.ability_check(ctx["self"], ctx["self"].spellcasting_ability, 10 + lv)["success"]
		if ok:
			var caster: Node = Spellcasting.instances[id]["caster"]
			if is_instance_valid(caster) and caster.concentration.get("instance") == id:
				caster.concentration = {}
			Spellcasting.end_instance(id)
			ended += 1
	return {"ok": true, "ended": ended}
