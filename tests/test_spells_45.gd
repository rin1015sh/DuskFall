extends "res://tests/test_case.gd"
## 4·5레벨 주문(1구간): 추방·죽음 방비·화염 방패·이동의 자유·집단 상처 치료·차원 문·상급 회복·고정 범위(죽음의 구름).

const Builder := preload("res://scripts/rules/character_builder.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")


func _caster(w: Dictionary, sid: String, cell: Vector2i = Vector2i(0, 1)) -> Node:
	var c: Node = own(Builder.build(Builder.default_spec("wizard", 9))["creature"])
	if not c.spells.has(sid):
		c.spells.append(sid)
	w["grid"].place(c, cell)
	c.reset_turn()
	return c


func test_banishment() -> void:
	var w := make_world(["..........", "..........", ".........."])
	var c := _caster(w, "banishment")
	var foe := make_creature({"team": "enemy", "hp_max": 40})
	w["grid"].place(foe, Vector2i(4, 1))
	Dice.force([2])
	assert_true(Spellcasting.cast(w, c, "banishment", Vector2i(4, 1)).get("ok", false))
	assert_true(foe.has_condition("banished") and foe.is_incapacitated(), "추방")
	assert_true(Resolver.can_attack(c, foe) != "", "공격할 수 없다")
	c.break_concentration("시험")
	assert_false(foe.has_condition("banished"), "집중이 끊기면 돌아온다")


func test_death_ward_and_fire_shield() -> void:
	var w := make_world(["..........", "..........", ".........."])
	var c := _caster(w, "death_ward")
	var ally := make_creature({"team": "party", "hp_max": 20})
	w["grid"].place(ally, Vector2i(1, 1))
	assert_true(Spellcasting.cast(w, c, "death_ward", Vector2i(1, 1)).get("ok", false))
	Resolver.apply_damage(ally, [{"amount": 50, "damage_type": "fire"}])
	assert_eq(ally.hp, 1, "죽음 방비: 1 HP")
	assert_false(ally.has_condition("death_warded"))
	c.spells.append("fire_shield")
	c.reset_turn()
	assert_true(Spellcasting.cast(w, c, "fire_shield", Vector2i(0, 1), {"choice": "chill"}).get("ok", false))
	assert_true(c.has_condition("fire_shield_chill"))
	var foe := make_creature({"team": "enemy", "hp_max": 40})
	w["grid"].place(foe, Vector2i(0, 2))
	Dice.force([15, 4, 4])
	Resolver.attack(foe, c, {"name": "발톱", "bonus": 20, "kind": "melee", "damage": [{"dice": "1d4", "damage_type": "slashing"}]},
		w["grid"].attack_context(foe, c))
	assert_eq(foe.hp, 40 - 8, "차가운 방패: 근접 공격자 2d8 냉기")


func test_freedom_and_restoration() -> void:
	var w := make_world(["..........", "..........", ".........."])
	var c := _caster(w, "freedom_of_movement")
	var ally := make_creature({"team": "party", "hp_max": 20})
	w["grid"].place(ally, Vector2i(1, 1))
	ally.apply_condition("restrained", 10)
	assert_true(Spellcasting.cast(w, c, "freedom_of_movement", Vector2i(1, 1)).get("ok", false))
	assert_false(ally.has_condition("restrained"), "걸려 있던 속박이 풀린다")
	assert_false(ally.apply_condition("paralyzed", 10), "마비 면역")
	ally.apply_condition("charmed", 10)
	c.spells.append("greater_restoration")
	c.reset_turn()
	assert_true(Spellcasting.cast(w, c, "greater_restoration", Vector2i(1, 1)).get("ok", false))
	assert_false(ally.has_condition("charmed"), "상급 회복: 매혹 해제")


func test_mass_cure_wounds_allies_only() -> void:
	var w := make_world(["..........", "..........", ".........."])
	var c := _caster(w, "mass_cure_wounds")
	var ally := make_creature({"team": "party", "hp_max": 60})
	var foe := make_creature({"team": "enemy", "hp_max": 60})
	w["grid"].place(ally, Vector2i(3, 1))
	w["grid"].place(foe, Vector2i(4, 1))
	ally.hp = 1
	foe.hp = 1
	assert_true(Spellcasting.cast(w, c, "mass_cure_wounds", Vector2i(3, 1)).get("ok", false))
	assert_true(ally.hp > 1, "아군 회복")
	assert_eq(foe.hp, 1, "적은 회복하지 않는다")


func test_dimension_door_no_sight() -> void:
	var w := make_world(["...#......", "...#......", "...#......"])
	var c := _caster(w, "dimension_door")
	assert_true(Spellcasting.cast(w, c, "dimension_door", Vector2i(8, 1)).get("ok", false))
	assert_eq(w["grid"].cell_of(c), Vector2i(8, 1), "벽 너머로 순간 이동")


func test_cloudkill_zone() -> void:
	var w := make_world(["...............", "...............", "...............", "..............."])
	var c := _caster(w, "cloudkill")
	var foe := make_creature({"team": "enemy", "hp_max": 200})
	w["grid"].place(foe, Vector2i(10, 1))
	var r := Spellcasting.cast(w, c, "cloudkill", Vector2i(10, 1))
	assert_true(r.get("ok", false))
	var hp: int = foe.hp
	assert_true(hp < 200, "나타날 때 피해")
	w["turns"].round_number += 1
	Dice.force([1])
	w["turns"].end_turn(foe)
	assert_true(foe.hp < hp, "안에서 턴을 끝내면 다시 피해")


## AI: 강한 적 하나에게는 단일 대상 슬롯 주문(또는 피해 범위 주문)을 쓰고, 집중 중이면 다른 집중 주문은 쓰지 않는다.
func test_ai_uses_slots_on_big_foe() -> void:
	var AI: Variant = load("res://scripts/ai/simple_ai.gd")
	var Roles: Variant = load("res://scripts/ai/spell_roles.gd")
	assert_eq(Roles.role_of(RulesDB.get_entry("spell", "blight")), "single")
	assert_eq(Roles.role_of(RulesDB.get_entry("spell", "hold_monster")), "single")
	var w := make_world(["..............", "..............", ".............."])
	var c: Node = own(Builder.build(Builder.default_spec("wizard", 9))["creature"])
	var foe := make_creature({"team": "enemy", "hp_max": 150})
	w["grid"].place(c, Vector2i(0, 1))
	w["grid"].place(foe, Vector2i(10, 1))
	c.reset_turn()
	var before := 0
	for i in range(1, 6):
		before += c.resource("spell_slot_%d" % i)
	AI.take_turn(w, c)
	var after := 0
	for i in range(1, 6):
		after += c.resource("spell_slot_%d" % i)
	assert_eq(after, before - 1, "강한 적 하나에게 슬롯 주문 1개")
	var hold := RulesDB.get_entry("spell", "hold_monster")
	c.concentration = {"spell": "haste"}
	assert_true(AI._breaks_concentration(c, hold), "집중 중이면 다른 집중 주문 안 씀")
