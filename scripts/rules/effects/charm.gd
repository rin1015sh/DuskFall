extends "res://scripts/rules/effect_script.gd"
## Charm Person(1레벨, SRD): 휴머노이드 지혜 내성(싸우는 중이면 유리), 실패하면 매혹(시전자를 공격할 수 없음) + 대화 태그 charmed. 피해를 받으면 끝난다.

const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var t := U.target(ctx)
	if t == null or t.creature_type != "humanoid":
		return {"ok": false, "reason": "휴머노이드만"}
	var fighting: bool = ctx["world"].get("turns") != null and ctx["world"]["turns"].in_combat
	var s := Resolver.saving_throw(t, "wis", U.dc(ctx), {"advantage": ["싸우는 중"] if fighting else []})
	if s["success"]:
		return {"ok": true, "saved": true}
	U.add_condition(ctx, t, "charmed")
	U.end_when_damaged(ctx, t)
	if not ctx["world"].has("dialogue_tags"):
		ctx["world"]["dialogue_tags"] = {}
	ctx["world"]["dialogue_tags"]["charmed"] = true
	return {"ok": true}
