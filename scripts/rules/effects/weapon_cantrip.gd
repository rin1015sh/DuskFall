extends "res://scripts/rules/effect_script.gd"
## True Strike(SRD 5.2.1): 주문에 쓴 무기로 공격 1회, 명중·피해에 주문 시전 능력. 피해는 광휘 또는 무기 유형(opts.choice).
## 5레벨부터 광휘 1d6 추가.
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Area := preload("res://scripts/rules/area.gd")


func is_implemented() -> bool:
	return true


const Combat := preload("res://scripts/rules/combat.gd")


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var world: Dictionary = ctx["world"]
	var t: Node = world["grid"].creature_at(ctx["aim"])
	if t == null:
		return {"ok": false, "reason": "대상이 없다"}
	var wid: String = c.weapon("main")
	var atk := Combat.build_weapon_attack(c, wid)
	var mod := Spellcasting.spell_mod(c)
	atk["bonus"] = int(atk["bonus"]) - int(atk["ability_mod"]) + mod
	var w := Combat.weapon_data(wid)
	var dtype: String = "radiant" if ctx["opts"].get("choice", "radiant") == "radiant" else w["damage_type"]
	atk["damage"] = [{"dice": "%s%+d" % [w["damage"], mod] if mod != 0 else w["damage"], "damage_type": dtype}]
	if c.level >= 5:
		atk["damage"].append({"dice": Spellcasting.scaled_dice(c, ctx["spell"], "1d6", 0), "damage_type": "radiant"})
	var ctxa := Combat.attack_context(world, c, t, atk)
	if ctxa.has("invalid"):
		return {"ok": false, "reason": ctxa["invalid"]}
	var r := Resolver.attack(c, t, atk, ctxa)
	return {"ok": true, "hit": r["hit"]}
