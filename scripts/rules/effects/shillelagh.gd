extends "res://scripts/rules/effect_script.gd"
## 마법 곤봉(Shillelagh, BG3 수치): 보너스 행동, 쥔 곤봉·육척봉이 10턴 동안 마법 무기 — 피해 1d8, 명중·피해에 시전 능력.
const U := preload("res://scripts/rules/spell_util.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var wid: String = c.weapon("main")
	if not wid in ["club", "quarterstaff"]:
		return {"ok": false, "reason": "곤봉이나 육척봉을 쥐어야 한다"}
	c.set_meta("shillelagh", {"weapon": wid, "ability": str(c.get_meta("casting_ability", "wis"))})
	U.on_end(ctx, func() -> void:
		if is_instance_valid(c):
			c.remove_meta("shillelagh"))
	ctx["instance"]["targets"].append(c)
	return {"ok": true}
