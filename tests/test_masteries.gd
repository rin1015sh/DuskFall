extends "res://tests/test_case.gd"
## 무기 마스터리 8종과 가벼운 무기 보조 공격(SRD 5.2.1 Mastery Properties, 룰북 3단계 보조 무기 공격).

const Combat := preload("res://scripts/rules/combat.gd")


func _attacker(main: String, off: String = "", values: Dictionary = {}) -> Node:
	var c := make_creature({"team": "party", "abilities": {"str": 16, "dex": 16}, "hp_max": 30,
		"weapon_proficiencies": ["simple", "martial"], "weapon_masteries": [main, off],
		"weapon_sets": {"melee": {"main": main, "off": off}, "ranged": {"main": "shortbow"}}})
	c.setup(values)
	return c


func _foe(values: Dictionary = {}) -> Node:
	var c := make_creature({"team": "enemy", "ac_base": 12, "hp_max": 40, "abilities": {"con": 10}})
	c.setup(values)
	return c


func _world(a: Node, foes: Array, cells: Array) -> Dictionary:
	var w := make_world([".......", ".......", "......."])
	w["grid"].place(a, Vector2i(1, 1))
	for i in foes.size():
		w["grid"].place(foes[i], cells[i])
	return w


func test_topple() -> void:
	var a := _attacker("maul")
	var f := _foe()
	var w := _world(a, [f], [Vector2i(2, 1)])
	Dice.force([15, 3, 3, 5])  # 명중, 2d6, 건강 내성 5 < DC 13
	var r := Combat.attack(w, a, f)
	assert_eq(r["topple"]["dc"], 13, "8 + 근력 3 + 숙련 2")
	assert_true(f.has_condition("prone"))


func test_sap_and_vex() -> void:
	var a := _attacker("mace")
	var f := _foe()
	var w := _world(a, [f], [Vector2i(2, 1)])
	Dice.force([15, 3])
	Combat.attack(w, a, f)
	assert_eq(Combat.preview_attack(w, f, a, {"weapon": "unarmed"})["mode"], -1, "Sap: 다음 공격 불리")
	f.turn = {"action": 1, "attacks_left": 0}
	Dice.force([10])
	Combat.attack(w, f, a, {"weapon": "unarmed"})
	assert_eq(Combat.preview_attack(w, f, a, {"weapon": "unarmed"})["mode"], 0, "한 번 쓰면 사라진다")
	var v := _attacker("rapier")
	var f2 := _foe()
	var w2 := _world(v, [f2], [Vector2i(2, 1)])
	Dice.force([15, 3])
	Combat.attack(w2, v, f2)
	assert_eq(Combat.preview_attack(w2, v, f2)["mode"], 1, "Vex: 그 대상 다음 공격 유리")


func test_graze_on_miss() -> void:
	var a := _attacker("greatsword")
	var f := _foe({"ac_base": 30})
	var w := _world(a, [f], [Vector2i(2, 1)])
	Dice.force([5])
	var r := Combat.attack(w, a, f)
	assert_false(r["hit"])
	assert_eq(f.hp, 37, "빗나가도 능력 수정치 3")


func test_cleave_second_target_no_mod() -> void:
	var a := _attacker("greataxe")
	var f1 := _foe()
	var f2 := _foe()
	var w := _world(a, [f1, f2], [Vector2i(2, 1), Vector2i(2, 2)])
	Dice.force([15, 6, 15, 6])
	var r := Combat.attack(w, a, f1)
	assert_eq(f1.hp, 31, "6 + 3")
	assert_eq(f2.hp, 34, "두 번째 대상은 능력 수정치 없이 6")
	assert_true(r.has("cleave"))
	a.turn["attacks_left"] = 1
	Dice.force([15, 6])
	r = Combat.attack(w, a, f1)
	assert_false(r.has("cleave"), "턴당 한 번")


func test_push_mastery() -> void:
	var a := _attacker("warhammer")
	var f := _foe()
	var w := _world(a, [f], [Vector2i(2, 1)])
	Dice.force([15, 3])
	Combat.attack(w, a, f)
	assert_eq(w["grid"].cell_of(f), Vector2i(4, 1), "공격자에게서 2칸")


func test_slow_mastery() -> void:
	var a := _attacker("club")
	var f := _foe({"speed_tiles": 6})
	var w := _world(a, [f], [Vector2i(2, 1)])
	Dice.force([15, 2])
	Combat.attack(w, a, f)
	assert_eq(f.speed(), 4, "속도 −2칸")
	a.turn["attacks_left"] = 1
	Dice.force([15, 2])
	Combat.attack(w, a, f)
	assert_eq(f.speed(), 4, "여러 번 맞아도 10피트까지만")
	w["turns"].begin_turn(a)
	assert_eq(f.speed(), 6, "공격자의 다음 턴 시작에 풀린다")


func test_offhand_light_attack_no_mod() -> void:
	var a := _attacker("shortsword", "dagger", {"weapon_masteries": []})
	var f := _foe()
	var w := _world(a, [f], [Vector2i(2, 1)])
	assert_false(Combat.offhand_attack(w, a, f)["ok"], "공격 행동에서 먼저 가벼운 무기로 공격해야")
	Dice.force([15, 4])
	Combat.attack(w, a, f)
	Dice.force([15, 4])
	var r := Combat.offhand_attack(w, a, f)
	assert_eq(r["damage"]["total"], 4, "보조 공격 피해에 능력 수정치 없음")
	assert_eq(a.turn["bonus"], 0, "보너스 행동")
	a.features.append("two_weapon_fighting")
	assert_eq(Combat.build_weapon_attack(a, "dagger", {"hand": "off"})["damage"][0]["dice"], "1d4+3", "Two-Weapon Fighting이면 더함")


func test_nick_makes_offhand_part_of_attack() -> void:
	var a := _attacker("shortsword", "scimitar")
	var f := _foe()
	var w := _world(a, [f], [Vector2i(2, 1)])
	Dice.force([15, 4, 15, 4])
	Combat.attack(w, a, f)
	Combat.offhand_attack(w, a, f)
	assert_eq(a.turn["bonus"], 1, "Nick: 보너스 행동을 쓰지 않는다")


func test_no_mastery_without_feature() -> void:
	var a := _attacker("maul", "", {"weapon_masteries": []})
	var f := _foe()
	var w := _world(a, [f], [Vector2i(2, 1)])
	Dice.force([15, 3, 3])
	var r := Combat.attack(w, a, f)
	assert_false(r.has("topple"), "마스터리 기능이 없으면 발동하지 않는다")
