extends "res://tests/test_case.gd"
## 2구간 몬스터(도전 등급 11~15): 생성, 전설적 저항, 지옥의 상처, 번개 폭풍(원기둥 범위), 성룡 숨결(선).

const MF := preload("res://scripts/rules/monster_factory.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")

const IDS := ["remorhaz", "horned_devil", "adult_white_dragon", "storm_giant", "ice_devil", "adult_black_dragon", "adult_green_dragon"]


func test_spawn_all() -> void:
	for id: String in IDS:
		var m: Node = own(MF.spawn(id))
		assert_true(m != null and m.hp_max >= 195, id)
		assert_true(float(RulesDB.get_entry("monster", id)["cr"]) >= 11)


func test_legendary_resistance() -> void:
	var d: Node = own(MF.spawn("adult_green_dragon"))
	for i in 3:
		Dice.force([1])
		assert_true(Resolver.saving_throw(d, "wis", 30)["success"], "전설적 저항 %d" % (i + 1))
	Dice.force([1])
	assert_false(Resolver.saving_throw(d, "wis", 30)["success"], "3회 뒤에는 실패")


func test_infernal_tail_wound() -> void:
	var w := make_world([".........."])
	var dv: Node = own(MF.spawn("horned_devil"))
	var t := make_creature({"team": "party", "hp_max": 200})
	w["grid"].place(dv, Vector2i(0, 0), 2)
	w["grid"].place(t, Vector2i(3, 0))
	dv.reset_turn()
	Dice.force([1])
	assert_true(Combat.monster_action(w, dv, "infernal_tail", t).get("ok", false))
	assert_true(t.has_condition("infernal_wound"))
	var hp: int = t.hp
	Resolver.start_turn(t, {"in_combat": true})
	assert_true(t.hp < hp, "턴 시작 3d6")


func test_area_breath_and_storm() -> void:
	var w := make_world(["....................", "....................", "....................", "...................."])
	var g: Node = own(MF.spawn("storm_giant"))
	var a := make_creature({"team": "party", "hp_max": 300})
	var b := make_creature({"team": "party", "hp_max": 300})
	var far := make_creature({"team": "party", "hp_max": 300})
	w["grid"].place(g, Vector2i(0, 0), 3)
	w["grid"].place(a, Vector2i(15, 1))
	w["grid"].place(b, Vector2i(16, 2))
	w["grid"].place(far, Vector2i(19, 3))
	g.reset_turn()
	assert_true(Combat.monster_action(w, g, "lightning_storm", a).get("ok", false))
	assert_true(a.hp < 300 and b.hp < 300, "반지름 2칸 원기둥")
	assert_eq(far.hp, 300)
	var d: Node = own(MF.spawn("adult_black_dragon"))
	var w2 := make_world(["....................", "....................", "...................."])
	var c := make_creature({"team": "party", "hp_max": 300})
	var side := make_creature({"team": "party", "hp_max": 300})
	w2["grid"].place(d, Vector2i(0, 0), 3)
	w2["grid"].place(c, Vector2i(10, 1))
	w2["grid"].place(side, Vector2i(10, 0) + Vector2i(0, 2))
	d.reset_turn()
	assert_true(Combat.monster_action(w2, d, "acid_breath", c).get("ok", false))
	assert_true(c.hp < 300, "선 숨결")
