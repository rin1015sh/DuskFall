extends "res://scripts/rules/effect_script.gd"
## 바람의 걸음(몽크 2레벨, SRD): 보너스 행동으로 질주. 기가 있으면 기 1로 질주 + 이탈 + 이번 턴 도약 거리 2배.


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	c.turn["movement"] = int(c.turn.get("movement", 0)) + c.speed()
	if c.resource("focus") > 0:
		c.spend_resource("focus")
		c.turn["disengaged"] = true
		c.extra_modifiers.append({"effect": {"type": "modify", "stat": "jump_tiles", "multiply": 2.0}, "source": "step_of_the_wind", "until_turn_start_of": c})
		Dice.log_text("%s 바람의 걸음: 질주 + 이탈 + 도약 2배" % c.label())
		return {"ok": true, "empowered": true}
	Dice.log_text("%s 바람의 걸음: 질주" % c.label())
	return {"ok": true}
