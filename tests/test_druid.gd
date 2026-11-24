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
	assert_true(d.spells.has("speak_with_animals"), "드루이드어")
	assert_true(d.spells.has("blur") and d.spells.has("silence") and d.spells.has("hypnotic_pattern"), "사막 땅 주문(BG3)")
	assert_eq(int(d.skill_bonuses.get("nature", 0)), maxi(1, d.ability_mod("wis")), "마법사: 자연 + 지혜")
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
	var r := Features.use(w, d, "wild_shape")
	assert_true(r["ok"], str(r))
	assert_eq(r["form"], "wolf")
	assert_eq(int(d.abilities["str"]), 14, "늑대 근력")
	assert_eq(d.ac(), 12, "늑대 AC")
	assert_eq(d.speed(), 8)
	assert_eq(d.hp, hp, "HP는 그대로")
	assert_eq(d.temp_hp, 2, "임시 HP = 드루이드 레벨")
	assert_true(Spellcasting.can_cast(w, d, "cure_wounds", Vector2i(0, 0)) != "", "변신 중 주문 불가")
	assert_true(d.has_flag("no_spellcasting"), "주문 불가")
	d.reset_turn()
	Dice.force([18, 4])
	var res: Dictionary = Combat.attack(w, d, foe)
	assert_eq(res.get("attack", {}).get("name", ""), "Bite", "늑대 물기")
	d.reset_turn()
	assert_true(Features.use(w, d, "revert_wild_shape")["ok"])
	assert_eq(int(d.abilities["str"]), 8, "원래 근력")
	assert_false(d.has_flag("no_spellcasting"))
	d.reset_turn()
	Features.use(w, d, "wild_shape")
	Resolver.apply_damage(d, [{"amount": 999, "damage_type": "force"}], {})
	assert_false(d.has_meta("beast_form"), "0 HP면 풀린다")


func test_wild_shape_save_restore() -> void:
	var w := make_world(["...."])
	var d := _dru(4)
	d.name = "d"
	w["grid"].place(d, Vector2i(0, 0))
	d.options["wild_shape_form"] = "worg"
	d.reset_turn()
	Features.use(w, d, "wild_shape")
	assert_eq(d.get_meta("beast_form"), "worg", "4레벨 워그")
	var text := JSON.stringify(SaveGame.snapshot(w))
	load("res://scripts/rules/effects/wild_shape.gd").revert(d)
	assert_true(SaveGame.restore(w, JSON.parse_string(text)))
	assert_eq(d.get_meta("beast_form", ""), "worg")
	assert_eq(d.ac(), int(RulesDB.get_entry("monster", "worg")["ac"]), "변신 상태 복원")
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
	d.resources["wild_shape"]["current"] = 0
	assert_true(Features.use(w, d, "wild_resurgence")["ok"])
	assert_eq(d.resource("wild_shape"), 1, "슬롯 → 야생 변신")


func test_wild_companion() -> void:
	var w := make_world([".....", "....."])
	var d := _dru(2)
	w["grid"].place(d, Vector2i(0, 0))
	d.reset_turn()
	var r := Features.use(w, d, "wild_companion")
	assert_true(r["ok"], str(r))
	own(r["summon"])
	assert_eq(d.resource("wild_shape"), 1, "야생 변신 1회")
	assert_eq(r["summon"].creature_type, "fey", "요정 사역마")
	load("res://scripts/rules/spellcasting.gd").instances.clear()
