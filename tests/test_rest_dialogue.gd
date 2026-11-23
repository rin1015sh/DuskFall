extends "res://tests/test_case.gd"
## 휴식·캠프(7단계), 대화·영감(5단계), 절도·목격(5단계 결정 3), 저장·불러오기(9단계).

const Rest := preload("res://scripts/rules/rest.gd")
const Dialogue := preload("res://scripts/rules/dialogue.gd")
const Interact := preload("res://scripts/rules/interact.gd")
const Goals := preload("res://scripts/rules/goals.gd")
const SaveGame := preload("res://scripts/rules/save_game.gd")


func _hero(values: Dictionary = {}) -> Node:
	var v := {"team": "party", "is_player_character": true, "hp_max": 20}
	v.merge(values, true)
	var c := make_creature(v)
	c.resources = {"second_wind": {"current": 0, "max": 2, "recharge": "short_one"},
		"action_surge": {"current": 0, "max": 1, "recharge": "short"},
		"spell_slot_1": {"current": 0, "max": 4, "recharge": "long"}}
	return c


func test_short_rest_twice_half_hp() -> void:
	var w := make_world(["...."])
	var c := _hero()
	w["grid"].place(c, Vector2i(0, 0))
	c.hp = 2
	assert_true(Rest.short_rest(w, [c])["ok"])
	assert_eq(c.hp, 12, "최대 HP 절반 회복")
	assert_eq(c.resource("second_wind"), 1, "짧은 휴식 1개 회복")
	assert_eq(c.resource("action_surge"), 1, "짧은 휴식 전부 회복")
	assert_eq(c.resource("spell_slot_1"), 0, "긴 휴식 자원은 그대로")
	assert_true(Rest.short_rest(w, [c])["ok"])
	assert_eq(c.hp, 20)
	assert_false(Rest.short_rest(w, [c])["ok"], "긴 휴식 사이 2회")


func test_short_rest_blocked_by_aware_enemy_and_ends_effects() -> void:
	var w := make_world(["....."])
	var c := _hero()
	var o := make_creature({"team": "enemy"})
	w["grid"].place(c, Vector2i(0, 0))
	w["grid"].place(o, Vector2i(4, 0))
	o.awareness[c] = {"state": "suspicious", "last": Vector2i(0, 0)}
	assert_false(Rest.short_rest(w, [c])["ok"], "적이 의심 단계 이상이면 불가")
	o.awareness.clear()
	c.apply_condition("blessed" if not RulesDB.get_entry("condition", "blessed").is_empty() else "wet", 100)
	c.apply_condition("prone", -1)
	assert_true(Rest.short_rest(w, [c])["ok"])
	assert_false(c.has_condition("wet") or c.has_condition("blessed"), "1시간이 흘러 100턴 이하 효과가 끝난다")
	assert_true(c.has_condition("prone"), "시간 제한 없는 상태는 남는다")


func test_long_rest_supplies_and_partial() -> void:
	var w := make_world(["...."])
	var c := _hero({"species_id": "human", "caps": ["long_rest_inspiration"]})  # 인간 기지(종족 기능 caps)
	w["grid"].place(c, Vector2i(0, 0))
	c.hp = 3
	w["short_rests_left"] = 0
	Interact.give(w, "rations", 3)  # 30
	assert_eq(Rest.supplies(w), 30)
	var r := Rest.long_rest(w, [c])
	assert_true(r["partial"], "보급품이 모자라면 부분 휴식")
	assert_eq(c.hp, 10, "HP 최대치 절반까지")
	assert_eq(c.resource("spell_slot_1"), 2, "슬롯 절반까지")
	assert_eq(w["short_rests_left"], 0, "짧은 휴식 충전 없음")
	assert_eq(int(w.get("inspiration", 0)), 0, "부분 휴식에는 인간 기지 영감이 없다")
	w["party_resources"] = {"camp_supplies": 15}
	r = Rest.long_rest(w, [c])
	assert_false(r["partial"])
	assert_eq(c.hp, 20)
	assert_eq(c.resource("spell_slot_1"), 4)
	assert_eq(w["short_rests_left"], 2)
	assert_eq(w["inspiration"], 1, "인간 기지: 긴 휴식에 공용 영감 +1")
	assert_eq(w["party_resources"]["camp_supplies"], 0, "주문 보급품을 먼저 쓴다")
	assert_eq(Interact.count(w, "rations"), 0, "15 + 식량 3개 = 45 ≥ 40")


