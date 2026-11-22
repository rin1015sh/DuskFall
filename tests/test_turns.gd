extends "res://tests/test_case.gd"
## TurnManager: 이니셔티브·동률·공유 턴·기습·전투 구역·전투 끝·실시간 틱(룰북 3단계, 2단계 동률, 7단계).


func _zone_world() -> Dictionary:
	var w := make_world(["..........", "..........", ".........."])
	for x in range(0, 6):
		for y in 3:
			w["grid"].add_zone(Vector2i(x, y), "camp")
	return w


func _pc(dex: int, values: Dictionary = {}) -> Node:
	var c := make_creature({"team": "party", "is_player_character": true, "abilities": {"dex": dex}, "hp_max": 20})
	c.setup(values)
	return c


func _foe(dex: int) -> Node:
	return make_creature({"team": "enemy", "abilities": {"dex": dex}, "hp_max": 10})


func test_initiative_order_and_ties() -> void:
	var w := _zone_world()
	var a := _pc(14)
	var b := _foe(14)
	var c := _foe(18)
	w["grid"].place(a, Vector2i(0, 0))
	w["grid"].place(b, Vector2i(1, 0))
	w["grid"].place(c, Vector2i(2, 0))
	Dice.force([10, 7, 10, 7, 8, 7])  # a: 10+2=12, b: 10+2=12, c: 8+4=12 (사이사이 동률용 굴림)
	w["turns"].start_combat("camp")
	var order: Array = w["turns"].order
	assert_eq(order[0], c, "동률이면 민첩 점수가 높은 쪽")
	assert_eq(order[1], a, "그다음 아군 우선")
	assert_eq(order[2], b)


func test_shared_turn_for_consecutive_allies() -> void:
	var w := _zone_world()
	var p1 := _pc(10)
	var p2 := _pc(10)
	var e := _foe(10)
	w["grid"].place(p1, Vector2i(0, 0))
	w["grid"].place(p2, Vector2i(0, 1))
	w["grid"].place(e, Vector2i(4, 0))
	Dice.force([20, 1, 19, 1, 2, 1])
	w["turns"].start_combat("camp")
	var tm: Node = w["turns"]
	assert_eq(tm.current_group().size(), 2, "이어진 아군은 공유 턴")
	tm.end_turn(p2)
	assert_eq(tm.current_group(), [p1], "원하는 순서로")
	tm.end_turn(p1)
	assert_eq(tm.current_group(), [e])


func test_zone_participation_and_join() -> void:
	var w := _zone_world()
	var inside := _pc(10)
	var outside := _pc(10)
	var e := _foe(10)
	w["grid"].place(inside, Vector2i(0, 0))
	w["grid"].place(outside, Vector2i(9, 0))
	w["grid"].place(e, Vector2i(3, 0))
	Dice.force([20, 1, 2, 1])
	w["turns"].start_combat("camp")
	var tm: Node = w["turns"]
	assert_false(outside in tm.order, "구역 밖 파티원은 참가하지 않는다")
	w["grid"].move_creature(outside, Vector2i(5, 0))
	assert_false(outside in tm.order, "들어와도 다음 라운드에 합류")
	Dice.force([10, 1])
	tm.end_turn(inside)
	tm.end_turn(e)
	assert_true(outside in tm.order, "다음 라운드에 합류")
	assert_eq(tm.round_number, 2)


func test_surprise_first_turn() -> void:
	var w := _zone_world()
	var p := _pc(10)
	var e := _foe(10)
	w["grid"].place(p, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(3, 0))
	Dice.force([20, 1, 2, 1])
	w["turns"].start_combat("camp", [p])
	assert_eq(p.turn["action"], 0, "기습: 첫 턴 행동 불가")
	assert_eq(p.turn["movement"], 0, "이동 불가")
	assert_false(p.can_react(), "반응 불가")
	w["turns"].end_turn(p)
	assert_false(p.has_condition("surprised"), "첫 턴이 끝나면 풀린다")
	assert_true(p.can_react())


func test_turn_start_order_effects() -> void:
	var w := _zone_world()
	var p := _pc(10)
	var e := _foe(10)
	w["grid"].place(p, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(3, 0))
	p.apply_condition("burning")
	p.turn["reaction"] = 0
	e.cooldowns["breath"] = 3
	Dice.force([20, 1, 2, 1, 2])
	w["turns"].start_combat("camp")
	assert_eq(p.hp, 18, "턴 시작: 연소 1d4")
	assert_true(p.can_react(), "반응 회복")
	w["turns"].end_turn(p)
	assert_eq(e.cooldowns["breath"], 2, "재충전 쿨다운 −1")


