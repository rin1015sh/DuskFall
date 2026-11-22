extends "res://tests/test_case.gd"
## 7단계 수직 슬라이스: 경험치·레벨 업·동료 영입, 구역 보상, 발견 시 대화, 평화 해결, 구역 맵(fallen_watch) 점검.

const Progression := preload("res://scripts/rules/progression.gd")
const Builder := preload("res://scripts/rules/character_builder.gd")
const Dialogue := preload("res://scripts/rules/dialogue.gd")
const ExplorationScript := preload("res://scripts/rules/exploration.gd")
const WorldBuilder := preload("res://scripts/rules/world_builder.gd")


func _pc(cls: String, lv: int = 1) -> Node:
	var c: Node = Builder.build(Builder.default_spec(cls, lv))["creature"]
	return own(c)


func test_xp_table_and_level_up_keeps_damage() -> void:
	assert_eq(Progression.level_for(0), 1)
	assert_eq(Progression.level_for(899), 2)
	assert_eq(Progression.level_for(900), 3)
	assert_eq(Progression.level_for(99999), 5, "1차 상한 5레벨")
	var c := _pc("fighter")
	var w := {"xp": 300}
	c.hp -= 4
	var mx: int = c.hp_max
	assert_true(Progression.level_up(w, c))
	assert_eq(c.level, 2)
	assert_eq(c.hp, c.hp_max - 4, "잃은 HP는 그대로")
	assert_true(c.hp_max > mx)
	assert_false(Progression.level_up(w, c), "경험치가 모자라면 못 올린다")
	assert_eq(c.extra_modifiers.size(), 0, "기능 수정치가 겹쳐 쌓이지 않는다")


func test_level_up_to_5_gets_extra_attack() -> void:
	var c := _pc("fighter")
	var w := {"xp": 6500}
	while Progression.level_up(w, c):
		pass
	assert_eq(c.level, 5)
	assert_eq(c.attacks_per_action, 2)
	assert_eq(c.known_reactions.count("opportunity_attack"), 1)


func test_recruit_matches_party_level_and_cap() -> void:
	var w := make_world(["......"])
	var party: Array = []
	for cls: String in ["fighter", "rogue", "cleric"]:
		party.append(_pc(cls, 3))
	w["party"] = party
	w["xp"] = 900
	var wiz := _pc("wizard", 1)
	wiz.team = "neutral"
	assert_eq(Progression.recruit(w, wiz), "party")
	assert_eq(wiz.level, 3, "영입하면 파티 경험치에 맞춰 레벨이 오른다")
	assert_eq(wiz.team, "party")
	var extra := _pc("cleric", 1)
	assert_eq(Progression.recruit(w, extra), "camp", "활성 파티 4명이면 캠프에서 쉰다")
	var first: Node = party[0]
	assert_false(Progression.swap(w, first, extra), "캠프에서만 교체")
	w["at_camp"] = true
	assert_true(Progression.swap(w, first, extra))
	assert_true(extra in w["party"] and first in w["roster"])


func test_detected_by_talker_opens_dialogue_not_combat() -> void:
	var w := make_world(["........"])
	var g: Node = w["grid"]
	for c in g.all_cells():
		g.add_zone(c, "road")
	var p := make_creature({"team": "party"})
	var boss := make_creature({"team": "enemy", "faction": "gang"})
	var mook := make_creature({"team": "enemy", "faction": "gang"})
	boss.set_meta("dialogue", "goblin_toll")
	boss.facing = Vector2i(-1, 0)
	mook.facing = Vector2i(-1, 0)
	g.place(p, Vector2i(0, 0))
	g.place(mook, Vector2i(6, 0))
	g.place(boss, Vector2i(7, 0))
	var ex: Node = own(ExplorationScript.new().setup(w, [p]))
	ex.move_to(p, Vector2i(3, 0))
	assert_false(w["turns"].in_combat, "대화할 상대가 있으면 전투 대신 대화")
	assert_eq(w["pending_dialogue"]["npc"], boss)
	# 평화 해결 → 세력 전원 중립, 구역 보상
	w.erase("pending_dialogue")
	w["zone_rewards"] = {"road": 100}
	w["inventory"] = {"gold": 0}
	Dice.force([20, 20])  # 통찰 성공, 위협 성공
	var d: RefCounted = Dialogue.start(w, "goblin_toll", p, boss)
	var idx: int = d.options().filter(func(o: Dictionary) -> bool: return o["text"]["en"].begins_with("[Intimidation]"))[0]["index"]
	d.choose(idx)
	assert_eq(mook.team, "neutral", "물러난 세력은 중립")
	ex.check_zone_rewards()
	assert_eq(w["xp"], 100, "적이 남지 않으면 구역 보상")
	ex.check_zone_rewards()
	assert_eq(w["xp"], 100, "한 번만")


