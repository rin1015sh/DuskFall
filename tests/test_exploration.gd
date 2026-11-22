extends "res://tests/test_case.gd"
## 탐험: 은신·시야 원뿔·의심→수색→발견, 기습 전투 시작, 함정·자물쇠·살펴보기(룰북 5단계).

const Stealth := preload("res://scripts/rules/stealth.gd")
const Interact := preload("res://scripts/rules/interact.gd")
const ExplorationScript := preload("res://scripts/rules/exploration.gd")


func _dim(g: Node) -> void:
	for c in g.all_cells():
		g.set_base_light(c, GridWorldScript.Light.DIM)


func _guard(facing: Vector2i = Vector2i(1, 0)) -> Node:
	var o := make_creature({"team": "enemy", "abilities": {"wis": 10}})
	o.facing = facing
	return o


func _sneak(dex: int = 16) -> Node:
	var p := make_creature({"team": "party", "abilities": {"dex": dex}, "skill_bonuses": {"stealth": 2}})
	p.sneaking = true
	return p


func test_cone_is_90_degrees_and_blocked_by_walls() -> void:
	var g := make_grid([
		".........",
		".........",
		"....#....",
		".........",
	])
	var o := _guard(Vector2i(1, 0))
	g.place(o, Vector2i(0, 2))
	var cells := Stealth.cone_cells(g, o)
	assert_true(Vector2i(3, 2) in cells, "정면")
	assert_true(Vector2i(2, 0) in cells, "45° 경계")
	assert_false(Vector2i(1, 0) in cells, "45°보다 옆은 밖")
	assert_false(Vector2i(5, 2) in cells, "벽 뒤는 안 보인다")
	assert_false(Vector2i(0, 3) in cells, "옆·뒤는 밖")


func test_bright_light_reveals_sneaker_immediately() -> void:
	var g := make_grid(["......"])
	var o := _guard()
	var p := _sneak()
	g.place(o, Vector2i(0, 0))
	g.place(p, Vector2i(4, 0))
	assert_eq(Stealth.observe(g, o, p), "alerted", "밝은 곳에서는 숨어도 발견")


func test_dim_light_stealth_vs_passive() -> void:
	var g := make_grid(["......"])
	_dim(g)
	var o := _guard()
	var p := _sneak()
	g.place(o, Vector2i(0, 0))
	g.place(p, Vector2i(4, 0))
	assert_eq(Stealth.passive_perception(o), 10)
	Dice.force([15])  # 15 + 3 + 2 = 20 ≥ 10
	assert_eq(Stealth.observe(g, o, p), "", "은신 성공")
	Dice.force([2])  # 2 + 5 = 7 < 10
	assert_eq(Stealth.observe(g, o, p), "suspicious", "첫 실패는 의심")
	assert_eq(o.awareness[p]["last"], Vector2i(4, 0))
	Dice.force([2])
	assert_eq(Stealth.observe(g, o, p), "alerted", "의심 중 다시 실패하면 발견")


func test_darkness_hides_and_not_sneaking_is_seen() -> void:
	var g := make_grid(["......"])
	for c in g.all_cells():
		g.set_base_light(c, GridWorldScript.Light.DARK)
	var o := _guard()
	var p := _sneak()
	g.place(o, Vector2i(0, 0))
	g.place(p, Vector2i(4, 0))
	assert_eq(Stealth.observe(g, o, p), "", "어둠에서는 눈으로 못 본다")
	o.senses = ["darkvision"]
	p.sneaking = false
	assert_eq(Stealth.observe(g, o, p), "alerted", "암시야 + 숨지 않음 = 발견")


func test_suspicious_then_search() -> void:
	var g := make_grid([".......", "......."])
	_dim(g)
	var o := _guard()
	var p := _sneak()
	g.place(o, Vector2i(0, 0))
	g.place(p, Vector2i(2, 0))
	Dice.force([1])  # 자연 1: 실패
	assert_eq(Stealth.observe(g, o, p), "suspicious")
	p.set_meta("stealth_total", 12)
	Dice.force([1])
	assert_eq(Stealth.search(g, o, p), "", "지각 실패")
	assert_eq(o.awareness[p]["state"], "searching")
	Dice.force([15])
	assert_eq(Stealth.search(g, o, p), "alerted", "2칸 안 감지 성공")


func test_hidden_attack_starts_combat_with_surprise() -> void:
	var w := make_world([
		"........",
		"........",
	])
	var g: Node = w["grid"]
	for c in g.all_cells():
		g.add_zone(c, "room")
	var p := _sneak()
	var o1 := _guard(Vector2i(-1, 0))
	var o2 := _guard(Vector2i(-1, 0))
	g.place(p, Vector2i(0, 0))
	g.place(o1, Vector2i(1, 0))
	g.place(o2, Vector2i(6, 1))
	var ex: Node = own(ExplorationScript.new().setup(w, [p]))
	ex.hostile_action(p, o1)
	assert_true(w["turns"].in_combat, "적대 행동은 전투를 시작한다")
	assert_true(o1.has_condition("surprised") and o2.has_condition("surprised"), "알아채지 못한 적은 기습")
	assert_false(p.sneaking, "전투가 시작되면 은신이 풀린다")


func test_alerted_enemy_starts_combat_on_move() -> void:
	var w := make_world(["........"])
	var g: Node = w["grid"]
	for c in g.all_cells():
		g.add_zone(c, "room")
	var p := make_creature({"team": "party"})
	var o := _guard(Vector2i(-1, 0))
	g.place(p, Vector2i(0, 0))
	g.place(o, Vector2i(7, 0))
	var ex: Node = own(ExplorationScript.new().setup(w, [p]))
	ex.move_to(p, Vector2i(3, 0))
	assert_true(w["turns"].in_combat, "숨지 않고 원뿔에 들어가면 발견 → 전투")
	assert_false(p.has_condition("surprised"))


