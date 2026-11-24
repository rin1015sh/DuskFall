extends "res://scripts/rules/effect_script.gd"
## 불과 물의 조화(4원소 3레벨, BG3): 전투 밖에서 행동, 기 최대치 절반(내림) 회복. 긴 휴식 1회.
func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	if not EventBus.realtime and ctx["world"].get("turns") != null and ctx["world"]["turns"].in_combat:
		return {"ok": false, "reason": "전투 밖에서만"}
	if not c.resources.has("focus"):
		return {"ok": false, "reason": "기가 없다"}
	var mx := int(c.resources["focus"]["max"])
	c.resources["focus"]["current"] = mini(mx, c.resource("focus") + mx / 2)
	return {"ok": true}
