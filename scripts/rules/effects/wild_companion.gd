extends "res://scripts/rules/effect_script.gd"
## 야생 동료(드루이드 2레벨, SRD): 행동, 야생 변신 1회(없으면 가장 낮은 주문 슬롯)로 재료 없이 사역마 찾기 —
## 사역마는 요정이고 긴 휴식에 사라진다(소환 script summon의 사역마와 같다).

const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Summon := preload("res://scripts/rules/effects/summon.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var w: Dictionary = ctx.get("world", {})
	if not w.has("grid"):
		return {"ok": false, "reason": "격자가 없다"}
	var pay: String = "wild_shape" if c.resource("wild_shape") > 0 else load("res://scripts/rules/reaction_queue.gd").lowest_slot(c, 1)
	if pay == "":
		return {"ok": false, "reason": "야생 변신도 주문 슬롯도 없다"}
	var spell := RulesDB.get_entry("spell", "find_familiar")
	var inst: Dictionary = Spellcasting.new_instance(w, c, spell, 1)
	var aim: Vector2i = w["grid"].cell_of(c)
	var r: Dictionary = Summon._creature({"self": c, "world": w, "instance": inst, "aim": aim, "spell": spell, "slot": 1}, "owl", true)
	if not r.get("ok", false):
		return r
	c.spend_resource(pay)
	r["summon"].creature_type = "fey"
	return {"ok": true, "summon": r["summon"]}
