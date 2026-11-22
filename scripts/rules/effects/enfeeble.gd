extends "res://scripts/rules/effect_script.gd"
## Ray of Enfeeblement(SRD 5.2.1): 건강 내성. 실패 → 근력 d20 테스트 불리, 피해 굴림 −1d8, 턴 끝 반복 내성.
## 성공 → 시전자의 다음 턴 시작까지 다음 공격 불리.
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Area := preload("res://scripts/rules/area.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Node = ctx["world"]["grid"].creature_at(ctx["aim"])
	if t == null:
		return {"ok": false, "reason": "대상이 없다"}
	var dc := Spellcasting.spell_dc(c)
	var id: int = ctx["instance"]["id"]
	if Resolver.saving_throw(t, "con", dc, {"source": c})["success"]:
		t.extra_modifiers.append({"effect": {"type": "advantage", "roll": "attack", "side": "self", "value": "disadvantage"},
			"source": "ray_of_enfeeblement", "consume_on_attack": true, "until_turn_start_of": c})
		return {"ok": true, "saved": true}
	for e: Dictionary in [{"type": "advantage", "roll": "save", "side": "self", "value": "disadvantage", "ability": ["str"]},
			{"type": "advantage", "roll": "ability_check", "side": "self", "value": "disadvantage", "ability": ["str"]},
			{"type": "modify", "stat": "damage_roll", "add": "-1d8"}]:
		t.extra_modifiers.append({"effect": e, "source": "ray_of_enfeeblement", "instance": id, "turns_left": -1})
	t.apply_condition("enfeebled", -1, c, {"instance": id, "repeat_save": {"ability": "con", "dc": dc}})
	ctx["instance"]["targets"].append(t)
	return {"ok": true, "saved": false}
