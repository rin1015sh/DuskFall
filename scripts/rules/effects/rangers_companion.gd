extends "res://scripts/rules/effect_script.gd"
## 레인저의 동료(야수 조련사 3레벨, BG3): 행동, 짧은 휴식 1회. 설정 ranger_companion(곰·멧돼지·큰까마귀·늑대·늑대거미)을 부른다.
## 레벨 표(BG3): HP·AC는 3/5/8/11레벨 값, 5레벨부터 동료의 결속(AC·피해 + 숙련 — 표의 AC에 들어 있음, 피해는 명중 피해에 더함),
## 11레벨 야수의 분노(공격 2회). 큰까마귀는 난다. 이미 있으면 바꾼다. 긴 휴식까지.
const Summon := preload("res://scripts/rules/effects/summon.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const TABLE := {
	"bear": {"hp": [19, 39, 69, 99], "ac": [11, 15, 16, 18]},
	"boar": {"hp": [11, 27, 51, 85], "ac": [11, 14, 15, 17]},
	"dire_raven": {"hp": [13, 21, 32, 44], "ac": [16, 19, 19, 22]},
	"wolf": {"hp": [11, 31, 61, 91], "ac": [13, 16, 16, 21]},
	"wolf_spider": {"hp": [10, 24, 42, 60], "ac": [14, 18, 18, 21]},
}


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var w: Dictionary = ctx["world"]
	if not w.has("grid"):
		return {"ok": false, "reason": "격자가 없다"}
	var kind := str(c.options.get("ranger_companion", "wolf"))
	if not TABLE.has(kind):
		kind = "wolf"
	for o: Node in w["grid"].creatures():
		if o.has_meta("ranger_companion") and o.get_meta("summoner") == c:
			o.dead = true
			w["grid"].remove(o)  # 하나만
	var spell := RulesDB.get_entry("spell", "find_familiar")
	var inst: Dictionary = Spellcasting.new_instance(w, c, spell, 1)
	var r: Dictionary = Summon._creature({"self": c, "world": w, "instance": inst, "aim": w["grid"].cell_of(c), "spell": spell, "slot": 1},
		"companion_" + kind, kind == "dire_raven")
	if not r.get("ok", false):
		return r
	var m: Node = r["summon"]
	var lv: int = c.feature_level("rangers_companion")
	var tier := 3 if lv >= 11 else (2 if lv >= 8 else (1 if lv >= 5 else 0))
	m.hp_max = int(TABLE[kind]["hp"][tier])
	m.hp = m.hp_max
	m.ac_base = int(TABLE[kind]["ac"][tier])
	m.set_meta("ranger_companion", kind)
	if lv >= 5:
		m.set_meta("bonus_damage", c.proficiency_bonus)  # 동료의 결속: 피해 + 숙련
		m.proficiency_bonus = c.proficiency_bonus
	if lv >= 11:
		m.attacks_per_action = 2  # 야수의 분노
	return {"ok": true, "summon": m}
