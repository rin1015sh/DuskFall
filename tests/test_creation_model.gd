extends "res://tests/test_case.gd"
## 캐릭터 생성 화면 모델: 포인트 구매 27점, 자유 배분, 체형 틀, 기능 선택(룰북 6단계, 1단계 체형 틀).

const Model := preload("res://scenes/ui/creation_model.gd")


func test_point_buy_budget() -> void:
	var m := Model.new("fighter")
	assert_eq(m.points_left(), 27, "모두 8에서 시작")
	for i in 7:
		m.raise("str")
	assert_eq(m.spec["scores"]["str"], 15)
	assert_false(m.raise("str"), "15가 상한")
	assert_eq(m.points_left(), 18, "15 = 9점")
	for i in 7:
		m.raise("dex")
	for i in 7:
		m.raise("con")
	assert_eq(m.points_left(), 0)
	assert_false(m.can_raise("int"), "남은 포인트 없음")
	m.lower("con")
	assert_eq(m.points_left(), 2, "15 → 14는 2점 돌려받음")


func test_bonus_and_final_scores() -> void:
	var m := Model.new("wizard")
	m.set_bonus_two_one("int", "wis")
	assert_eq(m.final_score("int"), 10)
	m.set_bonus_ones("str", "dex", "con")
	assert_eq(m.spec["bonus"], {"str": 1, "dex": 1, "con": 1})


func test_body_frames() -> void:
	var m := Model.new("fighter")
	m.set_species("dwarf")
	assert_eq(m.body_frame(), "dwarf")
	m.set_species("halfling")
	assert_eq(m.body_frame(), "small")
	m.set_species("human")
	m.spec["size"] = "small"
	assert_eq(m.body_frame(), "small", "인간은 작은 체형도 고를 수 있다")
	m.set_species("elf")
	assert_eq(m.spec["lineage"] != "", true, "엘프는 혈통이 기본으로 하나 골라진다")


func test_skills_and_valid_preview() -> void:
	var m := Model.new("rogue")
	m.set_species("halfling")
	for a: String in ["dex", "dex", "dex", "dex", "dex", "dex", "dex", "con", "con", "con", "con", "con", "con", "wis", "wis", "wis", "wis", "wis"]:
		m.raise(a)
	m.set_bonus_two_one("dex", "con")
	for s: String in ["acrobatics", "stealth", "perception", "insight", "deception"]:
		m.toggle_skill(s)
	assert_eq(m.spec["skills"].size(), 4, "로그는 4개까지")
	assert_false(m.toggle_skill("arcana"), "목록 밖")
	assert_eq(m.errors().size(), 0, str(m.errors()))
	var p: Dictionary = m.preview()
	assert_eq(p["hp"], 8 + 2, "d8 + 건강 2")
	assert_eq(p["body"], "small")
