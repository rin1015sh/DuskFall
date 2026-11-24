extends "res://scripts/rules/effect_script.gd"
## 위엄의 명령(위엄의 망토 중): 보너스 행동으로 '명령' 주문을 슬롯 없이 시전한다.
func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	var w: Dictionary = ctx["world"]
	if not c.has_condition("mantle_of_majesty"):
		return {"ok": false, "reason": "위엄의 망토 중에만"}
	if not (t is Node):
		return {"ok": false, "reason": "대상을 골라야 한다"}
	return load("res://scripts/rules/spellcasting.gd").cast(w, c, "command", w["grid"].cell_of(t), {"free": true, "granted": true})
