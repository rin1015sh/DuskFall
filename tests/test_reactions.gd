extends "res://tests/test_case.gd"
## 기회 공격과 반응 설정(룰북 3단계 기회 공격·반응, 8단계 우선순위 규칙 4).

const Combat := preload("res://scripts/rules/combat.gd")


func _make(team: String, main: String = "longsword", values: Dictionary = {}) -> Node:
	var c := make_creature({"team": team, "abilities": {"str": 16, "dex": 12}, "hp_max": 40, "ac_base": 10,
		"weapon_proficiencies": ["simple", "martial"],
		"weapon_sets": {"melee": {"main": main, "off": ""}, "ranged": {"main": "shortbow"}}})
	c.setup(values)
	return c


func test_leaving_reach_provokes() -> void:
	var w := make_world(["......"])
	var mover := _make("party")
	var guard := _make("enemy")
	w["grid"].place(mover, Vector2i(1, 0))
	w["grid"].place(guard, Vector2i(2, 0))
	var p: Dictionary = Combat.preview_move(w, mover, Vector2i(0, 0))
	assert_eq(p["opportunity_attacks"].size(), 1, "미리보기에 기회 공격 지점")
	Dice.force([15, 4])
	Combat.move(w, mover, Vector2i(0, 0))
	assert_eq(mover.hp, 33, "기회 공격 명중 4 + 3")
	assert_eq(guard.turn["reaction"], 0, "반응 소모")


func test_disengage_forced_and_ranged_wielder() -> void:
	var w := make_world(["......"])
	var mover := _make("party")
	var guard := _make("enemy")
	w["grid"].place(mover, Vector2i(1, 0))
	w["grid"].place(guard, Vector2i(2, 0))
	Combat.disengage(mover)
	Combat.move(w, mover, Vector2i(0, 0))
	assert_eq(guard.turn["reaction"], 1, "이탈하면 유발 안 함")
	w["grid"].move_creature(mover, Vector2i(1, 0))
	w["grid"].move_creature(mover, Vector2i(0, 0))
	assert_eq(guard.turn["reaction"], 1, "강제 이동은 유발 안 함")
	var archer := _make("enemy")
	Combat.switch_weapon_set(archer)
	var w2 := make_world(["......"])
	var m2 := _make("party")
	w2["grid"].place(m2, Vector2i(1, 0))
	w2["grid"].place(archer, Vector2i(2, 0))
	assert_eq(Combat.preview_move(w2, m2, Vector2i(0, 0))["opportunity_attacks"].size(), 0, "원거리 무기를 들면 불가")


func test_reach_weapon_two_tiles() -> void:
	var w := make_world([".......", "......."])
	var mover := _make("party")
	var guard := _make("enemy", "glaive")
	w["grid"].place(mover, Vector2i(2, 0))
	w["grid"].place(guard, Vector2i(4, 0))
	assert_eq(Combat.preview_move(w, mover, Vector2i(1, 0))["opportunity_attacks"].size(), 1, "리치 무기 2칸")


func test_moving_within_reach_does_not_provoke() -> void:
	var w := make_world(["...", "...", "..."])
	var mover := _make("party")
	var guard := _make("enemy")
	w["grid"].place(mover, Vector2i(0, 0))
	w["grid"].place(guard, Vector2i(1, 1))
	assert_eq(Combat.preview_move(w, mover, Vector2i(2, 0))["opportunity_attacks"].size(), 0, "도달 안에서 움직이면 없음")


func test_reaction_settings() -> void:
	var w := make_world(["......"])
	var mover := _make("party")
	var guard := _make("enemy")
	w["grid"].place(mover, Vector2i(1, 0))
	w["grid"].place(guard, Vector2i(2, 0))
	guard.reaction_settings["opportunity_attack"] = "off"
	Combat.move(w, mover, Vector2i(0, 0))
	assert_eq(guard.turn["reaction"], 1, "끄기")
	var w2 := make_world(["......"])
	var m2 := _make("party")
	var g2 := _make("enemy")
	w2["grid"].place(m2, Vector2i(1, 0))
	w2["grid"].place(g2, Vector2i(2, 0))
	g2.reaction_settings["opportunity_attack"] = "ask"
	var asked: Array = []
	w2["reactions"].ask_callback = func(c: Node, id: String, _info: Dictionary) -> bool:
		asked.append([c, id])
		return false
	Combat.move(w2, m2, Vector2i(0, 0))
	assert_eq(asked, [[g2, "opportunity_attack"]], "매번 묻기")
	assert_eq(g2.turn["reaction"], 1, "아니요 → 쓰지 않음")


func test_multiple_reactions_in_initiative_order() -> void:
	var w := make_world(["....", "...."])
	var mover := _make("party")
	var a := _make("enemy")
	var b := _make("enemy")
	a.initiative = 5
	b.initiative = 15
	w["grid"].place(mover, Vector2i(1, 0))
	w["grid"].place(a, Vector2i(2, 0))
	w["grid"].place(b, Vector2i(2, 1))
	Dice.force([2, 2])
	Combat.move(w, mover, Vector2i(0, 0))
	var order: Array = w["reactions"].history.map(func(h: Dictionary) -> Node: return h["creature"])
	assert_eq(order, [b, a], "이니셔티브 순")


func test_one_reaction_per_round() -> void:
	var w := make_world([".....", "....."])
	var m1 := _make("party")
	var m2 := _make("party")
	var guard := _make("enemy")
	w["grid"].place(m1, Vector2i(1, 0))
	w["grid"].place(m2, Vector2i(1, 1))
	w["grid"].place(guard, Vector2i(2, 0))
	Dice.force([2])
	Combat.move(w, m1, Vector2i(0, 0))
	Combat.move(w, m2, Vector2i(0, 1))
	assert_eq(m2.hp, 40, "반응은 라운드마다 1회")
