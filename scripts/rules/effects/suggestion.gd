extends "res://scripts/rules/effect_script.gd"
## Suggestion(2레벨, SRD): 지혜 내성 실패 → 매혹. 전투 중 적이면 '싸움을 멈추고 떠나라' — 중립이 되어 전투에서 빠진다. 피해를 받으면 끝난다. 탐험 중에는 대화 태그 suggested.

const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var t := U.target(ctx)
	if t == null:
		return {"ok": false, "reason": "대상이 없다"}
	if Resolver.saving_throw(t, "wis", U.dc(ctx))["success"]:
		return {"ok": true, "saved": true}
	U.add_condition(ctx, t, "charmed")
	U.end_when_damaged(ctx, t)
	var w: Dictionary = ctx["world"]
	if t.is_hostile_to(ctx["self"]):
		U.set_until_end(ctx, t, "team", "neutral")
		t.awareness.clear()
		if w.get("turns") != null and w["turns"].in_combat:
			w["turns"].leave(t)
	if not w.has("dialogue_tags"):
		w["dialogue_tags"] = {}
	w["dialogue_tags"]["suggested"] = true
	return {"ok": true}
