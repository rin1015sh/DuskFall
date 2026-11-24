extends "res://scripts/rules/effect_script.gd"
## 강화 마법(야생 마법 6레벨, BG3): 행동, 근접(1칸) 안 나나 아군 — 기능 bolster: boon = 10턴 명중 +1d4(상태 bolstering_boon),
## 숫자 = 그 레벨 주문 슬롯 1개 회복(최대치까지). 긴 휴식, 숙련 보너스 회(자원 공유).
func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	if not (t is Node):
		t = c
	if t.dead or t.is_hostile_to(c) or (t != c and ctx["world"]["grid"].distance_between(c, t) > 1):
		return {"ok": false, "reason": "옆의 아군이나 나"}
	var kind := str(ctx.get("feature", {}).get("bolster", "boon"))
	if kind == "boon":
		t.apply_condition("bolstering_boon", 0, c)
		return {"ok": true}
	var rid := "spell_slot_" + kind
	if not t.resources.has(rid) or t.resource(rid) >= int(t.resources[rid].get("max", 0)):
		return {"ok": false, "reason": "회복할 %s레벨 슬롯이 없다" % kind}
	t.resources[rid]["current"] = t.resource(rid) + 1
	return {"ok": true}
