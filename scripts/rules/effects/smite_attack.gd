extends "res://scripts/rules/effect_script.gd"
## 강타 주문(BG3 수치 — 신성한 강타·타오르는 강타·빛나는 강타·얽어매는 일격): 시전 = 근접 무기 공격 하나.
## 비용 "attack"은 공격 행동의 공격 하나다(첫 공격이면 행동을 쓰고 추가 공격이 남는다 — Combat.attack).
## 시전자에게 주문 데이터 effects.apply의 '준비' 상태를 걸고 바로 공격한다. 맞히면 준비 상태의 on_weapon_hit이 발동하고,
## 빗나가면 준비 상태를 지우고 주문(집중 포함)을 끝낸다.
const U := preload("res://scripts/rules/spell_util.gd")
const Combat := preload("res://scripts/rules/combat.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Node = U.target(ctx)
	if t == null or t == c:
		return {"ok": false, "reason": "대상이 없다"}
	var ready_id := ""
	for e: Dictionary in ctx["spell"].get("effects", {}).get("apply", []):
		if e.get("type") == "apply_condition":
			ready_id = str(e["id"])
	if ready_id != "":
		U.add_condition(ctx, c, ready_id)
	var aopts := {"weapon": ctx["opts"]["weapon"]} if ctx["opts"].has("weapon") else {}  # 기본은 주무기
	var res := Combat.attack(ctx["world"], c, t, aopts)
	if c.has_condition(ready_id):  # 빗나감(발동하지 않음)
		c.remove_condition(ready_id)
		if not res.get("hit", false):
			if int(c.concentration.get("instance", -1)) == int(ctx["instance"]["id"]):
				c.break_concentration("강타 빗나감")
			load("res://scripts/rules/spellcasting.gd").end_instance(int(ctx["instance"]["id"]))
	return {"ok": res.get("ok", true), "hit": res.get("hit", false), "attack": res}