func test_no_camp_zone_and_tiny_hut() -> void:
	var w := make_world(["...."])
	var c := _hero()
	w["grid"].place(c, Vector2i(0, 0))
	w["grid"].set_flag(Vector2i(0, 0), "no_camp")
	assert_false(Rest.long_rest(w, [c])["ok"])
	assert_true(Rest.long_rest(w, [c], {"tiny_hut": true})["ok"], "Tiny Hut이면 캠프 불가 구역에서도")


func test_camp_revive_and_inspiration_cap() -> void:
	var w := {"inventory": {"gold": 250}}
	var c := _hero()
	c.dead = true
	assert_true(Rest.camp_revive(w, c)["ok"])
	assert_false(c.dead)
	assert_eq(c.hp, 1)
	assert_eq(Interact.count(w, "gold"), 50)
	assert_false(Rest.pay_respec(w)["ok"], "100gp가 없으면 재분배 불가")
	w["inspiration"] = 3
	assert_eq(Rest.add_inspiration(w, 2), 1, "4점이 상한")
	assert_eq(w["inspiration"], 4)


func test_background_goal_gives_inspiration_once() -> void:
	var c := _hero({"background_id": "soldier"})
	var w := {"party": [c], "inspiration": 0}
	assert_eq(Goals.complete(w, "intimidate_foe"), "inspiration")
	assert_eq(Goals.complete(w, "intimidate_foe"), "", "목표마다 한 번")
	assert_eq(Goals.complete(w, "pick_lock"), "", "파티에 그 배경이 없다")
	w["inspiration"] = 4
	assert_eq(Goals.complete(w, "protect_ally"), "xp", "가득이면 경험치")


func test_dialogue_check_auto_insight_and_tags() -> void:
	var w := make_world(["...."])
	var c := _hero({"abilities": {"cha": 14, "wis": 14}, "background_id": "soldier"})
	w["grid"].place(c, Vector2i(0, 0))
	w["party"] = [c]
	w["inventory"] = {"gold": 20}
	Dice.force([15])  # 자동 통찰 15 + 2 ≥ 12
	var d: RefCounted = Dialogue.start(w, "goblin_toll", c)
	assert_true(d != null)
	assert_eq(d.extra_lines.size(), 1, "통찰 자동 판정 성공 → 추가 대사")
	var opts: Array = d.options()
	assert_eq(opts.size(), 4, "속마음 읽기 선택지는 태그가 없어 숨는다")
	assert_eq(opts[0]["dc"], 20, "기본 15 + 적대 5")
	assert_eq(opts[1]["dc"], 12)
	Dice.force([14])  # 14 + 2 = 16 ≥ 12
	var r: Dictionary = d.choose(1)
	assert_true(r["check"]["success"])
	assert_eq(d.node_id, "flee")
	assert_true(d.finished)
	assert_true(w["flags"].has("goblin_toll_passed"))
	assert_eq(w["inspiration"], 1, "병사 목표(위협) 달성 → 영감")


func test_dialogue_spell_unlock_and_hostile() -> void:
	var w := make_world(["....."])
	var c := _hero({"abilities": {"wis": 6}})
	var npc := make_creature({"team": "neutral", "faction": "goblins"})
	var buddy := make_creature({"team": "neutral", "faction": "goblins"})
	w["grid"].place(c, Vector2i(0, 0))
	w["grid"].place(npc, Vector2i(2, 0))
	w["grid"].place(buddy, Vector2i(4, 0))
	for cell in w["grid"].all_cells():
		w["grid"].add_zone(cell, "road")
	w["dialogue_tags"] = {"thoughts": true}
	w["inventory"] = {"gold": 20}
	Dice.force([2])  # 통찰 실패
	var d: RefCounted = Dialogue.start(w, "goblin_toll", c, npc)
	assert_eq(d.options().size(), 4, "통찰 실패: 위협 숨김, 속마음 읽기 보임")
	d.choose(2)
	assert_eq(d.node_id, "secret")
	assert_true(w["flags"].has("knows_cave_chest"))
	d.choose(0)
	assert_eq(d.node_id, "greet")
	d.choose(4)
	assert_eq(d.outcome, "hostile")
	assert_eq(npc.team, "enemy")
	assert_eq(buddy.team, "enemy", "같은 세력도 적대")


func test_gold_option_hidden_without_gold() -> void:
	var w := make_world(["...."])
	var c := _hero()
	w["grid"].place(c, Vector2i(0, 0))
	Dice.force([2])
	var d: RefCounted = Dialogue.start(w, "goblin_toll", c)
	assert_false(d.options().any(func(o: Dictionary) -> bool: return o["text"]["en"].contains("20 gold")), "금화가 모자라면 내는 선택지가 숨는다")


