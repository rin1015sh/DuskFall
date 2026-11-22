extends "res://scripts/rules/effect_script.gd"
## Chromatic Orb(SRD): 피해 유형 선택(산·냉기·화염·번개·독·천둥, opts.choice), 원거리 주문 공격 3d8.
## 같은 눈이 둘 이상이면 6칸 안 다른 대상에게 튄다(슬롯 레벨만큼, 대상마다 1번).
## Dragon's Breath: 접촉한 생물이 지속 동안 행동으로 원뿔 3칸 민첩 내성 3d6(선택 유형)을 내뿜는다.
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Area := preload("res://scripts/rules/area.gd")


func is_implemented() -> bool:
	return true


const TYPES := ["acid", "cold", "fire", "lightning", "poison", "thunder"]


func apply(ctx: Dictionary) -> Dictionary:
	var spell: Dictionary = ctx["spell"]
	var choice: String = ctx["opts"].get("choice", "fire")
	if not choice in TYPES:
		choice = "fire"
	if spell["id"] == "dragon_s_breath":
		return _breath(ctx, choice)
	var c: Node = ctx["self"]
	var grid: Node = ctx["world"]["grid"]
	var t: Node = grid.creature_at(ctx["aim"])
	if t == null:
		return {"ok": false, "reason": "대상이 없다"}
	var dice := Spellcasting.scaled_dice(c, spell, "3d8", int(ctx["slot"]))
	var leaps: int = int(ctx["slot"])
	var done: Array = []
	while t != null:
		done.append(t)
		var atk := {"name": "Chromatic Orb", "bonus": Spellcasting.spell_attack_bonus(c), "kind": "ranged", "weapon": false, "damage": []}
		var r := Resolver.attack(c, t, atk, grid.attack_context(c, t))
		var next: Node = null
		if r["hit"]:
			var roll := Dice.roll(dice, "Chromatic Orb", r["crit"])
			Resolver.apply_damage(t, [{"amount": roll["total"], "damage_type": choice}], {"attacker": c, "crit": r["crit"]})
			var seen := {}
			var dup := false
			for v: int in roll["rolls"]:
				if seen.has(v):
					dup = true
				seen[v] = true
			if dup and leaps > 0 - 0 and done.size() <= leaps:
				for o: Node in grid.creatures():
					if not o.dead and not o in done and o.is_hostile_to(c) and grid.distance_between(t, o) <= 6:
						next = o
						break
		t = next
	return {"ok": true, "targets": done.size()}


func _breath(ctx: Dictionary, choice: String) -> Dictionary:
	var grid: Node = ctx["world"]["grid"]
	var t: Node = grid.creature_at(ctx["aim"])
	if t == null:
		t = ctx["self"]
	var dice := Spellcasting.scaled_dice(ctx["self"], ctx["spell"], "3d6", int(ctx["slot"]))
	t.extra_modifiers.append({"effect": {"type": "grant_action", "action": "breath", "damage_type": choice, "dice": dice,
		"dc": Spellcasting.spell_dc(ctx["self"])}, "source": "dragon_s_breath", "instance": ctx["instance"]["id"], "turns_left": -1})
	ctx["instance"]["targets"].append(t)
	return {"ok": true}
