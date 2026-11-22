extends "res://scripts/rules/effect_script.gd"
## Calm Emotions(2레벨, SRD): 반경 4칸 휴머노이드 매력 내성 실패 → 매혹·공포 해제, 적대였으면 무관심(중립)이 된다. 피해를 받으면 무관심이 끝난다.

const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var g := U.grid(ctx)
	var c: Node = ctx["self"]
	var count := 0
	for t: Node in U.creatures_in(ctx, U.circle(ctx, U.aim_cell(ctx), 4)):
		if t.dead or t.creature_type != "humanoid":
			continue
		if Resolver.saving_throw(t, "cha", U.dc(ctx))["success"]:
			continue
		t.remove_condition("charmed")
		t.remove_condition("frightened")
		if t.is_hostile_to(c):
			U.set_until_end(ctx, t, "team", "neutral")
			t.awareness.clear()
			U.end_when_damaged(ctx, t)
		count += 1
	if ctx["world"].get("turns") != null:
		ctx["world"]["turns"].check_end()
	return {"ok": true, "calmed": count}
