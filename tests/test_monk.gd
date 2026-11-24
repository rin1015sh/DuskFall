extends "res://tests/test_case.gd"
## 몽크: 무술(민첩·무술 주사위·보너스 비무장 공격), 맨몸 방어·이동, 기(연타·인내의 방어·바람의 걸음), 신비한 대사,
## 공격 쳐내기, 느린 낙하, 충격의 일격(설정), 열린 손 기법.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Features := preload("res://scripts/rules/features.gd")
const Physics := preload("res://scripts/rules/physics.gd")


func _monk(lv: int) -> Node:
	var r := Builder.build(Builder.default_spec("monk", lv))
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func _foe(extra := {}) -> Node:
	var f := make_creature({"team": "enemy", "hp_max": 80, "ac_base": 5})
	f.setup(extra)
	return f


func test_build_martial_arts() -> void:
	var m := _monk(5)
	assert_eq(m.ac(), 10 + m.ability_mod("dex") + m.ability_mod("wis"), "맨몸 방어(지혜)")
	assert_eq(m.speed_tiles, 8, "맨몸 이동 +2칸")
	assert_eq(m.resource("focus"), 6, "기 = 레벨 + 1(BG3)")
	var a := Combat.build_weapon_attack(m, "unarmed")
	assert_eq(a["ability"], "dex", "무술: 민첩")
	assert_eq(a["damage"][0]["dice"], "1d6%+d" % m.ability_mod("dex"), "5레벨 기민한 타격 d6(BG3)")
	var d := Combat.build_weapon_attack(m, "dagger")
	assert_eq(d["damage"][0]["dice"], "1d6%+d" % m.ability_mod("dex"), "대거 1d4 → 1d6")


func test_flurry_open_hand_and_bonus_strike() -> void:
	var w := make_world(["....."])
	var m := _monk(3)
	var f := _foe({"abilities": {"dex": 1}})
	w["grid"].place(m, Vector2i(0, 0))
	w["grid"].place(f, Vector2i(1, 0))
	m.reset_turn()
	Dice.force([18, 3, 1, 18, 3, 1])  # 명중·피해·넘어뜨리기 내성 실패 ×2
	var r := Features.use(w, m, "flurry_of_blows", f)
	assert_true(r["ok"], str(r))
	assert_eq(int(r["hits"]), 2)
	assert_eq(m.resource("focus"), 3, "기 1(4 → 3)")
	assert_true(f.has_condition("prone"), "열린 손: 넘어뜨리기")
	assert_false(Features.use(w, m, "martial_arts_strike", f)["ok"], "보너스 행동은 하나")


func test_patient_defense_step_metabolism() -> void:
	var w := make_world(["....."])
	var m := _monk(3)
	w["grid"].place(m, Vector2i(0, 0))
	m.reset_turn()
	assert_true(Features.use(w, m, "patient_defense")["ok"])
	assert_false(m.turn.get("disengaged", false), "인내의 방어는 회피만(BG3)")
	assert_eq(m.resource("focus"), 3)
	m.reset_turn()
	var mv: int = m.turn["movement"]
	Features.use(w, m, "step_of_the_wind")
	assert_eq(int(m.turn["movement"]), mv + m.speed(), "질주")
	assert_eq(m.resource("focus"), 2, "바람의 걸음 기 1")
	m.reset_turn()
	assert_true(Features.use(w, m, "step_of_the_wind_disengage")["ok"])
	assert_true(m.turn.get("disengaged", false))


func test_deflect_slow_fall_stunning() -> void:
	var w := make_world(["....."])
	var m := _monk(5)
	var f := _foe({"abilities": {"con": 1}})
	w["grid"].place(m, Vector2i(0, 0))
	w["grid"].place(f, Vector2i(1, 0))
	m.reaction_settings["deflect_missiles"] = "auto"
	m.reset_turn()
	f.reset_turn()
	var hp: int = m.hp
	Dice.force([18, 4])  # 근접 단검: 화살 튕기기는 원거리만(BG3) — 피해 그대로
	Combat.attack(w, f, m, {"weapon": "dagger"})
	assert_true(m.hp < hp, "근접은 튕기지 못한다")
	m.hp = hp
	f.reset_turn()
	w["grid"].move_creature(f, Vector2i(4, 0))
	Dice.force([18, 10, 4])
	Combat.attack(w, f, m, {"weapon": "shortbow"})
	assert_eq(m.hp, hp, "화살 튕기기로 피해 0")
	w["grid"].move_creature(f, Vector2i(1, 0))
	m.reset_turn()
	m.refresh_reaction()  # 반응은 라운드마다 돌아온다
	Dice.force([6, 6, 6])
	var fr := Physics.fall(m, 6)
	assert_eq(int(fr["damage"]), 0, "느린 낙하 −25")
	m.reset_turn()
	Dice.force([18, 3, 1])  # 명중·피해·건강 내성 1
	Combat.attack(w, m, f, {"weapon": "unarmed"})
	assert_true(f.has_condition("stunned"), "충격의 일격")
	assert_eq(m.resource("focus"), 5)
	m.options["stunning_strike"] = "off"
