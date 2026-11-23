extends "res://tests/test_case.gd"
## 9레벨 주문(3구간): 권능의 말 둘, 집단 치유, 유성 폭풍, 예지, 창조의 말(바드 20 항상 준비), 신비한 비전 9.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")


func _caster(w: Dictionary, cid: String, sid: String, cell: Vector2i = Vector2i(0, 1)) -> Node:
	var c: Node = own(Builder.build(Builder.default_spec(cid, 20))["creature"])
	if not c.spells.has(sid):
		c.spells.append(sid)
	w["grid"].place(c, cell)
	c.reset_turn()
	return c


func _world() -> Dictionary:
	return make_world(["....................", "....................", "...................."])


func test_power_words() -> void:
	var w := _world()
	var wz := _caster(w, "wizard", "power_word_kill")
	var weak := make_creature({"team": "enemy", "hp_max": 90})
	var big := make_creature({"team": "enemy", "hp_max": 300})
	w["grid"].place(weak, Vector2i(5, 1))
	w["grid"].place(big, Vector2i(6, 2))
	assert_true(Spellcasting.cast(w, wz, "power_word_kill", Vector2i(5, 1)).get("ok", false))
	assert_true(weak.dead, "HP 100 이하 죽음")
	wz.reset_turn()
	wz.resources["spell_slot_9"]["current"] = 1  # 9레벨 슬롯은 하나
	assert_true(Spellcasting.cast(w, wz, "power_word_kill", Vector2i(6, 2)).get("ok", false))
	assert_true(not big.dead and big.hp < 300, "아니면 12d12")
	var bd := _caster(w, "bard", "power_word_heal", Vector2i(0, 2))
	assert_true(bd.spells.has("power_word_heal") and bd.spells.has("power_word_kill"), "창조의 말: 항상 준비")
	var ally := make_creature({"team": "party", "hp_max": 120})
	w["grid"].place(ally, Vector2i(2, 2))
	ally.hp = 5
	ally.apply_condition("stunned", 5)
	assert_true(Spellcasting.cast(w, bd, "power_word_heal", Vector2i(2, 2)).get("ok", false))
	assert_eq(ally.hp, 120)
	assert_false(ally.has_condition("stunned"))


func test_mass_heal_and_meteor() -> void:
	var w := _world()
	var cl := _caster(w, "cleric", "mass_heal")
	var a := make_creature({"team": "party", "hp_max": 300})
	var b := make_creature({"team": "party", "hp_max": 600})
	w["grid"].place(a, Vector2i(2, 1))
	w["grid"].place(b, Vector2i(3, 1))
	a.hp = 1
	b.hp = 1
	assert_true(Spellcasting.cast(w, cl, "mass_heal", Vector2i(2, 1)).get("ok", false))
	assert_eq(a.hp + b.hp - 2, 700, "합계 700")
	var wz := _caster(w, "wizard", "meteor_swarm", Vector2i(0, 0))
	var foe := make_creature({"team": "enemy", "hp_max": 500})
	w["grid"].place(foe, Vector2i(15, 1))
	assert_true(Spellcasting.cast(w, wz, "meteor_swarm", Vector2i(15, 1)).get("ok", false))
	assert_true(foe.hp < 500)


func test_arcanum_9() -> void:
	var wl: Node = own(Builder.build(Builder.default_spec("warlock", 17))["creature"])
	assert_true(wl.spells.has("weird") and wl.resource("innate_weird") == 1, "신비한 비전 9")