func test_condition_durations_tick_on_turn_end() -> void:
	var w := _zone_world()
	var p := _pc(10)
	var e := _foe(10)
	w["grid"].place(p, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(3, 0))
	Dice.force([20, 1, 2, 1])
	w["turns"].start_combat("camp")
	p.apply_condition("poisoned", 1)
	w["turns"].end_turn(p)
	assert_false(p.has_condition("poisoned"), "자기 턴 끝에 1 줄어 풀린다")


func test_combat_ends_and_downed_rise() -> void:
	var w := _zone_world()
	var p := _pc(10)
	var p2 := _pc(10)
	var e := _foe(10)
	w["grid"].place(p, Vector2i(0, 0))
	w["grid"].place(p2, Vector2i(0, 1))
	w["grid"].place(e, Vector2i(3, 0))
	Dice.force([20, 1, 19, 1, 2, 1])
	w["turns"].start_combat("camp")
	preload("res://scripts/rules/resolver.gd").apply_damage(p2, [{"amount": 20, "damage_type": "slashing"}])
	preload("res://scripts/rules/resolver.gd").apply_damage(e, [{"amount": 10, "damage_type": "slashing"}])
	w["turns"].end_turn(p)
	assert_false(w["turns"].in_combat, "적대 생물이 모두 쓰러지면 끝")
	assert_eq(p2.hp, 1, "쓰러진 동료는 안정 상태로 HP 1")


func test_enemy_leaving_zone_flees() -> void:
	var w := _zone_world()
	var p := _pc(10)
	var e := _foe(10)
	w["grid"].place(p, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(5, 0))
	Dice.force([20, 1, 2, 1])
	w["turns"].start_combat("camp")
	w["grid"].move_creature(e, Vector2i(6, 0))
	assert_true(w["turns"].in_combat, "쫓아 나간 적은 계속 참가한다")
	w["grid"].move_creature(e, Vector2i(5, 0))
	e.set_meta("fleeing", true)
	w["grid"].move_creature(e, Vector2i(6, 0))
	assert_false(w["turns"].in_combat, "도주하는 적이 구역을 벗어나면 이탈 → 전투 끝")


func test_realtime_tick_runs_turn_effects() -> void:
	var w := make_world(["...."])
	var p := _pc(10)
	w["grid"].place(p, Vector2i(0, 0))
	w["surfaces"].place_surface([Vector2i(0, 0)], "fire")
	Dice.force([2])
	w["turns"].tick()
	assert_true(p.has_condition("burning"), "탐험 중에도 6초마다 표면 효과")
	assert_eq(w["grid"].surface(Vector2i(0, 0))["turns_left"], 2, "지속시간도 흐른다")


func test_manual_turn_mode_party_only() -> void:
	var w := make_world(["...."])
	var p1 := _pc(10)
	var p2 := _pc(12)
	w["grid"].place(p1, Vector2i(0, 0))
	w["grid"].place(p2, Vector2i(1, 0))
	Dice.force([5, 1, 15, 1])
	w["turns"].start_manual([p1, p2])
	assert_eq(w["turns"].mode, "manual")
	assert_eq(w["turns"].current_group().size(), 2)


func test_party_wipe_is_defeat() -> void:
	var w := _zone_world()
	var p := _pc(10)
	var e := _foe(10)
	w["grid"].place(p, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(3, 0))
	Dice.force([2, 1, 20, 1])
	w["turns"].start_combat("camp")
	preload("res://scripts/rules/resolver.gd").apply_damage(p, [{"amount": 20, "damage_type": "slashing"}])
	w["turns"].end_turn(e)
	assert_false(w["turns"].in_combat)
	assert_eq(w["turns"].result, "defeat", "활성 파티 전원이 쓰러지면 게임 오버(7단계)")
	assert_eq(p.hp, 0, "일으키지 않는다")


func test_attacked_outsider_joins_next_round() -> void:
	var w := _zone_world()
	var p := _pc(10)
	var e := _foe(10)
	var outsider := _pc(10)
	w["grid"].place(p, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(5, 0))
	w["turns"].start_combat("camp")
	w["grid"].place(outsider, Vector2i(7, 0))
	assert_false(outsider in w["turns"].order)
	EventBus.on_after_attack_roll.emit({"attacker": e, "target": outsider})
	assert_true(outsider in w["turns"]._pending, "참가자에게 공격받으면 다음 라운드에 합류")
