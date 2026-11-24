extends "res://scripts/rules/effect_script.gd"
## 불길한 징조의 사냥개(그림자 마법 6레벨, BG3): 보너스 행동 + 마법 점수 3, 짧은 휴식 1회. 12칸 안 적 옆에 사냥개를 부르고
## 그 적은 사냥개가 있는 동안(10턴) 내 주문 내성 불리(상태 ill_omen). 사냥개 임시 HP = 소서러 레벨 절반.
const Summon := preload("res://scripts/rules/effects/summon.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	var w: Dictionary = ctx["world"]
	if not (t is Node) or t.dead or not t.is_hostile_to(c) or w["grid"].distance_between(c, t) > 12:
		return {"ok": false, "reason": "12칸 안 적"}
	if c.resource("sorcery_points") < 3:
		return {"ok": false, "reason": "마법 점수 3이 필요하다"}
	var spell := RulesDB.get_entry("spell", "find_familiar")
	var inst: Dictionary = Spellcasting.new_instance(w, c, spell, 1)
	var r: Dictionary = Summon._creature({"self": c, "world": w, "instance": inst, "aim": w["grid"].cell_of(t), "spell": spell, "slot": 1}, "hound_of_ill_omen", false)
	if not r.get("ok", false):
		return r
	c.spend_resource("sorcery_points", 3)
	r["summon"].temp_hp = c.feature_level("hound_of_ill_omen") / 2
	r["summon"].set_meta("summon_until", "turns")
	t.apply_condition("ill_omen", 10, c)
	return {"ok": true, "summon": r["summon"]}