func test_dialogue_not_in_combat() -> void:
	var w := make_world(["...."])
	var c := _hero()
	w["grid"].place(c, Vector2i(0, 0))
	w["turns"].start_manual([c])
	assert_true(Dialogue.start(w, "goblin_toll", c) == null, "전투 중 대화 불가")


func test_theft_witnessed_in_cone() -> void:
	var w := make_world(["......"])
	var g: Node = w["grid"]
	var thief := _hero({"background_id": "criminal"})
	var shop := make_creature({"team": "neutral", "faction": "merchants"})
	shop.facing = Vector2i(-1, 0)
	w["party"] = [thief]
	g.place(thief, Vector2i(1, 0))
	g.place(shop, Vector2i(5, 0))
	g.place_object(Vector2i(0, 0), {"id": "chest", "loot": {"potion_of_healing": 1}, "owner": "merchants", "owner_dialogue": "goblin_toll"})
	var r := Interact.take_loot(w, thief, Vector2i(0, 0))
	assert_true(r["stolen"] and r.get("witness") == shop, "원뿔 안에서 훔치면 들킨다")
	assert_eq(w["pending_dialogue"]["npc"], shop)
	assert_eq(Interact.count(w, "potion_of_healing"), 1)
	shop.facing = Vector2i(1, 0)
	g.place_object(Vector2i(0, 0), {"id": "chest", "loot": {"gold": 5}, "owner": "merchants"})
	r = Interact.take_loot(w, thief, Vector2i(0, 0))
	assert_false(r.has("witness"), "등 뒤에서는 안 들킨다")
	assert_eq(w["inspiration"], 1, "범죄자 목표(몰래 훔치기)")


func test_save_and_restore() -> void:
	var w := make_world(["....."])
	var g: Node = w["grid"]
	var c := _hero()
	c.name = "hero"
	g.place(c, Vector2i(0, 0))
	g.place_object(Vector2i(3, 0), {"id": "chest", "lock": {"dc": 15, "key": "", "locked": true}})
	w["inventory"] = {"gold": 12, "rations": 2}
	w["inspiration"] = 2
	w["options"] = {"seed_lock": true}
	c.apply_condition("prone", -1)
	var snap := SaveGame.snapshot(w)
	var text := JSON.stringify(snap)
	var a: int = Dice.roll("1d20")["total"]
	# 바꾼 뒤 되돌리기
	c.hp = 1
	g.move_creature(c, Vector2i(4, 0))
	w["inventory"]["gold"] = 0
	g.object_at(Vector2i(3, 0))["lock"]["locked"] = false
	c.remove_condition("prone")
	assert_true(SaveGame.restore(w, JSON.parse_string(text)))
	assert_eq(c.hp, 20)
	assert_eq(g.cell_of(c), Vector2i(0, 0))
	assert_eq(Interact.count(w, "gold"), 12)
	assert_true(g.object_at(Vector2i(3, 0))["lock"]["locked"])
	assert_true(c.has_condition("prone"))
	assert_eq(Dice.roll("1d20")["total"], a, "시드 고정 옵션: 불러와도 같은 굴림")


func test_save_recasts_lasting_buffs() -> void:
	var w := make_world(["....."])
	var g: Node = w["grid"]
	var wz: Node = own(preload("res://scripts/rules/character_builder.gd").build(preload("res://scripts/rules/character_builder.gd").default_spec("wizard", 5))["creature"])
	wz.name = "wiz"
	g.place(wz, Vector2i(0, 0))
	wz.spells.append("fly")
	wz.reset_turn()
	assert_true(preload("res://scripts/rules/spellcasting.gd").cast(w, wz, "fly", Vector2i(0, 0))["ok"])
	wz.concentration["turns_left"] = 40
	var slots: int = wz.resource("spell_slot_3")
	var snap: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.snapshot(w)))
	wz.break_concentration("시험")
	assert_false(wz.has_condition("flying"))
	assert_true(SaveGame.restore(w, snap))
	assert_true(wz.has_condition("flying"), "지속 주문을 다시 건다")
	assert_eq(wz.altitude, 2)
	assert_eq(int(wz.concentration.get("turns_left", 0)), 40, "남은 집중 시간 이어서")
	assert_eq(wz.resource("spell_slot_3"), slots, "슬롯을 쓰지 않는다")
