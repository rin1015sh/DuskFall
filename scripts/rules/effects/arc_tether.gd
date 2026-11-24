extends "res://scripts/rules/effect_script.gd"
## 번개 사슬(자체 이름, BG3 수치): 원거리 주문 공격 1d12 번개(+1d12/슬롯). 맞으면 집중 10턴 동안 대상과 이어진다.
## 다시 쓰기(행동, 슬롯 없음): 이어진 대상이 12칸 안이면 자동으로 1d12 번개. 대상이 쓰러지거나 멀어지면 끝.
const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Node = U.target(ctx)
	if t == null or t == c:
		return {"ok": false, "reason": "대상이 없다"}
	var dice := Spellcasting.damage_dice(c, ctx["spell"], "1d12", int(ctx["slot"]), "lightning")
	var res := Resolver.attack(c, t, {"name": "Arc Tether", "bonus": Spellcasting.spell_attack_bonus(c), "kind": "ranged", "weapon": false,
		"spell": true, "damage": [{"dice": dice, "damage_type": "lightning"}]}, U.grid(ctx).attack_context(c, t))
	if res.get("hit", false) and not t.dead:
		ctx["instance"]["tether"] = t
		ctx["instance"]["targets"].append(t)
	elif c.concentration.get("instance", -1) == ctx["instance"]["id"]:
		c.break_concentration("빗나감")
	return {"ok": true, "hit": res.get("hit", false)}


func recast(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx["instance"].get("tether")
	var g := U.grid(ctx)
	if not (t is Node) or not is_instance_valid(t) or t.dead or g.distance_between(c, t) > 12:
		c.break_concentration("사슬이 끊어짐")
		return {"ok": false, "reason": "이어진 대상이 없다"}
	Resolver.apply_damage(t, [{"amount": Dice.roll("1d12", "번개 사슬")["total"], "damage_type": "lightning"}], {"attacker": c})
	return {"ok": true}
