extends "res://tests/test_case.gd"
## 6~8레벨 주문(2구간): 연쇄 번개·분해·치유·신성한 말·권능의 말: 기절·재생, 워락 신비한 비전.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")


func _caster(w: Dictionary, cid: String, sid: String, cell: Vector2i = Vector2i(0, 1)) -> Node:
	var c: Node = own(Builder.build(Builder.default_spec(cid, 15))["creature"])
	if not c.spells.has(sid):
		c.spells.append(sid)
	w["grid"].place(c, cell)
	c.reset_turn()
	return c


func _world() -> Dictionary:
	return make_world(["....................", "....................", "...................."])


func test_chain_lightning() -> void:
	var w := _world()
	var c := _caster(w, "wizard", "chain_lightning")
	var foes: Array = []
	for x in [8, 10, 12, 13, 19]:
		var f := make_creature({"team": "enemy", "hp_max": 200})
		w["grid"].place(f, Vector2i(x, 1))
		foes.append(f)
	assert_true(Spellcasting.cast(w, c, "chain_lightning", Vector2i(8, 1)).get("ok", false))
	var hit := foes.filter(func(f: Node) -> bool: return f.hp < 200).size()
	assert_eq(hit, 4, "첫 대상 + 6칸 안 3")
	assert_eq(foes[4].hp, 200, "멀리 있는 적은 안 맞는다")


func test_disintegrate_and_heal() -> void:
	var w := _world()
	var c := _caster(w, "wizard", "disintegrate")
	var foe := make_creature({"team": "enemy", "hp_max": 200})
	w["grid"].place(foe, Vector2i(5, 1))
	var forced: Array = [1]
	for i in 10:
		forced.append(1)
	Dice.force(forced)
	assert_true(Spellcasting.cast(w, c, "disintegrate", Vector2i(5, 1)).get("ok", false))
	assert_eq(foe.hp, 200 - 50, "10d6 + 40")
	var cl := _caster(w, "cleric", "heal", Vector2i(0, 2))
	var ally := make_creature({"team": "party", "hp_max": 100})
	w["grid"].place(ally, Vector2i(2, 2))
	ally.hp = 10
	ally.apply_condition("poisoned", 10)
	assert_true(Spellcasting.cast(w, cl, "heal", Vector2i(2, 2)).get("ok", false))
	assert_eq(ally.hp, 10 + 70 + 8, "치유 70 + 생명의 제자(2 + 슬롯 6)")
	assert_false(ally.has_condition("poisoned"))


func test_divine_word_and_power_word() -> void:
	var w := _world()
	var cl := _caster(w, "cleric", "divine_word")
	var weak := make_creature({"team": "enemy", "hp_max": 15})
	var mid := make_creature({"team": "enemy", "hp_max": 35})
	w["grid"].place(weak, Vector2i(3, 1))
	w["grid"].place(mid, Vector2i(4, 1))
	Dice.force([1, 1])
	assert_true(Spellcasting.cast(w, cl, "divine_word", Vector2i(3, 1)).get("ok", false))
	assert_true(weak.dead, "HP 20 이하 죽음")
	assert_true(mid.has_condition("blinded"), "HP 40 이하 실명")
	var wz := _caster(w, "wizard", "power_word_stun", Vector2i(0, 2))
	var foe := make_creature({"team": "enemy", "hp_max": 120})
	w["grid"].place(foe, Vector2i(6, 2))
	assert_true(Spellcasting.cast(w, wz, "power_word_stun", Vector2i(6, 2)).get("ok", false))
	assert_true(foe.has_condition("stunned"), "HP 150 이하 기절")


func test_regenerate_ticks() -> void:
	var w := _world()
	var dr := _caster(w, "druid", "regenerate")
	var ally := make_creature({"team": "party", "hp_max": 100})
	w["grid"].place(ally, Vector2i(1, 1))
	ally.hp = 10
	Dice.force([1, 1, 1, 1])
	assert_true(Spellcasting.cast(w, dr, "regenerate", Vector2i(1, 1)).get("ok", false))
	assert_eq(ally.hp, 10 + 19, "4d8 + 15")
	Resolver.start_turn(ally, {"in_combat": true})
	assert_eq(ally.hp, 30, "턴 시작 1 회복")


func test_mystic_arcanum() -> void:
	var wl: Node = own(Builder.build(Builder.default_spec("warlock", 15))["creature"])
	for sid: String in ["circle_of_death", "finger_of_death", "power_word_stun"]:
		assert_true(wl.spells.has(sid), sid)
		assert_eq(wl.resource("innate_" + sid), 1, "긴 휴식마다 1회")
	var w := _world()
	w["grid"].place(wl, Vector2i(0, 1))
	var foe := make_creature({"team": "enemy", "hp_max": 300})
	w["grid"].place(foe, Vector2i(5, 1))
	wl.reset_turn()
	assert_eq(Spellcasting.can_cast(w, wl, "finger_of_death", Vector2i(5, 1)), "", "7레벨 슬롯 없이도")
	assert_true(Spellcasting.cast(w, wl, "finger_of_death", Vector2i(5, 1)).get("ok", false))
	assert_eq(wl.resource("innate_finger_of_death"), 0)
	assert_true(foe.hp < 300)
