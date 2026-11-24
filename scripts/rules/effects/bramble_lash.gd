extends "res://scripts/rules/effect_script.gd"
## 가시덩굴 채찍(자체 이름, BG3 수치): 6칸(9m) 근접 주문 공격 1d6 관통(5레벨 2d6, 10레벨 3d6). 맞으면 시전자 쪽으로 2칸(3m) 끌려온다.
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
	var dice := Spellcasting.damage_dice(c, ctx["spell"], "1d6", int(ctx["slot"]), "piercing")
	var res := Resolver.attack(c, t, {"name": "Bramble Lash", "bonus": Spellcasting.spell_attack_bonus(c), "kind": "melee", "weapon": false,
		"spell": true, "damage": [{"dice": dice, "damage_type": "piercing"}]}, U.grid(ctx).attack_context(c, t))
	if res.get("hit", false) and not t.dead:
		U.pull(ctx, t, U.grid(ctx).cell_of(c), 2)
	return {"ok": true, "hit": res.get("hit", false)}
