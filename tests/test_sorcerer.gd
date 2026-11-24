extends "res://tests/test_case.gd"
## 소서러: 타고난 마법(DC +1·주문 공격 유리), 마법의 샘(슬롯 ↔ 점수), 주문 변형(빠른·원거리·고양된 — 설정, 한 번 쓰면 꺼짐),
## 마법 회복(짧은 휴식), 용의 혈통(HP·AC·항상 준비).

const Builder := preload("res://scripts/rules/character_builder.gd")
const Features := preload("res://scripts/rules/features.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Rest := preload("res://scripts/rules/rest.gd")


func _sorc(lv: int) -> Node:
	var r := Builder.build(Builder.default_spec("sorcerer", lv))
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func test_build_draconic() -> void:
	var s := _sorc(5)
	assert_eq(s.ac(), 13 + s.ability_mod("dex"), "용의 회복력 AC 13 + 민첩(BG3)")
	var con: int = s.ability_mod("con")
	assert_eq(s.hp_max, 6 + con + 4 * (4 + con) + 5, "용의 회복력 +5")
	assert_true(s.spells.has("burning_hands"), "용의 조상(붉은 용) 주문")
	assert_eq(s.resource("sorcery_points"), 5)
	assert_true(s.has_cap("metamagic_quickened") and s.has_cap("metamagic_distant") and s.has_cap("metamagic_heightened"), "BG3: 3레벨 변형 3개")


func test_innate_sorcery_and_font() -> void:
	var w := make_world(["...."])
	var s := _sorc(3)
	w["grid"].place(s, Vector2i(0, 0))
	var dc: int = Spellcasting.spell_dc(s)
	s.reset_turn()
	assert_false(s.feature_data.has("innate_sorcery"), "타고난 마법 없음(BG3)")
	assert_true(Features.use(w, s, "convert_slot")["ok"] == false, "점수가 가득하면 못 바꾼다")
	s.resources["sorcery_points"]["current"] = 0
	assert_true(Features.use(w, s, "convert_slot")["ok"])
	assert_eq(s.resource("sorcery_points"), 1, "1레벨 슬롯 → 1점")
	s.resources["sorcery_points"]["current"] = 3
	s.reset_turn()
	var r := Features.use(w, s, "create_slot")
	assert_eq(int(r["level"]), 2, "3점 → 2레벨 슬롯")
	assert_eq(s.resource("sorcery_points"), 0)


func test_metamagic_quickened_distant() -> void:
	var w := make_world(["..............................."])
	var s := _sorc(3)
	var foe := make_creature({"team": "enemy", "hp_max": 50, "ac_base": 1})
	w["grid"].place(s, Vector2i(0, 0))
	w["grid"].place(foe, Vector2i(16, 0))
	s.reset_turn()
	assert_eq(Spellcasting.can_cast(w, s, "fire_bolt", Vector2i(16, 0)), "사거리 밖")
	s.options["metamagic"] = "distant"
	assert_eq(Spellcasting.can_cast(w, s, "fire_bolt", Vector2i(16, 0)), "", "원거리 주문(BG3): 12칸 → 18칸(+50%)")
	assert_eq(Spellcasting.can_cast(w, s, "fire_bolt", Vector2i(19, 0)), "사거리 밖", "2배가 아니다")
	Dice.force([15, 5])
	assert_true(Spellcasting.cast(w, s, "fire_bolt", Vector2i(16, 0)).get("ok", false))
	assert_eq(s.resource("sorcery_points"), 2, "1점")
	assert_eq(s.options["metamagic"], "none", "한 번 쓰면 꺼진다")
	s.reset_turn()
	s.resources["sorcery_points"]["current"] = 3
	s.options["metamagic"] = "quickened"
	w["grid"].move_creature(foe, Vector2i(5, 0))
	Dice.force([3, 3, 3])  # 마법 화살: 명중 굴림 없음
	assert_true(Spellcasting.cast(w, s, "magic_missile", Vector2i(5, 0)).get("ok", false))
	assert_eq(int(s.turn["action"]), 1, "빠른 주문: 행동이 남는다")
	assert_eq(int(s.turn["bonus"]), 0)
	assert_eq(s.resource("sorcery_points"), 0, "빠른 주문 3점(BG3)")


func test_metamagic_careful_all_allies_and_choices() -> void:
	var spec := Builder.default_spec("sorcerer", 3)
	spec["metamagic"] = ["careful", "twinned", "subtle"]
	var r0 := Builder.build(spec)
	assert_eq(r0["errors"].size(), 0, str(r0["errors"]))
	var s: Node = own(r0["creature"])
	var w := make_world(["......", "......", "......"])
	var ally := make_creature({"team": "party", "hp_max": 30})
	var ally2 := make_creature({"team": "party", "hp_max": 30})
	var foe := make_creature({"team": "enemy", "hp_max": 30, "abilities": {"dex": 1}})
	w["grid"].place(s, Vector2i(0, 1))
	w["grid"].place(ally, Vector2i(1, 1))
	w["grid"].place(ally2, Vector2i(1, 0))
	w["grid"].place(foe, Vector2i(2, 1))
	s.reset_turn()
	s.options["metamagic"] = "careful"
	Dice.force([1, 3, 3, 3])
	var r: Dictionary = Spellcasting.cast(w, s, "burning_hands", Vector2i(2, 1))
	assert_true(r.get("ok", false), str(r))
	assert_eq(ally.hp, 30, "신중한 주문: 아군 피해 없음")
	assert_eq(ally2.hp, 30, "BG3: 매력 수정치 수가 아니라 아군 모두")
	assert_true(foe.hp < 30)
	assert_true(s.has_cap("metamagic_subtle"), "은밀한 주문은 3레벨부터")
	var low := Builder.default_spec("sorcerer", 2)
	low["metamagic"] = ["quickened", "twinned"]
	assert_false(Builder.build(low)["creature"].has_cap("metamagic_quickened"), "빠른 주문은 3레벨부터(BG3)")
	var sk := Builder.default_spec("sorcerer", 3)
	sk["metamagic"] = ["seeking", "careful", "distant"]
	var ss: Node = own(Builder.build(sk)["creature"])
	assert_false(ss.has_cap("metamagic_seeking"), "추적 주문은 일반 선택지가 아니다(BG3)")


func test_metamagic_twinned() -> void:
	var spec := Builder.default_spec("sorcerer", 5)
	spec["metamagic"] = ["twinned", "distant", "careful"]
	spec["spells"] = ["hold_person"] + (spec.get("spells", []) as Array).filter(func(x: String) -> bool: return x != "hold_person")
	var s: Node = own(Builder.build(spec)["creature"])
	var w := make_world(["........", "........", "........"])
	var a := make_creature({"team": "enemy", "hp_max": 50, "ac_base": 1})
	var b := make_creature({"team": "enemy", "hp_max": 50, "ac_base": 1})
	var far := make_creature({"team": "enemy", "hp_max": 50, "ac_base": 1})
	var friend := make_creature({"team": "party", "hp_max": 50})
	w["grid"].place(s, Vector2i(0, 1))
	w["grid"].place(a, Vector2i(4, 1))
	w["grid"].place(b, Vector2i(5, 2))
	w["grid"].place(far, Vector2i(7, 0))
	w["grid"].place(friend, Vector2i(3, 1))
	s.reset_turn()
	var pts: int = s.resource("sorcery_points")
	s.options["metamagic"] = "twinned"
	Dice.force([15, 5, 5, 15, 5, 5])  # 대상마다 명중 15·피해 2d10(5레벨)
	assert_true(Spellcasting.cast(w, s, "fire_bolt", Vector2i(4, 1)).get("ok", false))
	assert_true(a.hp < 50 and b.hp < 50, "첫 대상에 가장 가까운 같은 편 생물이 두 번째 대상")
	assert_eq(far.hp, 50)
	assert_eq(friend.hp, 50, "아군은 두 번째 대상이 아니다")
	assert_eq(s.resource("sorcery_points"), pts - 1, "소마법은 1점")
	s.reset_turn()
	s.options["metamagic"] = "twinned"
	pts = s.resource("sorcery_points")
	Dice.force([1, 1])  # 대상마다 지혜 내성 1 실패
	assert_true(Spellcasting.cast(w, s, "hold_person", Vector2i(4, 1), {"slot": 2, "targets": [a, far]}).get("ok", false))
	assert_true(a.has_condition("paralyzed") and far.has_condition("paralyzed"), "직접 고른 두 번째 대상")
	assert_eq(s.resource("sorcery_points"), pts - 2, "2레벨 슬롯 = 2점")
	s.reset_turn()
	s.options["metamagic"] = "twinned"
	assert_eq(Spellcasting.metamagic_for(s, RulesDB.get_entry("spell", "burning_hands")), "", "범위 주문은 쌍둥이 불가")


func test_subtle_spell_can_still_be_counterspelled() -> void:
	# BG3: 은밀한 주문은 침묵 속 시전만 — 주문 방해는 받는다
	var w := make_world(["..........", ".........."])
	var s := _sorc(5)
	var r := Builder.build(Builder.default_spec("wizard", 5))
	var wiz: Node = own(r["creature"])
	wiz.team = "enemy"
	w["grid"].place(s, Vector2i(0, 0))
	w["grid"].place(wiz, Vector2i(6, 0))
	wiz.reaction_settings["counterspell"] = "auto"
	s.options["metamagic"] = "subtle"
	s.reset_turn()
	Dice.force([2])
	var res: Dictionary = Spellcasting.cast(w, s, s.spells.filter(func(x: String) -> bool: return int(RulesDB.get_entry("spell", x)["level"]) >= 1 and RulesDB.get_entry("spell", x).get("area") == null)[0], Vector2i(6, 0))
	assert_true(res.get("countered", false), "은밀해도 끊긴다")
