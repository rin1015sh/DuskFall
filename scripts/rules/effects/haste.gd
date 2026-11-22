extends "res://scripts/rules/effect_script.gd"
## Haste(SRD): 보이는 자발적 생물 하나. 속도 2배, AC +2, 민첩 내성 유리, 턴마다 추가 행동(공격 1회·질주·이탈·숨기·활용).
## 주문이 끝나면 대상은 다음 턴 끝까지 무력화·속도 0.
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Area := preload("res://scripts/rules/area.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var grid: Node = ctx["world"]["grid"]
	var t: Node = grid.creature_at(ctx["aim"])
	if t == null:
		return {"ok": false, "reason": "대상이 없다"}
	var inst: Dictionary = ctx["instance"]
	var id: int = inst["id"]
	for e: Dictionary in [{"type": "modify", "stat": "speed_tiles", "add": t.speed_tiles}, {"type": "modify", "stat": "ac", "add": 2},
			{"type": "advantage", "roll": "save", "side": "self", "value": "advantage", "ability": ["dex"]},
			{"type": "grant_action", "action": "haste_action"}]:
		t.extra_modifiers.append({"effect": e, "source": "haste", "instance": id, "turns_left": -1})
	inst["targets"].append(t)
	inst["on_end"] = func() -> void:
		if is_instance_valid(t) and not t.dead:
			t.apply_condition("incapacitated", 1, "haste_lethargy")
			t.extra_modifiers.append({"effect": {"type": "modify", "stat": "speed_tiles", "add": -99}, "source": "haste_lethargy", "turn_ends_left": 1})
	return {"ok": true}
