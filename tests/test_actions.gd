extends "res://tests/test_case.gd"
## 행동 목록(BG3식 단축 막대의 엔진 쪽): 공용·클래스·아이템·주문 목록, 사용 가능 검사, 미리보기, 실행, 탐험 중 비용 없음.

const Actions := preload("res://scripts/rules/actions.gd")
const Builder := preload("res://scripts/rules/character_builder.gd")
const ExplorationScript := preload("res://scripts/rules/exploration.gd")


func _pc(cls: String, lv: int = 1) -> Node:
	return own(Builder.build(Builder.default_spec(cls, lv))["creature"])


func test_lists_by_tab() -> void:
	var w := make_world(["....."])
	var f := _pc("fighter", 2)
	var r := _pc("rogue", 2)
	w["grid"].place(f, Vector2i(0, 0))
	f.inventory = {"potion_of_healing": 2}
	var lf: Dictionary = Actions.list_for(w, f)
	assert_true("jump" in lf["common"] and "shove" in lf["common"] and "dash" in lf["common"])
	assert_true("feature:second_wind" in lf["class"] and "feature:action_surge" in lf["class"])
	assert_false("cunning_dash" in lf["class"], "교활한 행동은 로그만")
	assert_true("drink:potion_of_healing" in lf["items"] and "throw_potion:potion_of_healing" in lf["items"])
	var lr: Dictionary = Actions.list_for(w, r)
	assert_true("cunning_hide" in lr["class"])
	assert_true("offhand_attack" in lr["common"], "보조 무기가 있으면 보조 공격")
	var le: Dictionary = Actions.list_for(w, f, true)
	assert_true("jump" in le["common"] and not "dash" in le["common"], "탐험에는 탐험용 행동만")


func test_costs_and_execute() -> void:
	var w := make_world(["......", "......"])
	var f := _pc("fighter")
	var g := make_creature({"team": "enemy", "hp_max": 30, "ac_base": 5})
	w["grid"].place(f, Vector2i(0, 0))
	w["grid"].place(g, Vector2i(1, 0))
	f.reset_turn()
	var pv: Dictionary = Actions.preview(w, f, "attack", Vector2i(1, 0))
	assert_true(pv["valid"] and pv["lines"][0].begins_with("명중"))
	assert_false(Actions.preview(w, f, "attack", Vector2i(3, 1))["valid"], "적이 아닌 칸")
	Dice.force([15, 5])
	assert_true(Actions.execute(w, f, "attack", Vector2i(1, 0))["ok"])
	assert_eq(Actions.unavailable(w, f, "dash"), "행동이 없다", "공격 행동을 썼다")
	assert_true(Actions.execute(w, f, "jump", Vector2i(3, 1))["ok"], "도약은 보너스 행동")
	assert_eq(w["grid"].cell_of(f), Vector2i(3, 1))
	assert_eq(Actions.unavailable(w, f, "shove"), "보너스 행동이 없다")
	f.hp = 3
	f.inventory = {"potion_of_healing": 1}
	f.reset_turn()
	assert_true(Actions.execute(w, f, "drink:potion_of_healing", Vector2i(3, 1))["ok"])
	assert_true(f.hp > 3)
	assert_eq(int(f.inventory.get("potion_of_healing", 0)), 0, "마신 캐릭터의 물약이 줄었다")


func test_explore_hidden_attack_has_advantage_and_starts_combat() -> void:
	var w := make_world(["......"])
	var g: Node = w["grid"]
	for c in g.all_cells():
		g.add_zone(c, "room")
	var r := _pc("rogue")
	var e := make_creature({"team": "enemy", "hp_max": 30})
	e.facing = Vector2i(1, 0)
	g.place(r, Vector2i(0, 0))
	g.place(e, Vector2i(1, 0))
	var ex: Node = own(ExplorationScript.new().setup(w, [r]))
	r.sneaking = true
	r.reset_turn()
	r.turn["action"] = 0  # 탐험 중에는 비용을 채우고 쓴다
	var res: Dictionary = Actions.execute(w, r, "attack", Vector2i(1, 0), true)
	assert_true(res["ok"] and res["hostile"])
	assert_true("advantage" in str(res.get("mode_note", "")) or res.get("mode", 0) == 1, "숨은 채 하는 공격은 유리")
	assert_true(w["turns"].in_combat, "적대 행동이면 전투 시작")
	assert_true(e.has_condition("surprised"), "알아채지 못한 적은 기습")


func test_throw_nearby_barrel() -> void:
	var w := make_world(["......"])
	var f := _pc("fighter")
	var e := make_creature({"team": "enemy", "hp_max": 30, "ac_base": 5})
	w["grid"].place(f, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(4, 0))
	w["grid"].place_object(Vector2i(1, 0), {"id": "oil_barrel", "material": "wood", "hp": 4, "weight_kg": 30,
		"contents": {"surface": "oil", "radius": 1}})
	f.reset_turn()
	Dice.force([18, 3])
	var r: Dictionary = Actions.execute(w, f, "throw", Vector2i(4, 0))
	assert_true(r["ok"] and r["hit"])
	assert_true(w["grid"].object_at(Vector2i(1, 0)).is_empty(), "던진 물체는 집어 든 자리에서 사라진다")
	assert_eq(w["grid"].surface_id(Vector2i(4, 0)), "oil", "기름통은 맞은 자리에서 깨진다")
