extends "res://tests/test_case.gd"
## 3구간 몬스터(도전 등급 16~20): 생성, 화염 흡수, 구덩이 악마 독(내성 뒤 상태), 반응 불가.

const MF := preload("res://scripts/rules/monster_factory.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")

const IDS := ["adult_blue_dragon", "iron_golem", "adult_red_dragon", "balor", "pit_fiend"]


func test_spawn_all() -> void:
	for id: String in IDS:
		var m: Node = own(MF.spawn(id))
		assert_true(m != null and m.hp_max >= 212, id)
		assert_true(float(RulesDB.get_entry("monster", id)["cr"]) >= 16)


func test_fire_absorption() -> void:
	var g: Node = own(MF.spawn("iron_golem"))
	g.hp = 100
	Resolver.apply_damage(g, [{"amount": 30, "damage_type": "fire"}])
	assert_eq(g.hp, 130, "화염 피해만큼 회복")


func test_pit_fiend_bite_and_balor_blade() -> void:
	var w := make_world([".........."])
	var pf: Node = own(MF.spawn("pit_fiend"))
	var t := make_creature({"team": "party", "hp_max": 300, "ac_base": 1})
	w["grid"].place(pf, Vector2i(0, 0), 2)
	w["grid"].place(t, Vector2i(3, 0))
	pf.reset_turn()
	Dice.force([15, 3, 3, 3, 1])
	Combat.monster_action(w, pf, "bite", t)
	assert_true(t.has_condition("pit_fiend_poison") and t.has_condition("poisoned"), "물기 독")
	var bl: Node = own(MF.spawn("balor"))
	var w2 := make_world([".........."])
	var u := make_creature({"team": "party", "hp_max": 300, "ac_base": 1})
	w2["grid"].place(bl, Vector2i(0, 0), 3)
	w2["grid"].place(u, Vector2i(4, 0))
	bl.reset_turn()
	Dice.force([15])
	Combat.monster_action(w2, bl, "lightning_blade", u)
	assert_true(u.has_condition("reactionless"))
	assert_false(u.can_react(), "반응 불가")
