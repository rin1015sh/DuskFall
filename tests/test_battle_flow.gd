extends "res://tests/test_case.gd"
## 4단계 완료 기준(로직): 시험 맵에서 4인 파티와 고블린 전사 4가 끝까지 싸운다.
## 양쪽 모두 간단한 AI로 돌려 전투가 정상적으로 끝나는지 여러 시드로 본다.

const Roster := preload("res://scenes/battle/test_roster.gd")
const SimpleAI := preload("res://scripts/ai/simple_ai.gd")


func _run_battle(seed_value: int) -> Dictionary:
	Dice.set_seed(seed_value)
	var b := Roster.build()
	for n: Node in b["nodes"]:
		own(n)
	var w: Dictionary = b["world"]
	var tm: Node = w["turns"]
	tm.start_combat("arena")
	var steps := 0
	while tm.in_combat and steps < 400:
		steps += 1
		var group: Array = tm.current_group()
		if group.is_empty():
			break
		var c: Node = group[0]
		SimpleAI.take_turn(w, c)
		if tm.in_combat:
			tm.end_turn(c)
	return {"ended": not tm.in_combat, "rounds": tm.round_number, "party": b["party"], "foes": b["foes"]}


func test_battle_runs_to_the_end() -> void:
	var party_wins := 0
	for s in [1, 2, 3, 4, 5]:
		var r := _run_battle(s)
		assert_true(r["ended"], "시드 %d: 전투가 끝난다(라운드 %d)" % [s, r["rounds"]])
		assert_true(r["rounds"] < 30, "시드 %d: 30라운드 안" % s)
		var foes_left: int = r["foes"].filter(func(c: Node) -> bool: return not c.dead and not c.is_down()).size()
		if foes_left == 0:
			party_wins += 1
	assert_true(party_wins >= 1, "파티가 이길 수 있다(%d/5)" % party_wins)


func test_map_loaded() -> void:
	var b := Roster.build()
	for n: Node in b["nodes"]:
		own(n)
	var g: Node = b["world"]["grid"]
	assert_eq(g.size, Vector2i(16, 12))
	assert_true(g.has_flag(Vector2i(0, 0), "wall"))
	assert_eq(g.material(Vector2i(3, 2)), "grass")
	assert_eq(g.surface_id(Vector2i(11, 6)), "water")
	assert_eq(g.surface(Vector2i(11, 6))["turns_left"], -1, "맵 배치 물은 영구")
	assert_eq(g.height(Vector2i(12, 3)), 2)
	assert_false(g.object_at(Vector2i(8, 3)).is_empty(), "기름통")
	assert_eq(b["party"].size(), 4)
	assert_eq(b["foes"].size(), 4)
