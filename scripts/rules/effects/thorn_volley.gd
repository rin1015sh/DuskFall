extends "res://scripts/rules/effect_script.gd"
## 가시 세례(자체 이름, BG3 수치): 원거리 무기 공격 하나(행동). 맞든 빗나가든 대상 칸에서 터져 반경 1칸(2m) 민첩 내성 1d10 관통(+1d10/슬롯), 성공 절반.
const U := preload("res://scripts/rules/spell_util.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Area := preload("res://scripts/rules/area.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var g := U.grid(ctx)
	var t: Node = U.target(ctx)
	var wid: String = c.weapon("main")
	if wid == "" or not Combat.is_ranged_weapon(Combat.weapon_data(wid)):
		return {"ok": false, "reason": "원거리 무기가 필요하다"}
	var res := {}
	if t != null and t != c:
		res = Combat._do_attack(ctx["world"], c, t, Combat.build_weapon_attack(c, wid))
	var dice := Spellcasting.damage_dice(c, ctx["spell"], "1d10", int(ctx["slot"]), "piercing")
	var cells := Area.circle(g, U.aim_cell(ctx), 1)
	Resolver.save_effect(Area.creatures_in(g, cells).filter(func(o: Node) -> bool: return not o.dead and o != c),
		{"ability": "dex", "dc": U.dc(ctx)}, [{"type": "damage", "dice": dice, "damage_type": "piercing"}],
		[{"type": "damage", "dice": dice, "damage_type": "piercing", "scale": 0.5}], {"source": c})
	return {"ok": true, "hit": res.get("hit", false)}
