extends "res://scripts/rules/effect_script.gd"
## Counterspell(SRD): 반응. 12칸 안 시전하는 생물이 건강 내성, 실패하면 그 주문이 사라지고 슬롯은 쓰지 않는다.
## ReactionQueue가 on_spell_cast에서 반응 창을 열고 opts.cast_ctx로 넘긴다.
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Area := preload("res://scripts/rules/area.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var cast_ctx: Dictionary = ctx["opts"].get("cast_ctx", {})
	if cast_ctx.is_empty():
		return {"ok": false, "reason": "끊을 주문이 없다"}
	var caster: Node = cast_ctx["caster"]
	var s := Resolver.saving_throw(caster, "con", Spellcasting.spell_dc(ctx["self"]), {"source": ctx["self"]})
	if not s["success"]:
		cast_ctx["countered"] = true
	return {"ok": true, "countered": not s["success"]}
