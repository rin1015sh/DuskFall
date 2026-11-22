extends "res://tests/test_case.gd"
## 전술 AI(구현 어려운 것 묶음 2)와 물체 공격, 실시간 수색 이동.

const Tactics := preload("res://scripts/ai/tactics.gd")
const Builder := preload("res://scripts/rules/character_builder.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const ExplorationScript := preload("res://scripts/rules/exploration.gd")


func _pc(cls: String, lv: int = 3) -> Node:
	var c: Node = own(Builder.build(Builder.default_spec(cls, lv))["creature"])
	c.reset_turn()
	return c


func _foe(values: Dictionary = {}) -> Node:
	var v := {"team": "enemy", "hp_max": 20, "ac_base": 10, "weight_kg": 30.0, "abilities": {"str": 3, "dex": 3}}
	v.merge(values, true)
	var c := make_creature(v)
	c.reset_turn()
	return c


func test_pick_target_prefers_weak_and_concentrating() -> void:
	var w := make_world(["......"])
	var f := _pc("fighter")
	var a := _foe()
	var b := _foe()
	w["grid"].place(f, Vector2i(0, 0))
	w["grid"].place(a, Vector2i(2, 0))
	w["grid"].place(b, Vector2i(3, 0))
	assert_eq(Tactics.pick_target(w, f), a, "가까운 쪽")
	b.hp = 2
	b.concentration = {"id": "bless"}
	assert_eq(Tactics.pick_target(w, f), b, "약하고 집중 중인 쪽")


func test_shove_off_ledge() -> void:
	var w := make_world(["220000"])
	var f := _pc("fighter")
	var e := _foe()
	w["grid"].place(f, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(1, 0))
	Dice.force([1, 1, 1, 6, 6])
	assert_true(Tactics.pre_turn(w, f))
	assert_true(w["grid"].height(w["grid"].cell_of(e)) == 0, "바위 턱에서 밀어 떨어뜨린다")


func test_explode_barrel_and_attack_object() -> void:
	var w := make_world(["..........", ".........."])
	var r := _pc("rogue")
	var a := _foe()
	var b := _foe()
	w["grid"].place(r, Vector2i(0, 0))
	w["grid"].place(a, Vector2i(6, 0))
	w["grid"].place(b, Vector2i(6, 1))
	w["grid"].place_object(Vector2i(7, 0), {"id": "oil_barrel", "material": "wood", "hp": 1, "ac": 5, "weight_kg": 60,
		"contents": {"surface": "oil", "radius": 1}})
	Dice.force([15, 4])
	assert_true(Tactics.pre_turn(w, r))
	assert_true(w["grid"].object_at(Vector2i(7, 0)).is_empty(), "적 둘 곁의 기름통을 쏴 터뜨린다")
	assert_eq(w["grid"].surface_id(Vector2i(6, 0)), "oil")


func test_ranged_takes_high_ground_and_drinks() -> void:
	var w := make_world([".33.......", "..........", ".........."])
	var r := _pc("rogue")
	var e := _foe()
	w["grid"].set_flag(Vector2i(1, 0), "climb")
	w["grid"].place(r, Vector2i(1, 1))
	w["grid"].place(e, Vector2i(8, 2))
	Tactics.pre_turn(w, r)
	assert_eq(w["grid"].height(w["grid"].cell_of(r)), 3, "원거리 공격자는 고지로")
	w["inventory"] = {"potion_of_healing": 1}
	r.reset_turn()
	r.hp = 2
	Tactics.pre_turn(w, r)
	assert_true(r.hp > 2, "위급하면 물약")
	assert_eq(int(w["inventory"]["potion_of_healing"]), 0)


func test_searching_enemy_walks_to_last_position() -> void:
	var w := make_world([".........."])
	var p := make_creature({"team": "party"})
	var o := _foe()
	w["grid"].place(p, Vector2i(0, 0))
	w["grid"].place(o, Vector2i(9, 0))
	var ex: Node = own(ExplorationScript.new().setup(w, [p]))
	o.awareness[p] = {"state": "searching", "last": Vector2i(2, 0)}
	o.facing = Vector2i(1, 0)
	p.sneaking = true
	ex.tick()
	assert_eq(w["grid"].cell_of(o), Vector2i(6, 0), "마지막 위치 쪽으로 3칸")


func test_enemies_never_shove() -> void:
	var w := make_world(["220000"])
	var e := _foe({"abilities": {"str": 18, "dex": 10}})
	var p := make_creature({"team": "party", "hp_max": 20, "weight_kg": 30.0, "abilities": {"str": 3, "dex": 3}})
	w["grid"].place(e, Vector2i(0, 0))
	w["grid"].place(p, Vector2i(1, 0))
	Tactics.pre_turn(w, e)
	assert_eq(w["grid"].cell_of(p), Vector2i(1, 0), "적은 밀치기를 쓰지 않는다")
	assert_eq(int(e.turn["bonus"]), 1)
