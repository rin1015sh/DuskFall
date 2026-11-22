extends "res://tests/test_case.gd"
## 캐릭터 생성·성장(룰북 6단계): 포인트 구매, 자유 배분, 종족·배경, 클래스 1→5레벨.

const Builder := preload("res://scripts/rules/character_builder.gd")


func _build(class_id: String, level: int, extra: Dictionary = {}) -> Node:
	var spec := Builder.default_spec(class_id, level)
	spec.merge(extra, true)
	var r := Builder.build(spec)
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	if r["creature"] != null:
		own(r["creature"])
	return r["creature"]


func test_point_buy() -> void:
	assert_eq(Builder.validate_point_buy({"str": 15, "dex": 15, "con": 15, "int": 8, "wis": 8, "cha": 8}).size(), 0, "9×3 = 27")
	assert_eq(Builder.validate_point_buy({"str": 15, "dex": 15, "con": 15, "int": 9, "wis": 8, "cha": 8}).size(), 1, "28점은 초과")
	assert_eq(Builder.validate_point_buy({"str": 16}).size(), 1, "15를 넘을 수 없다")
	assert_eq(Builder.point_cost({"str": 14, "dex": 13}), 12)


func test_free_ability_bonus() -> void:
	assert_eq(Builder.validate_bonus({"wis": 2, "str": 1}).size(), 0, "아무 능력치에나 +2/+1")
	assert_eq(Builder.validate_bonus({"wis": 1, "str": 1, "cha": 1}).size(), 0, "+1/+1/+1")
	assert_eq(Builder.validate_bonus({"wis": 2, "str": 2}).size(), 1)
	var c := _build("wizard", 1)
	assert_eq(c.abilities["int"], 17, "1레벨 최대 15 + 2")


func test_fighter_1_to_5() -> void:
	var l1 := _build("fighter", 1)
	assert_eq(l1.hp_max, 12, "d10 최대 + 건강 2")
	assert_eq(l1.resources["second_wind"]["max"], 2)
	assert_false(l1.resources.has("action_surge"), "행동 연쇄는 2레벨")
	assert_eq(l1.weapon_masteries.size(), 3)
	assert_eq(l1.ac(), 19, "사슬 갑옷 16 + 방패 2 + 방어 1")
	assert_eq(l1.initiative_bonus, 2, "인간 출신 재주 경계")
	var l5 := _build("fighter", 5)
	assert_eq(l5.hp_max, 44, "12 + 4 × (6 + 2) — 룰북 예시 전투 3의 HP 44")
	assert_eq(l5.proficiency_bonus, 3)
	assert_eq(l5.attacks_per_action, 2, "추가 공격")
	assert_eq(l5.resources["second_wind"]["max"], 3, "4레벨 3회")
	assert_eq(l5.resources["action_surge"]["max"], 1)
	assert_eq(l5.weapon_masteries.size(), 4)
	assert_eq(l5.crit_threshold, 19, "챔피언 향상된 치명타")
	assert_eq(l5.abilities["str"], 19, "15 + 2 + 능력치 향상 2")


func test_rogue_1_to_5() -> void:
	var l1 := _build("rogue", 1)
	assert_true(l1.has_feature("sneak_attack"))
	assert_eq(l1.skill_bonuses["stealth"], 4, "전문화: 숙련 2배")
	assert_eq(l1.weapon_masteries.size(), 2)
	assert_true("rapier" in l1.weapon_proficiencies and not "longsword" in l1.weapon_proficiencies, "교묘·가벼움 군용 무기만")
	assert_true(l1.has_feature("halfling_luck"))
	var l5 := _build("rogue", 5)
	assert_true(l5.has_feature("cunning_strike") and l5.has_feature("uncanny_dodge"))
	assert_true("uncanny_dodge" in l5.known_reactions)
	assert_true(l5.has_feature("fast_hands"), "도둑")


