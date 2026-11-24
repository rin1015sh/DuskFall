extends "res://scripts/rules/effect_script.gd"
## 위협적인 존재감(광전사 10레벨, BG3): 행동, 6칸(9m) 안 적 하나 지혜 내성(DC 8 + 숙련 + 매력) 실패 시 2턴 공포.
## 위협 유지(보너스 행동 — 기능 maintain_intimidation)는 내성 없이 1턴 늘린다.
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	var grid: Node = ctx["world"]["grid"]
	if not (t is Node) or t.dead or not t.is_hostile_to(c):
		return {"ok": false, "reason": "적을 골라야 한다"}
	if grid.distance_between(c, t) > 6:
		return {"ok": false, "reason": "6칸 안"}
	if ctx.get("feature", {}).get("maintain", false):
		var inst: Dictionary = t.condition_instance("frightened")
		if inst.is_empty() or inst.get("source") != c:
			return {"ok": false, "reason": "내가 건 공포가 없다"}
		inst["turns_left"] = int(inst["turns_left"]) + 1
		return {"ok": true}
	var dc: int = 8 + c.proficiency_bonus + c.ability_mod("cha")
	if not Resolver.saving_throw(t, "wis", dc, {"source": c})["success"]:
		t.apply_condition("frightened", 2, c)
		return {"ok": true, "frightened": true}
	return {"ok": true, "frightened": false}
