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
