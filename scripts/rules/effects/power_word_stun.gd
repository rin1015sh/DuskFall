extends "res://scripts/rules/effect_script.gd"
## Power Word Stun(SRD 8레벨): 내성 없이 — 대상 HP 150 이하면 기절(턴 끝 건강 내성으로 끝), 아니면 다음 내 턴 시작까지 속도 0.

const Spellcasting := preload("res://scripts/rules/spellcasting.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Node = ctx["world"]["grid"].creature_at(ctx["aim"])
	if t == null or t.dead:
		return {"ok": false, "reason": "대상이 없다"}
	if t.hp <= 150:
		t.apply_condition("stunned", -1, c, {"repeat_save": {"ability": "con", "dc": Spellcasting.spell_dc(c)}})
		return {"ok": true, "stunned": true}
	t.extra_modifiers.append({"effect": {"type": "modify", "stat": "speed_tiles", "add": -99}, "source": "power_word_stun", "until_turn_start_of": c})
	return {"ok": true, "stunned": false}
