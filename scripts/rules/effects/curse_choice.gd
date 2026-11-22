extends "res://scripts/rules/effect_script.gd"
## Bestow Curse(3레벨, SRD): 지혜 내성 실패 → 저주. 고르는 효과(opts.curse): ability(고른 능력 판정·내성 불리, 기본 지혜), attack(시전자를 향한 공격 불리), damage(시전자의 공격·주문에 맞으면 1d8 사령, 기본).

const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var t := U.target(ctx)
	if t == null:
		return {"ok": false, "reason": "대상이 없다"}
	if Resolver.saving_throw(t, "wis", U.dc(ctx))["success"]:
		return {"ok": true, "saved": true}
	var c: Node = ctx["self"]
	var kind: String = ctx.get("opts", {}).get("curse", "damage")
	U.add_condition(ctx, t, "cursed")
	var inst_id: int = ctx["instance"]["id"]
	match kind:
		"ability":
			var ab: String = ctx.get("opts", {}).get("ability", "wis")
			t.extra_modifiers.append({"effect": {"type": "advantage", "roll": "saving_throw", "side": "self", "value": "disadvantage", "ability": [ab]}, "instance": inst_id, "source": "spell"})
			t.extra_modifiers.append({"effect": {"type": "advantage", "roll": "ability_check", "side": "self", "value": "disadvantage", "ability": [ab]}, "instance": inst_id, "source": "spell"})
		"attack":
			t.extra_modifiers.append({"effect": {"type": "advantage", "roll": "attack", "side": "self", "value": "disadvantage", "requires": "other_is_source"}, "instance": inst_id, "source": c})
		_:
			var cb := func(info: Dictionary) -> void:
				if info.get("target") == t and info.get("opts", {}).get("attacker") == c and not info.get("opts", {}).get("curse", false) and not t.dead:
					var r: int = Dice.roll("1d8", "저주")["total"]
					Resolver.apply_damage(t, [{"amount": r, "damage_type": "necrotic"}], {"attacker": c, "curse": true})
			EventBus.on_damage_taken.connect(cb)
			U.on_end(ctx, func() -> void:
				if EventBus.on_damage_taken.is_connected(cb):
					EventBus.on_damage_taken.disconnect(cb))
	return {"ok": true, "curse": kind}
