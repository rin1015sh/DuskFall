extends "res://tests/test_case.gd"
## 멀티클래스(SRD 5.2.1 + BG3식 선행 조건 없음): 클래스 레벨별 기능·자원, HP(1레벨만 최대), 숙련 보너스(총 레벨),
## 멀티클래스 숙련(일부), 다중 시전 슬롯표, 계약 마법 슬롯 따로, 클래스마다 준비·시전 능력, 맨몸 방어 하나, 레벨 업으로 새 클래스.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const SpellPrep := preload("res://scripts/rules/spell_prep.gd")
const Progression := preload("res://scripts/rules/progression.gd")
const Actions := preload("res://scripts/rules/actions.gd")


func _multi(primary: String, classes: Array, extra: Dictionary = {}) -> Node:
	var spec := Builder.default_spec(primary, 1)
	spec["classes"] = classes
	spec.merge(extra, true)
	var r := Builder.build(spec)
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"]) if r["creature"] != null else null


func test_fighter_rogue() -> void:
	var c := _multi("fighter", [{"class": "fighter", "level": 3, "subclass": "champion"}, {"class": "rogue", "level": 2, "skills": ["stealth"]}])
	assert_eq(c.level, 5)
	assert_eq(c.proficiency_bonus, 3, "숙련 보너스는 총 레벨")
	assert_eq(c.class_level("rogue"), 2)
	var con: int = c.ability_mod("con")
	assert_eq(c.hp_max, 10 + con + 2 * (6 + con) + 2 * (5 + con), "1레벨만 최대, 나머지 평균")
	assert_true(c.resources.has("action_surge"), "전사 2레벨 행동 연쇄")
	assert_true(c.feature_data.has("cunning_action"), "로그 2레벨 교활한 행동")
	assert_eq(c.save_proficiencies, ["str", "con"], "내성은 주 클래스만")
	assert_true(c.skill_bonuses.has("stealth"), "로그 멀티클래스 기능 1")
	assert_eq(Actions.sneak_dice(c), 1, "급소 공격은 로그 레벨(2) 기준 1d6")
	assert_eq(c.attacks_per_action, 1, "추가 공격은 전사 5레벨부터")


func test_wizard_cleric_slots_and_ability() -> void:
	var c := _multi("wizard", [{"class": "wizard", "level": 3, "subclass": "evoker"},
		{"class": "cleric", "level": 2, "subclass": "life", "cantrips": ["sacred_flame"], "spells": ["healing_word", "bless", "spiritual_weapon"]}])
	assert_eq(c.resource("spell_slot_3"), 2, "시전 레벨 5: 4/3/2")
	assert_eq(c.resource("spell_slot_1"), 4)
	assert_eq(SpellPrep.max_slot_level(c, "wizard"), 2, "위저드 3레벨 표: 2레벨 주문까지")
	assert_eq(SpellPrep.max_slot_level(c, "cleric"), 1, "클레릭 2레벨 표: 1레벨 주문까지")
	assert_false(c.spells.has("spiritual_weapon"), "클레릭 2레벨은 2레벨 주문을 준비 못 한다")
	assert_true(c.spells.has("healing_word") and c.spells.has("sacred_flame"))
	assert_eq(Spellcasting.ability_for(c, "healing_word"), "wis", "클레릭 주문은 지혜")
	assert_eq(Spellcasting.ability_for(c, "magic_missile"), "int")
	assert_true("healing_word" in SpellPrep.prepared_of(c, "cleric"))
	var w := {}
	var r := SpellPrep.toggle(w, c, "healing_word")
	assert_true(r["ok"], str(r))
	assert_false("healing_word" in SpellPrep.prepared_of(c, "cleric"), "클래스별 준비 해제")


func test_warlock_sorcerer_pact_slots() -> void:
	var c := _multi("sorcerer", [{"class": "sorcerer", "level": 3, "subclass": "draconic"},
		{"class": "warlock", "level": 2, "subclass": "fiend", "cantrips": ["eldritch_blast", "minor_illusion"], "spells": ["hex", "charm_person"]}])
	assert_eq(c.resource("pact_slot_1"), 2, "계약 마법 슬롯은 따로")
	assert_eq(c.resources["pact_slot_1"]["recharge"], "short")
	assert_eq(c.resource("spell_slot_2"), 2, "소서러 3레벨 자기 표(시전 클래스가 하나)")
	for k: String in c.resources.keys():
		if k.begins_with("spell_slot_"):
			c.resources[k]["current"] = 0
	var w := make_world(["......"])
	var foe := make_creature({"team": "enemy", "hp_max": 30})
	w["grid"].place(c, Vector2i(0, 0))
	w["grid"].place(foe, Vector2i(3, 0))
	c.reset_turn()
	assert_true(Spellcasting.cast(w, c, "hex", Vector2i(3, 0)).get("ok", false), "계약 슬롯으로 시전")
	assert_eq(c.resource("pact_slot_1"), 1)
	assert_eq(Spellcasting.ability_for(c, "hex"), "cha")


func test_unarmored_defense_one_formula() -> void:
	var c := _multi("barbarian", [{"class": "barbarian", "level": 2}, {"class": "monk", "level": 1}])
	var dex: int = c.ability_mod("dex")
	var best := maxi(c.ability_mod("con"), c.ability_mod("wis"))
	assert_eq(c.ac(), 10 + dex + best, "맨몸 방어는 가장 좋은 공식 하나")
	assert_true(c.weapon_proficiencies.has("martial") or c.weapon_proficiencies.has("greataxe") or "martial" in c.weapon_proficiencies, "바바리안 무기 숙련")


func test_level_up_into_new_class() -> void:
	var w := {"xp": 6500}
	var r := Builder.build(Builder.default_spec("fighter", 4))
	var c: Node = own(r["creature"])
	assert_true(Progression.level_up(w, c, "wizard", {"cantrips": ["fire_bolt", "light", "mage_hand"], "spells": ["magic_missile", "shield"]}))
	assert_eq(c.level, 5)
	assert_eq(c.class_level("fighter"), 4)
	assert_eq(c.class_level("wizard"), 1)
	assert_true(c.spells.has("magic_missile") and c.resource("spell_slot_1") == 2, "위저드 1레벨 주문·슬롯")
	assert_eq(c.attacks_per_action, 1, "전사 4레벨: 추가 공격 없음")
	assert_true(c.has_meta("spec") and c.get_meta("spec")["classes"].size() == 2, "명세에 클래스 목록")
