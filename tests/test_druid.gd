extends "res://tests/test_case.gd"
## 드루이드: 야생 변신(짐승 능력치·AC·속도·공격, HP 유지 + 임시 HP, 주문 불가, 풀기·0 HP·긴 휴식, 저장), 원초의 질서(마법사),
## 드루이드어(항상 준비), 대지 회합(땅 주문·땅의 도움), 야생의 부활, 긴 휴식 뒤 전부 교체.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Features := preload("res://scripts/rules/features.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const SaveGame := preload("res://scripts/rules/save_game.gd")


func _dru(lv: int) -> Node:
	var r := Builder.build(Builder.default_spec("druid", lv))
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func test_build_order_land() -> void:
	var d := _dru(5)
	assert_false(d.feature_data.has("druidic") or d.feature_data.has("primal_order"), "드루이드어·원초의 질서 없음(BG3)")
	assert_true(d.spells.has("blur") and d.spells.has("silence") and d.spells.has("hypnotic_pattern"), "사막 땅 주문(BG3)")
	assert_true(d.spells.has("guidance"), "대지의 소마법(BG3)")
	assert_eq(d.prep_swaps, -1, "긴 휴식 뒤 전부 교체")


func test_wild_shape_attack_and_revert() -> void:
	var w := make_world(["....."])
	var d := _dru(2)
	var foe := make_creature({"team": "enemy", "hp_max": 40, "ac_base": 1})
	w["grid"].place(d, Vector2i(0, 0))
	w["grid"].place(foe, Vector2i(1, 0))
	var hp: int = d.hp
	d.reset_turn()
	d.options["wild_shape_form"] = "dire_wolf"
	var r := Features.use(w, d, "wild_shape")
	assert_true(r["ok"], str(r))
	assert_eq(r["form"], "dire_wolf")
	assert_eq(int(d.abilities["str"]), 17, "다이어 울프 근력")
	assert_eq(d.ac(), 14, "다이어 울프 AC")
	assert_eq(d.speed(), 10)
	assert_eq(d.hp, int(RulesDB.get_entry("monster", "dire_wolf")["hp"]), "형태 HP(BG3 18)")
	assert_eq(d.temp_hp, 0)
	assert_true(Spellcasting.can_cast(w, d, "cure_wounds", Vector2i(0, 0)) != "", "변신 중 주문 불가")
	assert_true(d.has_flag("no_spellcasting"), "주문 불가")
	d.reset_turn()
	Dice.force([18, 4])
	var res: Dictionary = Combat.attack(w, d, foe)
	assert_eq(res.get("attack", {}).get("name", ""), "Bite", "늑대 물기")
	d.reset_turn()
	assert_true(Features.use(w, d, "revert_wild_shape")["ok"])
	assert_eq(int(d.abilities["str"]), 8, "원래 근력")
	assert_eq(d.hp, hp, "원래 HP")
	assert_false(d.has_flag("no_spellcasting"))
	d.reset_turn()
	Features.use(w, d, "wild_shape")
	Resolver.apply_damage(d, [{"amount": 999, "damage_type": "force"}], {})
	assert_false(d.has_meta("beast_form"), "0 HP면 풀린다")
	assert_eq(d.hp, hp, "넘친 피해는 이어지지 않는다(BG3)")
	assert_false(d.is_down())


func test_wild_shape_save_restore() -> void:
	var w := make_world(["...."])
	var d := _dru(4)
	d.name = "d"
	w["grid"].place(d, Vector2i(0, 0))
	d.options["wild_shape_form"] = "cave_aurochs"
	d.reset_turn()
	Features.use(w, d, "wild_shape")
	assert_eq(d.get_meta("beast_form"), "cave_aurochs", "4레벨 동굴 들소")
	var text := JSON.stringify(SaveGame.snapshot(w))
	load("res://scripts/rules/effects/wild_shape.gd").revert(d)
	assert_true(SaveGame.restore(w, JSON.parse_string(text)))
	assert_eq(d.get_meta("beast_form", ""), "cave_aurochs")
	assert_eq(d.ac(), int(RulesDB.get_entry("monster", "cave_aurochs")["ac"]), "변신 상태 복원")
	load("res://scripts/rules/effects/wild_shape.gd").revert(d)
	assert_eq(int(d.abilities["str"]), 8, "풀면 원래대로")


func test_lands_aid_and_resurgence() -> void:
	var w := make_world(["........", "........"])
	var d := _dru(5)
	var foe := make_creature({"team": "enemy", "hp_max": 40, "abilities": {"con": 1}})
	var ally := make_creature({"team": "party", "hp_max": 30})
	w["grid"].place(d, Vector2i(0, 0))
	w["grid"].place(foe, Vector2i(5, 0))
	w["grid"].place(ally, Vector2i(5, 1))
	ally.hp = 10
	d.reset_turn()
	assert_false(d.has_feature("lands_aid"), "BG3 대지 회합에는 땅의 도움이 없다")
	assert_false(d.has_feature("wild_resurgence"), "야생 재기 없음(BG3)")




func test_wild_shape_full_recharge_on_short_rest() -> void:
	# BG3: 야생 변신 2회(6레벨 3회), 짧은 휴식에 모두 회복
	var d := _dru(6)
	var w := make_world(["...."])
	w["grid"].place(d, Vector2i(0, 0))
	assert_eq(d.resource("wild_shape"), 3)
	d.resources["wild_shape"]["current"] = 0
	assert_true(preload("res://scripts/rules/rest.gd").short_rest(w, [d])["ok"])
	assert_eq(d.resource("wild_shape"), 3, "짧은 휴식에 모두")
