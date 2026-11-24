extends "res://scripts/rules/effect_script.gd"
## 기 공명: 주먹(열린 손 9레벨, BG3): 행동(또는 보너스 행동 판 — 기능 kind), 비무장 공격 — 맞으면 10턴 '기 공명'(내가 터뜨릴 수 있다).
const Combat := preload("res://scripts/rules/combat.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	if not (t is Node) or t.dead or not t.is_hostile_to(c):
		return {"ok": false, "reason": "적을 골라야 한다"}
	if t.has_condition("resonating_ki"):
		return {"ok": false, "reason": "이미 공명 중"}
	var atk := Combat.build_weapon_attack(c, "unarmed")
	atk["name"] = "기 공명: 주먹"
	var r := Combat._do_attack(ctx["world"], c, t, atk)
	if not r.get("ok", true):
		return r
	if r.get("hit", false) and not t.dead:
		t.apply_condition("resonating_ki", 10, c)
	r["ok"] = true
	return r
