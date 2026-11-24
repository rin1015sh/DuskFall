extends "res://tests/test_case.gd"
## 기본 클래스 기능 BG3 개편(changes.md 2026-11-24) — 클래스마다 더한다.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Features := preload("res://scripts/rules/features.gd")


func _pc(cls: String, lv: int, extra: Dictionary = {}) -> Node:
	var spec := Builder.default_spec(cls, lv)
	spec.merge(extra, true)
	var r := Builder.build(spec)
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func test_fighter() -> void:
	var f := _pc("fighter", 5)
	assert_false(f.feature_data.has("tactical_mind") or f.feature_data.has("tactical_shift"), "전술적 판단·이동 없음")


func test_bard() -> void:
	var b := _pc("bard", 2)
	assert_eq(b.resources["bardic_inspiration"]["max"], 3, "영감 3회")
	assert_eq(int(b.skill_bonuses["persuasion"]), b.proficiency_bonus, "전문화는 3레벨부터")
	var b3 := _pc("bard", 3)
	assert_eq(int(b3.skill_bonuses["persuasion"]), b3.proficiency_bonus * 2)
	var w := make_world(["...."])
	w["grid"].place(b, Vector2i(0, 0))
	w["party"] = [b]
	b.hp = 1
	b.reset_turn()
	var r: Dictionary = Features.use(w, b, "song_of_rest")
	assert_true(r.get("ok", false), str(r))
	assert_eq(b.resource("song_of_rest"), 0)


func test_cleric() -> void:
	var c := _pc("cleric", 6)
	assert_eq(c.resources["channel_divinity"]["max"], 2, "6레벨 신성 변환 2회")
	assert_false(c.feature_data.has("divine_order") or c.feature_data.has("divine_spark"))
	var u := make_creature({"team": "enemy", "hp_max": 60, "creature_type": "undead", "abilities": {"wis": 1}})
	var w := make_world(["......"])
	w["grid"].place(c, Vector2i(0, 0))
	w["grid"].place(u, Vector2i(2, 0))
	c.reset_turn()
	Dice.force([1, 3, 3, 3, 3])
	assert_true(Features.use(w, c, "turn_undead")["ok"])
	assert_eq(u.hp, 48, "언데드 파괴 4d6")
	assert_true(u.has_condition("frightened"))


func test_druid_forms_and_wild_strike() -> void:
	var d := _pc("druid", 10)
	var forms: Array = load("res://scripts/rules/effects/wild_shape.gd").forms_for(d)
	assert_true("crested_saurian" in forms and "panther" in forms and "giant_badger" in forms, "BG3 형태")
	var w := make_world(["......"])
	var e := make_creature({"team": "enemy", "hp_max": 200, "ac_base": 1})
	w["grid"].place(d, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(1, 0))
	d.reset_turn()
	d.options["wild_shape_form"] = "panther"
	assert_true(Features.use(w, d, "wild_shape")["ok"])
	assert_eq(d.hp_max, 45 + 10, "표범 45 + 2레벨마다 5")
	d.reset_turn()
	Dice.force([15, 3, 3])
	load("res://scripts/rules/combat.gd").attack(w, d, e)
	assert_eq(int(d.turn["attacks_left"]), 2, "향상된 야생의 일격: 3회 중 1회")


func test_monk() -> void:
	var m := _pc("monk", 1)
	assert_eq(m.resources["focus"]["max"], 2, "기 = 레벨 + 1")
	assert_true(m.feature_data.has("flurry_of_blows"), "1레벨 연타")
	var m9 := _pc("monk", 9)
	assert_eq(load("res://scripts/rules/combat.gd").martial_arts_die(m9), "1d8")
	assert_eq(load("res://scripts/rules/combat.gd").jump_distance(m9) >= 7, true, "고급 맨몸 이동 도약 +4칸")


func test_rogue_sorcerer_wizard() -> void:
	var r := _pc("rogue", 11)
	assert_true(r.has_cap("reliable_talent") and not r.feature_data.has("cunning_strike") and not r.feature_data.has("steady_aim"))
	assert_false(_pc("rogue", 10).has_cap("reliable_talent"), "믿음직한 재능 11레벨")
	var s := _pc("sorcerer", 3)
	assert_false(s.feature_data.has("innate_sorcery"))
	assert_true(s.has_cap("metamagic_heightened"), "3레벨 변형 3개")
	var wz := _pc("wizard", 5)
	assert_false(wz.feature_data.has("scholar") or wz.feature_data.has("memorize_spell"))


func test_paladin() -> void:
	var p := _pc("paladin", 1)
	assert_eq(p.resources["lay_on_hands"]["max"], 3)
	assert_true(p.feature_data.has("divine_sense"), "1레벨 신성 감지")
	var u := make_creature({"team": "enemy", "hp_max": 60, "creature_type": "undead"})
	var w := make_world(["...."])
	w["grid"].place(p, Vector2i(0, 0))
	w["grid"].place(u, Vector2i(1, 0))
	p.reset_turn()
	assert_true(Features.use(w, p, "divine_sense")["ok"])
	var ctx: Dictionary = load("res://scripts/rules/combat.gd").attack_context(w, p, u, {"kind": "melee"})
	assert_true("신성 감지" in ctx["advantage"])
	p.hp = 2
	p.reset_turn()
	assert_true(Features.use(w, p, "lay_on_hands", p)["ok"])
	assert_eq(p.hp, 4, "레벨 × 2")


func test_ranger() -> void:
	var r := _pc("ranger", 10, {"favoured_enemy": "bounty_hunter", "natural_explorer": "wasteland_cold"})
	assert_true(r.skill_bonuses.has("investigation") and r.has_cap("bounty_hunter"))
	assert_true("cold" in r.damage_resistances)
	assert_true(r.has_cap("ignore_difficult_terrain"), "대지 걸음")
	assert_false(r.feature_data.has("tireless") or r.feature_data.has("roving"))


func test_default_armor_fits_subclass() -> void:
	var life := _pc("cleric", 3)
	assert_eq(str(life.get_meta("armor")), "chain_mail", "생명 영역은 중갑 숙련 — 사슬 갑옷 그대로")
	var death := _pc("cleric", 3, {"subclass": "death"})
	assert_false(death.has_condition("armor_unproficient"), "죽음 영역: 숙련 있는 갑옷으로 바뀐다")
	assert_eq(RulesDB.get_entry("armor", str(death.get_meta("armor")))["category"], "medium")
	var spec := Builder.default_spec("cleric", 3)
	spec["subclass"] = "death"
	spec["auto_armor"] = false
	var r := Builder.build(spec)
	own(r["creature"])
	assert_true(r["creature"].has_condition("armor_unproficient"), "직접 정한 갑옷은 건드리지 않는다")
