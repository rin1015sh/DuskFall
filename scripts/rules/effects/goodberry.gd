extends "res://scripts/rules/effect_script.gd"
## 좋은열매(SRD 5.2.1 Goodberry, 레인저 1레벨): 좋은열매 10개를 공용 소지품에 만든다.
## 열매는 아이템 데이터(goodberry: 보너스 행동으로 먹으면 HP 1, expires long_rest — 긴 휴식에 사라짐).

const Interact := preload("res://scripts/rules/interact.gd")
const COUNT := 10


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var w: Dictionary = ctx.get("world", {})
	Interact.give(w, "goodberry", COUNT)
	Dice.log_text("%s: 좋은열매 %d개" % [ctx["self"].label(), COUNT])
	return {"ok": true}
