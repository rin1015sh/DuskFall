extends "res://scripts/rules/effect_script.gd"
## 맹세 신성 변환 — 대상 하나 내성 실패 시 상태(BG3): 기능 range_tiles·save(능력)·condition·turns, repeat_save면 턴 끝 다시 내성,
## save_disadvantage_types(그 종류는 내성 불리 — 적 물리치기: 악마·언데드). DC 8 + 숙련 + 매력.
## 자연의 분노(속박 10턴, 근력) / 적 물리치기(공포·이동 불가 3턴, 지혜) / 앙심 어린 고통(정신, 매 턴 1d4 + 매력 사령·공격받을 때 유리 3턴, 매력).
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	var f: Dictionary = ctx.get("feature", {})
	var grid: Node = ctx["world"]["grid"]
	if not (t is Node) or t.dead or not t.is_hostile_to(c):
		return {"ok": false, "reason": "적을 골라야 한다"}
	if grid.distance_between(c, t) > int(f.get("range_tiles", 12)):
		return {"ok": false, "reason": "%d칸 안" % int(f.get("range_tiles", 12))}
	var dc: int = 8 + c.proficiency_bonus + c.ability_mod("cha")
	var ab := str(f.get("save", "wis"))
	var opts := {"source": c}
	if str(t.creature_type) in f.get("save_disadvantage_types", []):
		opts["disadvantage"] = ["종류"]
	if Resolver.saving_throw(t, ab, dc, opts)["success"]:
		return {"ok": true, "applied": false}
	var p := {}
	if f.get("repeat_save", false):
		p["repeat_save"] = {"ability": ab, "dc": dc}
	if f.has("dot_dice"):
		p["dice"] = "1d4%+d" % c.ability_mod("cha") if c.ability_mod("cha") != 0 else "1d4"
	t.apply_condition(str(f["condition"]), int(f.get("turns", 3)), c, p)
	return {"ok": true, "applied": true}
