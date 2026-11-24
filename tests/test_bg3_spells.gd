extends "res://tests/test_case.gd"
## BG3 수치 우선(2026-11-24) 주문 재정렬: 치료 1d8·치유의 말 1d4, 인도(능력 판정 +1d4)·저항(내성 +1d4) 등(룰북 6단계, 주문 변환표).

const Builder := preload("res://scripts/rules/character_builder.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func _pc(class_id: String, level: int) -> Node:
	var r := Builder.build(Builder.default_spec(class_id, level))
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func _world() -> Dictionary:
	var rows: Array = []
	for i in 12:
		rows.append("....................")
	return make_world(rows)


func _cast(w: Dictionary, c: Node, sid: String, aim: Vector2i, opts: Dictionary = {}) -> Dictionary:
	if not c.spells.has(sid):
		c.spells.append(sid)
	c.reset_turn()
	return Spellcasting.cast(w, c, sid, aim, opts)


func test_heal_dice_bg3() -> void:
	var cw := RulesDB.get_entry("spell", "cure_wounds")
	assert_eq(str(cw["effects"]["apply"][0]["dice"]), "1d8", "치료 1d8 + 수정치")
	assert_eq(str(cw["upcast"]["per_slot_level"]["dice_add"]), "1d8")
	var hw := RulesDB.get_entry("spell", "healing_word")
	assert_eq(str(hw["effects"]["apply"][0]["dice"]), "1d4", "치유의 말 1d4 + 수정치")
	assert_eq(str(hw["upcast"]["per_slot_level"]["dice_add"]), "1d4")


func test_guidance_adds_d4_to_any_ability_check() -> void:
	var w := _world()
	var cl := _pc("cleric", 1)
	var f := _pc("fighter", 1)
	w["grid"].place(cl, Vector2i(0, 0))
	w["grid"].place(f, Vector2i(1, 0))
	_cast(w, cl, "guidance", Vector2i(1, 0))
	Dice.force([10, 4])
	var r := Resolver.ability_check(f, "int", 30)
	assert_eq(int(r["total"]), 10 + f.ability_mod("int") + 4, "기능 고르기 없이 모든 능력 판정 +1d4")


func test_resistance_adds_d4_to_saves() -> void:
	var w := _world()
	var cl := _pc("cleric", 1)
	var f := _pc("fighter", 1)
	w["grid"].place(cl, Vector2i(0, 0))
	w["grid"].place(f, Vector2i(1, 0))
	_cast(w, cl, "resistance", Vector2i(1, 0))
	Dice.force([10, 3])
	var r := Resolver.saving_throw(f, "wis", 30)
	assert_eq(int(r["total"]), 10 + int(r["bonus"]) + 3, "내성 굴림 +1d4")


func _foe(hp: int) -> Node:
	var c := make_creature({"team": "enemy", "hp_max": hp, "abilities": {"wis": 30}})
	return c


func test_sleep_hp_pool_lowest_first_no_save() -> void:
	var w := _world()
	var wz := _pc("wizard", 3)
	var a := _foe(10)
	var b := _foe(12)
	var c := _foe(9)
	w["grid"].place(wz, Vector2i(0, 0))
	w["grid"].place(a, Vector2i(6, 0))
	w["grid"].place(b, Vector2i(7, 0))
	w["grid"].place(c, Vector2i(6, 1))
	assert_true(_cast(w, wz, "sleep", Vector2i(6, 0)).get("ok", false))
	# 총량 24: 9 → 10 (19), 12는 남은 5를 넘어 못 재운다. 지혜 30이라도 내성 없음
	assert_true(c.has_condition("unconscious") and a.has_condition("unconscious"), "낮은 HP부터")
	assert_false(b.has_condition("unconscious"), "총량을 넘는 생물은 못 재운다")
	Resolver.apply_damage(a, [{"amount": 1, "damage_type": "fire"}])
	assert_false(a.has_condition("unconscious"), "피해를 받으면 깬다")


func test_sleep_upcast_pool_and_immunity() -> void:
	var sp := RulesDB.get_entry("spell", "sleep")
	assert_eq(load("res://scripts/rules/effects/hp_pool.gd").pool(sp, 1), 24)
	assert_eq(load("res://scripts/rules/effects/hp_pool.gd").pool(sp, 3), 40, "슬롯마다 +8")
	var w := _world()
	var wz := _pc("wizard", 3)
	var u := make_creature({"team": "enemy", "hp_max": 5, "creature_type": "undead"})
	w["grid"].place(wz, Vector2i(0, 0))
	w["grid"].place(u, Vector2i(4, 0))
	_cast(w, wz, "sleep", Vector2i(4, 0))
	assert_false(u.has_condition("unconscious"), "언데드는 잠들지 않는다")


func test_color_spray_blinds_by_hp_pool() -> void:
	var w := _world()
	var wz := _pc("wizard", 1)
	var a := _foe(20)
	var b := _foe(20)
	w["grid"].place(wz, Vector2i(0, 0))
	w["grid"].place(a, Vector2i(1, 0))
	w["grid"].place(b, Vector2i(2, 0))
	_cast(w, wz, "color_spray", Vector2i(3, 0))
	assert_eq(int(a.has_condition("blinded")) + int(b.has_condition("blinded")), 1, "33 총량 — 20짜리 하나만")


func test_prayer_of_healing_heals_allies_around() -> void:
	var w := _world()
	var cl := _pc("cleric", 3)
	var f := _pc("fighter", 3)
	var far := _pc("fighter", 3)
	var e := _foe(30)
	w["grid"].place(cl, Vector2i(0, 0))
	w["grid"].place(f, Vector2i(3, 0))
	w["grid"].place(far, Vector2i(10, 0))
	w["grid"].place(e, Vector2i(2, 2))
	for c: Node in [f, far, e]:
		c.hp = 1
	_cast(w, cl, "prayer_of_healing", Vector2i(0, 0))
	assert_true(f.hp > 1, "6칸 안 아군")
	assert_eq(far.hp, 1, "6칸 밖")
	assert_eq(e.hp, 1, "적은 아니다")
