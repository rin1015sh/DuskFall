extends "res://tests/test_case.gd"
## 1구간 몬스터(도전 등급 6~10): 생성, 용의 숨결(원뿔 범위 내성 — 성공 절반), 망치 던지기(밀기), 마법 저항, 거대 크기 3×3.

const MF := preload("res://scripts/rules/monster_factory.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")

const IDS := ["wyvern", "chimera", "young_white_dragon", "stone_giant", "frost_giant", "young_green_dragon", "fire_giant", "stone_golem", "young_red_dragon"]


func test_spawn_all() -> void:
	for id: String in IDS:
		var m: Node = own(MF.spawn(id))
		assert_true(m != null and m.hp_max > 100, id)
		assert_true(float(RulesDB.get_entry("monster", id)["cr"]) >= 6)
	assert_eq(int(own(MF.spawn("fire_giant")).get_meta("cells")), 3, "거대 = 3×3")


func test_dragon_breath_cone() -> void:
	var w := make_world(["..............", "..............", "..............", "..............", ".............."])
	var d: Node = own(MF.spawn("young_red_dragon"))
	var a := make_creature({"team": "party", "hp_max": 200})
	var b := make_creature({"team": "party", "hp_max": 200})
	var far := make_creature({"team": "party", "hp_max": 200})
	w["grid"].place(d, Vector2i(0, 1), 2)
	w["grid"].place(a, Vector2i(3, 1))
	w["grid"].place(b, Vector2i(5, 2))
	w["grid"].place(far, Vector2i(13, 4))
	d.reset_turn()
	var forced: Array = [1, 20]  # a 실패, b 성공
	for i in 16:
		forced.append(3)
	Dice.force(forced)
	var r := Combat.monster_action(w, d, "fire_breath", a)
	assert_true(r.get("ok", false), str(r))
	assert_eq(a.hp, 200 - 48, "실패: 16d6")
	assert_eq(b.hp, 200 - 24, "성공: 절반")
	assert_eq(far.hp, 200, "원뿔 밖")
	assert_eq(int(d.cooldowns["fire_breath"]), 3, "재충전 5~6 → 3턴")


func test_hammer_throw_push() -> void:
	var w := make_world(["...................."])
	var g: Node = own(MF.spawn("fire_giant"))
	var t := make_creature({"team": "party", "hp_max": 200, "ac_base": 1})
	w["grid"].place(g, Vector2i(0, 0), 1)
	w["grid"].place(t, Vector2i(6, 0))
	g.reset_turn()
	Dice.force([15])
	var r := Combat.monster_action(w, g, "hammer_throw", t, "ranged")
	assert_true(r.get("hit", false))
	assert_eq(w["grid"].cell_of(t), Vector2i(9, 0), "3칸 밀림")


func test_magic_resistance() -> void:
	var w := make_world(["....."])
	var golem: Node = own(MF.spawn("stone_golem"))
	w["grid"].place(golem, Vector2i(0, 0), 2)
	var s := Resolver.saving_throw(golem, "dex", 15, {"magic": true})
	assert_eq(int(s["mode"]), 1, "주문 내성 유리")
	assert_eq(int(Resolver.saving_throw(golem, "dex", 15)["mode"]), 0)


func test_huge_moves() -> void:
	var w := make_world(["..........", "..........", "..........", "..........", ".........."])
	var g: Node = own(MF.spawn("stone_giant"))
	w["grid"].place(g, Vector2i(0, 0), 3)
	assert_eq(w["grid"].occupied_cells(g).size(), 9)
	g.reset_turn()
	var r := Combat.move(w, g, Vector2i(5, 1))
	assert_true(r.get("ok", r.get("valid", false)), str(r))
	assert_eq(w["grid"].cell_of(g), Vector2i(5, 1))
