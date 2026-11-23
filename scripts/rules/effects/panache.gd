extends "res://scripts/rules/effect_script.gd"
## 허세(스워시버클러형 9레벨, BG3): 행동. 12칸 안 인간형과 설득 대 통찰 겨루기. 적이 지면 10턴 동안
## 나 아닌 생물을 노린 공격이 불리(허세에 홀림), 적이 아니면 10턴 동안 매혹. 피해를 받으면 풀린다.
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	var world: Dictionary = ctx["world"]
	if not (t is Node) or t.dead or t == c:
		return {"ok": false, "reason": "대상을 골라야 한다"}
	if world.has("grid") and world["grid"].distance_between(c, t) > 12:
		return {"ok": false, "reason": "너무 멀다"}
	if str(t.creature_type) != "humanoid":
		return {"ok": false, "reason": "인간형만"}
	var mine: int = Resolver.ability_check(c, "cha", 0, {"skill": "persuasion"})["total"]
	var theirs: int = Resolver.ability_check(t, "wis", 0, {"skill": "insight"})["total"]
	if mine <= theirs:
		Dice.log_text("%s 허세: %s가 넘어가지 않았다(%d 대 %d)" % [c.label(), t.label(), mine, theirs])
		return {"ok": true, "success": false}
	if c.is_hostile_to(t):
		t.apply_condition("panache_goaded", 10, c)
	else:
		t.apply_condition("charmed", 10, c)
	t.set_meta("end_on_damage", ["panache_goaded", "charmed"])
	Dice.log_text("%s 허세: %s가 넘어갔다(%d 대 %d)" % [c.label(), t.label(), mine, theirs])
	return {"ok": true, "success": true}
