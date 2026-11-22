extends "res://tests/test_case.gd"
## RulesDB: 시작할 때 data/를 읽고 스키마를 검사한다(룰북 8단계 결정 기록 2).


func test_loaded_without_errors() -> void:
	assert_eq(RulesDB.load_errors.size(), 0, str(RulesDB.load_errors))


func test_spells_and_conditions_loaded() -> void:
	assert_eq(RulesDB.ids("spell").size(), 150)
	assert_eq(RulesDB.get_entry("spell", "fireball")["level"], 3.0)
	# 4단계: SRD 상태 12 + 환경 4, 주문 전용 윤곽, 3단계 기습
	assert_eq(RulesDB.ids("condition").size(), 18)
	for id in ["blinded", "charmed", "frightened", "incapacitated", "invisible", "paralyzed",
			"petrified", "poisoned", "prone", "restrained", "stunned", "unconscious",
			"wet", "burning", "acid", "coated_weapon"]:
		assert_true(RulesDB.has_entry("condition", id), "상태 %s" % id)
	for removed in ["grappled", "deafened", "exhaustion"]:
		assert_false(RulesDB.has_entry("condition", removed), "삭제된 상태 %s" % removed)


func test_missing_entry_is_empty() -> void:
	assert_eq(RulesDB.get_entry("spell", "no_such_spell"), {})
	assert_eq(RulesDB.get_entry("no_such_kind", "x"), {})