func test_zone_reward_includes_defeated_monster_xp() -> void:
	var w := make_world(["....."])
	var g: Node = w["grid"]
	for c in g.all_cells():
		g.add_zone(c, "pit")
	var gob: Node = own(load("res://scripts/rules/monster_factory.gd").spawn("goblin_warrior"))
	g.place(gob, Vector2i(3, 0))
	gob.dead = true
	w["zone_rewards"] = {"pit": 0}
	var ex: Node = own(ExplorationScript.new().setup(w, []))
	ex.check_zone_rewards()
	assert_eq(w["xp"], 50, "고블린 전사 XP 50(SRD)")


func test_fallen_watch_map_is_sound() -> void:
	var b := WorldBuilder.build("fallen_watch")
	for n: Node in b["nodes"]:
		own(n)
	var w: Dictionary = b["world"]
	var g: Node = w["grid"]
	assert_eq(b["party"].size(), 2, "시작 파티 2명 + 영입 동료 2명")
	var comps: Array = b["foes"].filter(func(c: Node) -> bool: return c.team == "neutral")
	assert_eq(comps.size(), 2)
	# 적대 생물은 모두 전투 구역 안
	for c: Node in b["foes"]:
		if c.team == "enemy":
			var inz := false
			for cell in g.occupied_cells(c):
				inz = inz or not g.zones(cell).is_empty()
			assert_true(inz, "%s가 전투 구역 밖" % c.name)
	# 구역마다 시작 지점에서 도달 가능(파티가 걸어서)
	var f: Node = b["party"][0]
	for target: Vector2i in [Vector2i(14, 7), Vector2i(10, 20), Vector2i(33, 20), Vector2i(27, 10)]:
		var p: Dictionary = g.find_path(f, target, -1, g.creatures())
		assert_false(p.is_empty(), "%s에 갈 수 없다" % target)
	# 동굴 바위 턱은 어둠, 바깥은 낮
	assert_eq(g.light_at(Vector2i(26, 2)), 0, "바위 턱 어둠")
	assert_eq(g.light_at(Vector2i(10, 22)), 2, "공터 낮")
	assert_eq(g.light_at(Vector2i(18, 8)), 1, "웅덩이 어스름(빛나는 균열)")
	assert_eq(g.height(Vector2i(41, 5)), 3, "높은 바위")
	assert_true(g.has_flag(Vector2i(20, 5), "no_camp"), "전투 구역은 캠프 불가")
	# 오우거 A는 높은 바위 위 2×2 전체
	var ogre: Node = b["foes"].filter(func(c: Node) -> bool: return c.name == "cliff_ogre_a")[0]
	for cell in g.occupied_cells(ogre):
		assert_eq(g.height(cell), 3)
	assert_eq(w["zone_rewards"]["cave"], 700)
	load("res://scripts/rules/spellcasting.gd").instances.clear()


func test_leader_swaps_with_follower_in_corridor() -> void:
	var w := make_world(["#####", ".....", "#####"])
	var g: Node = w["grid"]
	var a := make_creature({"team": "party"})
	var b := make_creature({"team": "party"})
	g.place(a, Vector2i(0, 1))
	g.place(b, Vector2i(1, 1))
	var ex: Node = own(ExplorationScript.new().setup(w, [a, b]))
	assert_eq(ex.move_to(a, Vector2i(4, 1)), 4, "1칸 통로에서도 묶인 파티원과 자리를 바꿔 지나간다")


