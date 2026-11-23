extends "res://scripts/rules/effect_script.gd"
## 신성한 불꽃(클레릭 2레벨 신성 변환, SRD): 6칸 안 보이는 생물. 1d8(7레벨 2d8) + 지혜 수정치.
## opts.mode = "heal"이면 회복, 아니면 건강 내성(실패 전부·성공 절반) 광휘 피해(opts.damage_type로 사령 선택).

const Resolver := preload("res://scripts/rules/resolver.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const RANGE := 6


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Node = ctx.get("target")
	var w: Dictionary = ctx.get("world", {})
	if t == null or t.dead:
		return {"ok": false, "reason": "대상이 없다"}
	if w.has("grid") and (w["grid"].distance_between(c, t) > RANGE or not w["grid"].can_see(c, t)):
		return {"ok": false, "reason": "6칸 안 보이는 대상만"}
	var dice := "2d8" if c.feature_level("divine_spark") >= 7 else "1d8"
	var total: int = Dice.roll(dice, "신성한 불꽃")["total"] + c.ability_mod("wis")
	var opts: Dictionary = ctx.get("opts", {})
	if opts.get("mode", "damage") == "heal":
		Resolver.heal(t, total, c)
	else:
		var dtype: String = opts.get("damage_type", "radiant")
		Resolver.save_effect([t], {"ability": "con", "dc": Spellcasting.spell_dc(c)},
			[{"type": "damage", "dice": str(total), "damage_type": dtype}],
			[{"type": "damage", "dice": str(total), "damage_type": dtype, "scale": 0.5}], {"source": c})
	return {"ok": true, "amount": total}