func test_cleric_1_to_5() -> void:
	var l1 := _build("cleric", 1)
	assert_eq(l1.hp_max, 11, "d8 최대 + 건강 2 + 드워프 1 — 룰북 예시 전투 1의 HP 11")
	assert_eq(l1.resources["spell_slot_1"]["max"], 2)
	assert_eq(l1.spells.filter(func(s: String) -> bool: return RulesDB.get_entry("spell", s)["level"] == 0).size(), 3)
	assert_true("poison" in l1.damage_resistances and "poisoned" in l1.save_advantage_vs, "드워프")
	assert_eq(l1.ac(), 18, "수호자 중갑: 사슬 갑옷 16 + 방패 2(민첩 없음) — 룰북 예시 전투 1의 AC 18")
	var l3 := _build("cleric", 3)
	assert_true(l3.spells.has("bless") and l3.spells.has("cure_wounds"), "생명 영역 주문 항상 준비")
	assert_eq(l3.resources["channel_divinity"]["max"], 2)
	var l5 := _build("cleric", 5)
	assert_eq(l5.hp_max, 43, "11 + 4 × (5 + 2) + 4 — 룰북 예시 전투 3의 HP 43")
	assert_eq([int(l5.resources["spell_slot_1"]["max"]), int(l5.resources["spell_slot_2"]["max"]), int(l5.resources["spell_slot_3"]["max"])], [4, 3, 2])
	assert_true(l5.spells.has("revivify") and l5.spells.has("spirit_guardians"))
	assert_true(l5.has_feature("sear_undead"))


func test_wizard_1_to_5() -> void:
	var l1 := _build("wizard", 1)
	assert_eq(l1.hp_max, 7, "d6 + 건강 1 — 룰북 예시 전투 1의 HP 7")
	assert_eq(l1.ac(), 12, "갑옷 없음 10 + 민첩 2")
	assert_true(l1.spells.has("prestidigitation"), "하이 엘프 소마법")
	assert_true(l1.spells.has("shield") and "shield" in l1.known_reactions)
	assert_eq(l1.skill_bonuses.get("arcana", 0), 2, "1레벨엔 학자 없음")
	var l5 := _build("wizard", 5)
	assert_eq(l5.hp_max, 27, "7 + 4 × (4 + 1) — 룰북 예시 전투 3의 HP 27")
	assert_true(l5.spells.has("fireball") and l5.spells.has("misty_step"), "준비 주문 + 혈통 5레벨 주문")
	assert_eq(l5.skill_bonuses["arcana"], 6, "학자 전문화")
	assert_true(l5.has_feature("potent_cantrip"))
	assert_eq(l5.abilities["int"], 19)


func test_species_lineage_spells_by_level() -> void:
	var l1 := _build("wizard", 1, {"lineage": "elf_drow"})
	assert_eq(l1.darkvision_tiles, 24, "드로우 암시야 120피트")
	assert_true(l1.spells.has("dancing_lights") and not l1.spells.has("faerie_fire"))
	var l3 := _build("wizard", 3, {"lineage": "elf_drow"})
	assert_true(l3.spells.has("faerie_fire"), "3레벨 혈통 주문")
	var wood := _build("wizard", 1, {"lineage": "elf_wood"})
	assert_eq(wood.speed_tiles, 7, "우드 엘프 속도 7칸")


func test_invalid_specs() -> void:
	var spec := Builder.default_spec("wizard", 1)
	spec.erase("lineage")
	assert_true(Builder.build(spec)["errors"].size() > 0, "엘프는 혈통을 골라야")
	var s2 := Builder.default_spec("fighter", 3)
	s2["subclass"] = ""
	assert_true(Builder.build(s2)["errors"].size() > 0, "3레벨 하위 클래스")
	var s3 := Builder.default_spec("rogue", 1)
	s3["skills"] = ["arcana", "stealth", "perception", "insight"]
	assert_true(Builder.build(s3)["errors"].size() > 0, "클래스 기능 목록 밖")
