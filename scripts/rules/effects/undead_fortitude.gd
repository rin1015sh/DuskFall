extends "res://scripts/rules/effect_script.gd"
## 언데드의 끈기(좀비, SRD): 피해로 0 HP가 되면 건강 내성 DC 5 + 받은 피해. 광휘 피해나 치명타면 안 된다.
## 성공하면 HP 1로 버틴다.

const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var info: Dictionary = ctx["res"]
	if info.get("prevented", false):
		return {"ok": false}
	var opts: Dictionary = info.get("opts", {})
	if opts.get("crit", false) or c.get_meta("last_damage_types", []).has("radiant"):
		return {"ok": false}
	var taken: int = int(c.get_meta("last_damage_total", 0))
	var s := Resolver.saving_throw(c, "con", 5 + taken)
	if s["success"]:
		c.hp = 1
		info["prevented"] = true
		Dice.log_text("%s 언데드의 끈기: HP 1" % c.label())
	return {"ok": s["success"]}
