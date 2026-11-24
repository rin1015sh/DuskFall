extends "res://scripts/rules/effect_script.gd"
## 폭풍 화살(자체 이름, BG3 수치): 원거리 주문 공격 4d8 번개(빗나가면 절반). 그 뒤 대상 둘레 반경 2칸(3m) 다른 생물 민첩 내성 2d8 번개, 성공 절반.
## 상위 슬롯마다 둘 다 +1d8.
const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Area := preload("res://scripts/rules/area.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var g := U.grid(ctx)
	var t: Node = U.target(ctx)
	if t == null or t == c:
		return {"ok": false, "reason": "대상이 없다"}
	var extra := maxi(0, int(ctx["slot"]) - 3)
	var main := "%dd8" % (4 + extra)
	var res := Resolver.attack(c, t, {"name": "Storm Arrow", "bonus": Spellcasting.spell_attack_bonus(c), "kind": "ranged", "weapon": false,
		"spell": true, "damage": [{"dice": main, "damage_type": "lightning"}]}, g.attack_context(c, t))
	if not res.get("hit", false) and not t.dead:
		Resolver.apply_damage(t, [{"amount": Dice.roll(main, "폭풍 화살(빗나감)")["total"] / 2, "damage_type": "lightning"}], {"attacker": c})
	var burst := "%dd8" % (2 + extra)
	var others := Area.creatures_in(g, Area.circle(g, g.cell_of(t), 2)).filter(func(o: Node) -> bool: return o != t and o != c and not o.dead)
	Resolver.save_effect(others, {"ability": "dex", "dc": U.dc(ctx)}, [{"type": "damage", "dice": burst, "damage_type": "lightning"}],
		[{"type": "damage", "dice": burst, "damage_type": "lightning", "scale": 0.5}], {"source": c})
	return {"ok": true, "hit": res.get("hit", false)}
