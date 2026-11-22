extends "res://scripts/rules/effect_script.gd"
## Disguise Self(1레벨): 변장 — 대화 태그 disguised, 절도를 목격당해도 알아보지 못한다(5단계). 긴 휴식까지.

const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	U.set_until_end(ctx, c, "faction", c.faction)
	c.set_meta("disguised", true)
	U.on_end(ctx, func() -> void: c.remove_meta("disguised"))
	if not ctx["world"].has("dialogue_tags"):
		ctx["world"]["dialogue_tags"] = {}
	ctx["world"]["dialogue_tags"]["disguised"] = true
	return {"ok": true}
