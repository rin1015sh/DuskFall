extends "res://scripts/rules/effect_script.gd"
## Enlarge/Reduce(2레벨, SRD): 원치 않으면 건강 내성. 확대(opts.mode=enlarge, 기본): 무기 피해 +1d4, 근력 판정·내성 유리, 무게 ×2(밀치기·던지기). 축소: 무기 피해 −1d4, 근력 판정·내성 불리, 무게 ÷2. 칸 크기 변경은 1차 생략.

const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var t := U.target(ctx)
	if t == null:
		return {"ok": false, "reason": "대상이 없다"}
	if t.is_hostile_to(ctx["self"]) and Resolver.saving_throw(t, "con", U.dc(ctx))["success"]:
		return {"ok": true, "saved": true}
	var enlarge: bool = ctx.get("opts", {}).get("mode", "enlarge" if not t.is_hostile_to(ctx["self"]) else "reduce") == "enlarge"
	var id: int = ctx["instance"]["id"]
	var v := "advantage" if enlarge else "disadvantage"
	for roll: String in ["saving_throw", "ability_check"]:
		t.extra_modifiers.append({"effect": {"type": "advantage", "roll": roll, "side": "self", "value": v, "ability": ["str"]}, "instance": id, "source": "spell"})
	var rider := {"when": "always", "expr_add": "+1d4" if enlarge else "-1d4", "instance": id}
	t.attack_riders.append(rider)
	U.on_end(ctx, func() -> void:
		if is_instance_valid(t):
			t.attack_riders.erase(rider))
	U.set_until_end(ctx, t, "weight_kg", t.weight_kg * (2.0 if enlarge else 0.5))
	if not t in ctx["instance"]["targets"]:
		ctx["instance"]["targets"].append(t)
	return {"ok": true, "enlarge": enlarge}
