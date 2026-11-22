extends "res://scripts/rules/effect_script.gd"
## 끈질긴 인내(오크, SRD): 0 HP가 되었지만 즉사가 아니면 HP 1로 버틴다. 긴 휴식 1회.


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var info: Dictionary = ctx["res"]
	if info.get("prevented", false) or c.resource("relentless_endurance") <= 0:
		return {"ok": false}
	if int(info.get("remainder", 0)) >= c.hp_max and c.is_player_character:
		return {"ok": false}  # 즉사
	c.spend_resource("relentless_endurance")
	c.hp = 1
	info["prevented"] = true
	Dice.log_text("%s 끈질긴 인내: HP 1" % c.label())
	return {"ok": true}
