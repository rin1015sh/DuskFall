extends "res://scripts/rules/effect_script.gd"
## 재생(트롤, SRD): 턴 시작마다 HP 15 회복. 산·화염 피해를 받으면 다음 턴에는 재생하지 않는다.
## 트롤은 0 HP로 턴을 시작하고 재생하지 못할 때만 죽는다 → 0 HP가 되면 즉사 대신 쓰러져 있다가
## 턴 시작(Resolver.start_turn → regeneration_turn_start)에 재생하거나 죽는다.


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var info: Dictionary = ctx["res"]
	if info.get("prevented", false):
		return {"ok": false}
	info["prevented"] = true
	c.hp = 0
	c.apply_condition("unconscious", -1, "regeneration")
	c.set_meta("regen_down", true)
	Dice.log_text("%s 쓰러졌지만 아직 재생할 수 있다" % c.label())
	return {"ok": true}