func test_rules_check_fixes() -> void:
	const Stealth := preload("res://scripts/rules/stealth.gd")
	const Rest := preload("res://scripts/rules/rest.gd")
	# 1. 원뿔 안에서 걸어 다녀도 은신 굴림은 들어올 때 한 번
	var w := make_world(["..........", ".........."])
	var g: Node = w["grid"]
	for c in g.all_cells():
		g.set_base_light(c, GridWorldScript.Light.DIM)
	var p := make_creature({"team": "party", "is_player_character": true, "hp_max": 10, "abilities": {"dex": 18}})
	var o := make_creature({"team": "enemy"})
	o.facing = Vector2i(-1, 0)
	g.place(o, Vector2i(9, 0))
	g.place(p, Vector2i(0, 0))
	var ex: Node = own(ExplorationScript.new().setup(w, [p]))
	p.sneaking = true
	Dice.force([15])
	ex.move_to(p, Vector2i(4, 1))
	var rolls := Dice.roll_log.filter(func(e: Dictionary) -> bool: return e["kind"] == "d20").size()
	assert_eq(rolls, 1, "원뿔에 들어올 때 1번만 굴린다")
	# 2. 실시간에는 반응이 없고, 낙하로 쓰러지면 안정 상태
	assert_true(EventBus.realtime)
	p.hp = 1
	Dice.force([6])
	preload("res://scripts/rules/physics.gd").fall(p, 2)
	assert_true(p.is_down() and p.stable, "탐험 중 낙하로 쓰러지면 안정 상태")
	# 3. 은신 동점이면 발견(수동 지각 10, 은신 합계 10)
	var q := make_creature({"team": "party", "abilities": {"dex": 10}})
	q.sneaking = true
	g.place(q, Vector2i(5, 0))
	Dice.force([10])
	assert_eq(Stealth.observe(g, o, q), "suspicious", "같은 값이면 찾는 쪽이 이긴다")
	# 4. 쉬는 동료도 긴 휴식
	var resting := make_creature({"team": "party", "hp_max": 20})
	resting.hp = 3
	w["roster"] = [resting]
	w["party_resources"] = {"camp_supplies": 40}
	o.awareness.clear()
	Rest.long_rest(w, [p, q])
	assert_eq(resting.hp, 20, "캠프의 동료도 긴 휴식을 받는다")


func test_failed_check_option_gives_no_goal() -> void:
	var w := make_world(["...."])
	var c: Node = _pc("fighter")
	w["grid"].place(c, Vector2i(0, 0))
	w["party"] = [c]
	w["dialogue_tags"] = {"goblin_bluffing": true}
	Dice.force([2, 1])  # 통찰(이미 태그) 건너뜀 → 위협 자연 1
	var d: RefCounted = Dialogue.start(w, "goblin_toll", c)
	var idx: int = d.options().filter(func(o: Dictionary) -> bool: return o["text"]["en"].begins_with("[Intimidation]"))[0]["index"]
	d.choose(idx)
	assert_eq(int(w.get("inspiration", 0)), 0, "위협에 실패하면 목표 달성이 아니다")


func test_broken_chest_drops_loot_and_save_keeps_progress() -> void:
	var w := make_world(["...."])
	var g: Node = w["grid"]
	g.place_object(Vector2i(1, 0), {"id": "chest", "material": "wood", "hp": 1, "loot": {"gold": 5}, "lock": {"dc": 15, "locked": true}})
	w["surfaces"].break_object(Vector2i(1, 0))
	assert_eq(g.object_at(Vector2i(1, 0)).get("loot", {}), {"gold": 5}, "부순 상자의 전리품은 남는다")
	var c: Node = _pc("fighter")
	c.name = "hero"
	g.place(c, Vector2i(0, 0))
	w["party"] = [c]
	w["xp"] = 900
	assert_true(Progression.level_up(w, c))
	w["zones_cleared"] = {"cave": true}
	var snap: Dictionary = JSON.parse_string(JSON.stringify(preload("res://scripts/rules/save_game.gd").snapshot(w)))
	var w2 := make_world(["...."])
	var c2: Node = _pc("fighter")
	c2.name = "hero"
	w2["grid"].place(c2, Vector2i(0, 0))
	assert_true(preload("res://scripts/rules/save_game.gd").restore(w2, snap))
	assert_eq(c2.level, 2, "레벨 업이 저장된다")
	assert_eq(c2.hp_max, c.hp_max)
	assert_true(w2["zones_cleared"].has("cave"), "구역 보상을 다시 받지 않는다")


func test_explore_jumps_down_from_ledge() -> void:
	var w := make_world(["22...", "22..."])
	var c := make_creature({"team": "party", "is_player_character": true, "hp_max": 30, "abilities": {"str": 14}})
	w["grid"].place(c, Vector2i(0, 0))
	var ex: Node = own(ExplorationScript.new().setup(w, [c]))
	assert_true(ex.move_to(c, Vector2i(4, 1)) > 0, "바위 턱에서 점프로 내려가 목적지까지 간다")
	assert_eq(w["grid"].cell_of(c), Vector2i(4, 1))
	assert_true(c.hp < 30, "2단계 낙하 피해")
