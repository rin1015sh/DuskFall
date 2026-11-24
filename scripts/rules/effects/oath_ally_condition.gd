extends "res://scripts/rules/effect_script.gd"
## 맹세 신성 변환 — 나나 아군 하나에게 상태(BG3): 기능 range_tiles·condition·turns. 심문관의 힘은 params.hit_dice = 팔라딘 매력(최소 1).
## 심문관의 힘(복수, 2턴 무기 + 매력 광휘·멍함) / 올바른 명료함(왕관, 10턴 명중 + 숙련).
func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	var f: Dictionary = ctx.get("feature", {})
	if not (t is Node):
		t = c
	if t.dead or t.is_hostile_to(c) or (t != c and ctx["world"]["grid"].distance_between(c, t) > int(f.get("range_tiles", 12))):
		return {"ok": false, "reason": "범위 안 나나 아군"}
	t.apply_condition(str(f["condition"]), int(f.get("turns", 10)), c, {"hit_dice": str(maxi(1, c.ability_mod("cha"))), "bonus": c.proficiency_bonus})
	return {"ok": true}