func test_party_follows_leader() -> void:
	var w := make_world(["........"])
	var g: Node = w["grid"]
	var a := make_creature({"team": "party"})
	var b := make_creature({"team": "party"})
	g.place(a, Vector2i(1, 0))
	g.place(b, Vector2i(0, 0))
	var ex: Node = own(ExplorationScript.new().setup(w, [a, b]))
	assert_eq(ex.move_to(a, Vector2i(5, 0)), 4)
	assert_eq(g.cell_of(b), Vector2i(4, 0), "묶인 파티원은 뒤를 따른다")
	ex.set_sneak(a, true)
	assert_true(b.sneaking, "묶이면 은신도 함께")
	ex.link(b, false)
	ex.move_to(a, Vector2i(7, 0))
	assert_eq(g.cell_of(b), Vector2i(4, 0), "풀린 파티원은 남는다")


func test_trap_perception_and_trigger() -> void:
	var w := make_world(["........"])
	var g: Node = w["grid"]
	var p := make_creature({"team": "party", "hp_max": 30, "abilities": {"wis": 10, "dex": 10}})
	g.place(p, Vector2i(0, 0))
	var trap := {"id": "dart", "cell": [4, 0], "dc_find": 12, "dc_disarm": 12, "save": {"ability": "dex", "dc": 13},
		"effects": [{"type": "damage", "dice": "2d4", "damage_type": "piercing"}], "state": "armed"}
	w["traps"] = [trap]
	var ex: Node = own(ExplorationScript.new().setup(w, [p]))
	Dice.force([5])  # 지각 실패(5 < 12)
	ex.move_to(p, Vector2i(1, 0))
	assert_false(trap.get("found", false))
	ex.move_to(p, Vector2i(2, 0))
	assert_false(trap.get("found", false), "캐릭터마다 1회만 굴린다")
	Dice.force([1, 4, 4])  # 내성 실패, 피해 8
	ex.move_to(p, Vector2i(4, 0))
	assert_eq(trap["state"], "spent")
	assert_eq(p.hp, 22)


func test_disarm_lock_and_tools() -> void:
	var w := make_world(["....."])
	var g: Node = w["grid"]
	var p := make_creature({"team": "party", "hp_max": 30, "abilities": {"dex": 14}})
	g.place(p, Vector2i(0, 0))
	var trap := {"id": "dart", "cell": [3, 0], "dc_find": 12, "dc_disarm": 15, "found": true,
		"effects": [{"type": "damage", "dice": "1d4", "damage_type": "piercing"}], "state": "armed"}
	assert_false(Interact.disarm(w, p, trap)["ok"], "도구가 없으면 못 한다")
	Interact.give(w, "trap_disarm_kit", 2)
	Dice.force([18])
	var r := Interact.disarm(w, p, trap)
	assert_true(r["success"])
	assert_eq(trap["state"], "disarmed")
	assert_eq(Interact.count(w, "trap_disarm_kit"), 2, "성공하면 도구가 남는다")
	# 자물쇠: 실패하면 도둑 도구 소모, 열쇠가 있으면 굴림 없이
	g.place_object(Vector2i(1, 0), {"id": "chest", "lock": {"dc": 15, "key": "chest_key", "locked": true}})
	Interact.give(w, "thieves_tools", 1)
	Dice.force([2])
	assert_false(Interact.open_lock(w, p, Vector2i(1, 0))["success"])
	assert_eq(Interact.count(w, "thieves_tools"), 0, "실패하면 도구가 부서진다")
	Interact.give(w, "chest_key")
	assert_true(Interact.open_lock(w, p, Vector2i(1, 0))["key"])
	assert_false(g.object_at(Vector2i(1, 0))["lock"]["locked"])


func test_failed_disarm_triggers_and_blocks_retry() -> void:
	var w := make_world(["....."])
	var p := make_creature({"team": "party", "hp_max": 30, "abilities": {"dex": 10}})
	w["grid"].place(p, Vector2i(3, 0))
	var trap := {"id": "dart", "cell": [3, 0], "dc_find": 12, "dc_disarm": 15, "found": true,
		"effects": [{"type": "damage", "dice": "1d4", "damage_type": "piercing"}], "state": "armed"}
	Interact.give(w, "trap_disarm_kit", 2)
	Dice.force([3, 4])
	Interact.disarm(w, p, trap)
	assert_eq(trap["state"], "spent", "실패하면 발동")
	assert_eq(Interact.count(w, "trap_disarm_kit"), 1, "실패하면 도구 소모")
	assert_eq(p.hp, 26)


func test_visible_check_assist_and_inspiration() -> void:
	var w := {"inspiration": 1}
	var p := make_creature({"abilities": {"int": 10}})
	Dice.force([4, 9])  # 보조 4(먼저) + 9 = 13 ≥ 13
	assert_true(Interact.visible_check(w, p, "int", "investigation", 13, {"assist": ["1d4"]})["success"])
	Dice.force([2, 17])
	var r := Interact.visible_check(w, p, "int", "investigation", 13, {"inspiration": true})
	assert_true(r["success"] and r.get("rerolled", false), "영감으로 다시 굴림")
	assert_eq(w["inspiration"], 0)
	var pv := Interact.preview_check(p, "int", "investigation", 13)
	assert_eq(pv["chance"], 0.4)
