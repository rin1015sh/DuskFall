extends "res://tests/test_case.gd"
## BG3 경험치(룰북 7단계 경험치, changes 2026-11-25): 처치 = 적 레벨 × 보상 종류(구역 레벨이 더 높으면 구역 레벨),
## 구역 정리 = 퀘스트 단계 표, 장소 발견 = 파티 평균 레벨 × 크기, 말로 피한 전투도 경험치.

const Levels := preload("res://scripts/rules/levels.gd")
const Progression := preload("res://scripts/rules/progression.gd")
const MonsterFactory := preload("res://scripts/rules/monster_factory.gd")
const ExplorationScript := preload("res://scripts/rules/exploration.gd")


func test_level_table_is_bg3() -> void:
	var want := [0, 300, 900, 2700, 6500, 13000, 21000, 30000, 42000, 56000, 76000, 100000]
	for i in want.size():
		assert_eq(Levels.xp_for(i + 1), want[i], "%d레벨" % (i + 1))


func test_creature_xp_table() -> void:
	assert_eq(Levels.creature_xp(1, "combatant"), 10)
	assert_eq(Levels.creature_xp(5, "elite"), 90, "bg3.wiki 예: 5레벨 정예 90")
	assert_eq(Levels.creature_xp(5, "combatant"), 75)
	assert_eq(Levels.creature_xp(1, "combatant", 3), 20, "구역 레벨이 더 높으면 구역 레벨(1레벨 고블린이 3레벨 구역 → 20)")
	assert_eq(Levels.creature_xp(1, "pack", 5), 40)
	assert_eq(Levels.creature_xp(12, "boss"), 1400)
	assert_eq(Levels.creature_xp(7, "civilian"), 1)
	assert_eq(Levels.creature_xp(9, "zero"), 0)


func test_cr_to_level() -> void:
	assert_eq(Levels.level_from_cr(0.125), 1)
	assert_eq(Levels.level_from_cr(0.25), 1)
	assert_eq(Levels.level_from_cr(0.5), 2)
	assert_eq(Levels.level_from_cr(1), 3)
	assert_eq(Levels.level_from_cr(2), 4)
	assert_eq(Levels.level_from_cr(8), 9)
	assert_eq(Levels.level_from_cr(13), 12)


func test_every_monster_has_level_and_category() -> void:
	for id: String in RulesDB.ids("monster"):
		var m := RulesDB.get_entry("monster", id)
		assert_true(m.has("level") and m.has("xp_category"), id)
		if int(m.get("xp", 0)) == 0:
			assert_eq(m["xp_category"], "zero", "%s: 소환수·동료는 경험치 0" % id)


func test_defeat_xp_uses_monster_data_and_area() -> void:
	var gob: Node = own(MonsterFactory.spawn("goblin_warrior"))
	var boss: Node = own(MonsterFactory.spawn("goblin_boss"))
	assert_eq(Progression.defeat_xp({}, gob), 10, "고블린 전사 1레벨 전투원")
	assert_eq(Progression.defeat_xp({}, boss), 40, "고블린 두목 3레벨 정예")
	assert_eq(Progression.defeat_xp({"area_level": 4}, gob), 40, "4레벨 구역")
	assert_eq(Progression.defeat_xp({}, make_creature({})), 0, "몬스터가 아닌 생물")


func test_quest_step_and_discovery_tables() -> void:
	assert_eq(Levels.quest_step_xp("combat_close_major", 1), 5)
	assert_eq(Levels.quest_step_xp("combat_close_major", 5), 20)
	assert_eq(Levels.quest_step_xp("close_main", 12), 1000)
	assert_eq(Levels.discovery_xp("small", 1), 5)
	assert_eq(Levels.discovery_xp("big", 4), 120, "bg3.wiki 예: 큰 장소 4레벨 120")
	assert_eq(Levels.discovery_xp("medium", 3), 60)


func test_discovery_awards_once_by_party_level() -> void:
	var w := make_world(["......"])
	var g: Node = w["grid"]
	for x in range(3, 6):
		g.add_zone(Vector2i(x, 0), "cave")
	var a := make_creature({"team": "party"})
	a.level = 3
	var b := make_creature({"team": "party"})
	b.level = 2
	g.place(a, Vector2i(1, 0))
	g.place(b, Vector2i(0, 0))
	w["party"] = [a, b]
	w["map_id"] = "t"
	w["discoveries"] = [{"zone": "cave", "size": "medium", "name": {"ko": "동굴", "en": "Cave"}}]
	var ex: Node = own(ExplorationScript.new().setup(w, [a, b]))
	ex.move_to(a, Vector2i(2, 0))
	assert_eq(int(w.get("xp", 0)), 0, "구역 밖")
	ex.move_to(a, Vector2i(4, 0))
	assert_eq(int(w["xp"]), 60, "중간 장소, 파티 평균 레벨 2.5 → 올림 3 → 60")
	ex.move_to(a, Vector2i(5, 0))
	assert_eq(int(w["xp"]), 60, "한 번만")


func test_pacify_gives_xp_of_avoided_fight() -> void:
	var w := make_world(["........"])
	var g: Node = w["grid"]
	var p := make_creature({"team": "party"})
	var boss: Node = own(MonsterFactory.spawn("goblin_boss"))
	var mook: Node = own(MonsterFactory.spawn("goblin_warrior"))
	for o: Node in [boss, mook]:
		o.team = "enemy"
		o.faction = "gang"
	g.place(p, Vector2i(0, 0))
	g.place(mook, Vector2i(6, 0))
	g.place(boss, Vector2i(7, 0))
	own(ExplorationScript.new().setup(w, [p]))
	Dice.force([20, 20])  # 통찰 성공, 위협 성공
	var d: RefCounted = load("res://scripts/rules/dialogue.gd").start(w, "goblin_toll", p, boss)
	var idx: int = d.options().filter(func(o: Dictionary) -> bool: return o["text"]["en"].begins_with("[Intimidation]"))[0]["index"]
	d.choose(idx)
	assert_eq(mook.team, "neutral")
	assert_eq(int(w.get("xp", 0)), 40 + 10, "말로 피한 전투 = 두목(정예 3레벨 40) + 전사(10)")
	mook.dead = true
	Progression.award_defeated(w, [mook])
	assert_eq(int(w["xp"]), 50, "그 뒤에 죽여도 다시 주지 않는다")
