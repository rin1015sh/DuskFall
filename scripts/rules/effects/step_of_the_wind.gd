extends "res://scripts/rules/effect_script.gd"
## 바람의 걸음(몽크 2레벨, BG3): 보너스 행동 + 기 1 — 기능 mode dash = 질주(이동 두 배, 이번 턴 도약에 보너스 행동 없음 — 도약 거리 2배로 대신),
## disengage = 이탈.
func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	if str(ctx.get("feature", {}).get("mode", "dash")) == "disengage":
		c.turn["disengaged"] = true
		return {"ok": true}
	c.turn["movement"] = int(c.turn.get("movement", 0)) + c.speed()
	c.turn["dashed"] = true
	c.extra_modifiers.append({"effect": {"type": "modify", "stat": "jump_tiles", "multiply": 2.0}, "source": "step_of_the_wind", "until_turn_start_of": c})
	return {"ok": true}
