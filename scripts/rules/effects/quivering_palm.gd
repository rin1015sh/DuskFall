extends "res://scripts/rules/effect_script.gd"
## 진동하는 손바닥(열린 손 17레벨, SRD): 비무장 명중 + 기 4 → 진동. 끝내면 건강 내성, 실패 10d12 역장(성공 절반).
## 1차: 설정을 켜 두면 비무장 명중 때 바로 끝낸다(원문: 나중에 행동 또는 공격 하나를 포기 — 같은 턴 공격 행동 안에서 바로 쓰는 것과 같게 본다).

const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var res: Dictionary = ctx["res"]
	var t: Variant = res.get("target")
	if res.get("attacker") != c or not (t is Node) or t.dead or str(c.options.get("quivering_palm", "off")) != "on":
		return {"ok": false}
	if str(res.get("attack", {}).get("weapon_id", "")) != "unarmed" or c.resource("focus") < 4 or c.turn.get("palm_used", false):
		return {"ok": false}
	for i in 4:
		c.spend_resource("focus")
	c.turn["palm_used"] = true
	c.options["quivering_palm"] = "off"
	var dc: int = 8 + c.ability_mod("wis") + c.proficiency_bonus
	Resolver.save_effect([t], {"ability": "con", "dc": dc}, [{"type": "damage", "dice": "10d12", "damage_type": "force"}],
		[{"type": "damage", "dice": "10d12", "damage_type": "force", "scale": 0.5}], {"source": c})
	return {"ok": true}
