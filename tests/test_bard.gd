extends "res://tests/test_case.gd"
## 바드: 바드의 영감(실패한 d20 시험에 자동, 매력 횟수, 5레벨 d8·짧은 휴식), 만물박사, 전문화, 영감의 샘(슬롯 → 영감),
## 지식 학파(기능 3개, 비꼬는 말 — 적 명중 굴림 빼기), 신랄한 조롱(다음 공격 불리), 레벨 업 때만 준비 교체.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Features := preload("res://scripts/rules/features.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const SpellPrep := preload("res://scripts/rules/spell_prep.gd")
const Rest := preload("res://scripts/rules/rest.gd")


func _bard(lv: int) -> Node:
	var r := Builder.build(Builder.default_spec("bard", lv))
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func test_build_skills_jack_swap() -> void:
	var b := _bard(3)
	assert_eq(b.resource("bardic_inspiration"), maxi(1, b.ability_mod("cha")), "횟수 = 매력")
	assert_eq(int(b.skill_bonuses["persuasion"]), b.proficiency_bonus * 2, "전문화")
	assert_true(b.skill_bonuses.has("arcana") and b.skill_bonuses.has("medicine"), "지식 학파 기능 3개")
	Dice.force([10])
	var r := Resolver.ability_check(b, "str", 30, {"skill": "athletics"})
	assert_eq(int(r["bonus"]), b.ability_mod("str") + 1, "만물박사 +1")
	assert_eq(b.prep_swaps, 0, "바드는 긴 휴식 교체가 없다")
	SpellPrep.open_window(b, "level_up")
	assert_eq(b.prep_swaps, 1, "레벨 업 때 1개")
	assert_eq(_bard(5).resources["bardic_inspiration"]["recharge"], "short", "영감의 샘: 짧은 휴식")


func test_inspiration_auto_on_failed_save() -> void:
	var w := make_world(["....."])
	var b := _bard(1)
	var ally := make_creature({"team": "party", "hp_max": 20})
	w["grid"].place(b, Vector2i(0, 0))
	w["grid"].place(ally, Vector2i(3, 0))
	b.reset_turn()
	assert_true(Features.use(w, b, "bardic_inspiration", ally)["ok"])
	assert_true(ally.has_condition("bardic_inspiration"))
	Dice.force([8, 6])  # 내성 8 실패 → 영감 6 → 14 성공
	var s := Resolver.saving_throw(ally, "wis", 12)
	assert_true(s["success"], "영감으로 성공 %s" % str(s))
	assert_false(ally.has_condition("bardic_inspiration"), "쓰면 사라진다")
	b.reset_turn()
	assert_false(Features.use(w, b, "bardic_inspiration", b)["ok"], "자신에게는 못 준다")


func test_cutting_words_and_font() -> void:
	var w := make_world(["......"])
	var b := _bard(5)
	var ally := make_creature({"team": "party", "hp_max": 40, "ac_base": 15})
	var foe := make_creature({"team": "enemy", "hp_max": 20})
	w["grid"].place(b, Vector2i(0, 0))
	w["grid"].place(ally, Vector2i(3, 0))
	w["grid"].place(foe, Vector2i(4, 0))
	b.reaction_settings["cutting_words"] = "auto"
	b.reset_turn()
	foe.reset_turn()
	var left: int = b.resource("bardic_inspiration")
	Dice.force([14, 8])  # 적 명중 14 + 2 = 16 vs AC 15, 비꼬는 말 8 → 빗나감
	var res: Dictionary = Combat.attack(w, foe, ally, {"weapon": "unarmed"})
	assert_false(res["hit"], "비꼬는 말로 빗나감 %s" % str(res.get("total")))
	assert_eq(b.resource("bardic_inspiration"), left - 1)
	assert_false(b.can_react(), "반응을 썼다")
	var slots: int = b.resource("spell_slot_1")
	assert_false(b.feature_data.get("font_of_inspiration", {}).has("script"), "영감의 샘은 짧은 휴식 회복만(BG3)")


func test_vicious_mockery() -> void:
	var w := make_world(["......"])
	var b := _bard(1)
	var foe := make_creature({"team": "enemy", "hp_max": 20, "abilities": {"wis": 1}})
	var ally := make_creature({"team": "party", "hp_max": 20})
	w["grid"].place(b, Vector2i(0, 0))
	w["grid"].place(foe, Vector2i(4, 0))
	w["grid"].place(ally, Vector2i(5, 0))
	b.reset_turn()
	Dice.force([1])
	assert_true(Spellcasting.cast(w, b, "vicious_mockery", Vector2i(4, 0)).get("ok", false))
	assert_true(foe.has_condition("mocked"))
	foe.reset_turn()
	Dice.force([15, 3])
	var res: Dictionary = Combat.attack(w, foe, ally, {"weapon": "unarmed"})
	assert_eq(int(res["mode"]), -1, "다음 공격 불리")
	assert_false(foe.has_condition("mocked"), "공격하면 끝")
