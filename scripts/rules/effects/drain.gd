extends "res://scripts/rules/effect_script.gd"
## Vampiric Touch(SRD): 근접 주문 공격 3d6 사령, 준 피해 절반 회복. 집중 동안 턴마다 행동으로 다시(슬롯 없이 — opts.no_slot).
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Area := preload("res://scripts/rules/area.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var grid: Node = ctx["world"]["grid"]
	var t: Node = grid.creature_at(ctx["aim"])
	if t == null or t == c:
		return {"ok": false, "reason": "대상이 없다"}
	var dice := Spellcasting.scaled_dice(c, ctx["spell"], "3d6", int(ctx["slot"]))
	var r := Resolver.attack(c, t, {"name": "Vampiric Touch", "bonus": Spellcasting.spell_attack_bonus(c), "kind": "melee",
		"weapon": false, "damage": [{"dice": dice, "damage_type": "necrotic"}]}, grid.attack_context(c, t))
	if r["hit"]:
		Resolver.heal(c, int(r["damage"]["total"]) / 2, c)
	if not ctx["opts"].get("no_slot", false):
		c.extra_modifiers.append({"effect": {"type": "grant_action", "action": "repeat_spell", "spell": "vampiric_touch",
			"slot": ctx["slot"]}, "source": "vampiric_touch", "instance": ctx["instance"]["id"], "turns_left": -1})
	return {"ok": true, "hit": r["hit"]}
