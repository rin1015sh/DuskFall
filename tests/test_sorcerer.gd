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
	assert_true(s.has_cap("metamagic_quickened") and s.has_cap("metamagic_distant") and not s.has_cap("metamagic_heightened"))


func test_innate_sorcery_and_font() -> void:
	var w := make_world(["...."])
	var s := _sorc(3)
	w["grid"].place(s, Vector2i(0, 0))
	var dc: int = Spellcasting.spell_dc(s)
	s.reset_turn()
	assert_true(Features.use(w, s, "innate_sorcery")["ok"])
	assert_eq(Spellcasting.spell_dc(s), dc + 1, "DC +1")
	assert_eq(s.resource("innate_sorcery"), 1)
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
	w["grid"].place(foe, Vector2i(30, 0))
	s.reset_turn()
	assert_eq(Spellcasting.can_cast(w, s, "fire_bolt", Vector2i(30, 0)), "사거리 밖")
	s.options["metamagic"] = "distant"
	assert_eq(Spellcasting.can_cast(w, s, "fire_bolt", Vector2i(30, 0)), "", "원거리 주문: 24칸 → 48칸")
	Dice.force([15, 5])
	assert_true(Spellcasting.cast(w, s, "fire_bolt", Vector2i(30, 0)).get("ok", false))
	assert_eq(s.resource("sorcery_points"), 2, "1점")
	assert_eq(s.options["metamagic"], "none", "한 번 쓰면 꺼진다")
	s.reset_turn()
	s.options["metamagic"] = "quickened"
	w["grid"].move_creature(foe, Vector2i(5, 0))
	Dice.force([3, 3, 3])  # 마법 화살: 명중 굴림 없음
	assert_true(Spellcasting.cast(w, s, "magic_missile", Vector2i(5, 0)).get("ok", false))
	assert_eq(int(s.turn["action"]), 1, "빠른 주문: 행동이 남는다")
	assert_eq(int(s.turn["bonus"]), 0)
	assert_eq(s.resource("sorcery_points"), 0)


func test_sorcerous_restoration() -> void:
	var w := make_world(["...."])
	var s := _sorc(5)
	w["grid"].place(s, Vector2i(0, 0))
	s.resources["sorcery_points"]["current"] = 0
	assert_true(Rest.short_rest(w, [s])["ok"])
	assert_eq(s.resource("sorcery_points"), 2, "레벨 절반")
	s.resources["sorcery_points"]["current"] = 0
	Rest.short_rest(w, [s])
	assert_eq(s.resource("sorcery_points"), 0, "긴 휴식마다 1회")


## 신중한 주문(범위 안 아군 자동 성공·피해 없음), 은밀한 주문(주문 방해를 받지 않음), 추적 주문(빗나가면 다시).
func test_metamagic_careful_subtle_seeking() -> void:
	var spec := Builder.default_spec("sorcerer", 3)
	spec["metamagic"] = ["careful", "seeking"]
	var s: Node = own(Builder.build(spec)["creature"])
	var w := make_world(["......", "......", "......"])
	var ally := make_creature({"team": "party", "hp_max": 30})
	var foe := make_creature({"team": "enemy", "hp_max": 30, "abilities": {"dex": 1}})
	w["grid"].place(s, Vector2i(0, 1))
	w["grid"].place(ally, Vector2i(1, 1))
	w["grid"].place(foe, Vector2i(2, 1))
	s.reset_turn()
	s.options["metamagic"] = "careful"
	Dice.force([1, 3, 3, 3])
	var r: Dictionary = Spellcasting.cast(w, s, "burning_hands", Vector2i(2, 1))
	assert_true(r.get("ok", false), str(r))
	assert_eq(ally.hp, 30, "신중한 주문: 아군 피해 없음")
	assert_true(foe.hp < 30)
	s.reset_turn()
	s.options["metamagic"] = "seeking"
	var hp: int = foe.hp
	Dice.force([1, 18, 5])  # 빗나감 → 다시 18 명중 → 피해
	assert_true(Spellcasting.cast(w, s, "fire_bolt", Vector2i(2, 1)).get("ok", false))
	assert_true(foe.hp < hp, "추적 주문으로 명중")
	var spec2 := Builder.default_spec("sorcerer", 3)
	spec2["metamagic"] = ["subtle", "quickened"]
	var s2: Node = own(Builder.build(spec2)["creature"])
	assert_true(s2.has_cap("metamagic_subtle"))
