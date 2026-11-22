extends "res://scripts/rules/effect_script.gd"
## Ice Knife(SRD): 원거리 주문 공격 1d10 관통. 맞든 빗나가든 대상 칸에서 터져 반경 1칸 민첩 내성 2d6 냉기(슬롯마다 +1d6).
## 폭발은 범위라 칸 반응(냉기 → 물이 얼음, 4단계)이 있다.
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Area := preload("res://scripts/rules/area.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var world: Dictionary = ctx["world"]
	var grid: Node = world["grid"]
	var t: Node = grid.creature_at(ctx["aim"])
	if t != null:
		Resolver.attack(c, t, {"name": "Ice Knife", "bonus": Spellcasting.spell_attack_bonus(c), "kind": "ranged", "weapon": false,
			"damage": [{"dice": "1d10", "damage_type": "piercing"}]}, grid.attack_context(c, t))
	var cells := Area.circle(grid, ctx["aim"], 1)
	var dice := Spellcasting.scaled_dice(c, ctx["spell"], "2d6", int(ctx["slot"]))
	var rolled := {}
	Resolver.save_effect(Area.creatures_in(grid, cells).filter(func(o: Node) -> bool: return not o.dead),
		{"ability": "dex", "dc": Spellcasting.spell_dc(c)}, [{"type": "damage", "dice": dice, "damage_type": "cold"}], [],
		{"source": c, "rolled": rolled})
	var amount := 0
	for k: String in rolled.keys():
		amount = maxi(amount, int(rolled[k]))
	if world.get("surfaces") != null:
		world["surfaces"].tile_damage(cells, "cold", amount, c)
	return {"ok": true}
