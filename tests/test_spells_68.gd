extends "res://tests/test_case.gd"
## 6레벨 주문: 연쇄 번개·분해·치유, 워락 신비한 비전(레벨 상한 12 — 7레벨 이상 주문 없음).

const Builder := preload("res://scripts/rules/character_builder.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")


func _caster(w: Dictionary, cid: String, sid: String, cell: Vector2i = Vector2i(0, 1)) -> Node:
	var c: Node = own(Builder.build(Builder.default_spec(cid, 12))["creature"])
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


func test_mystic_arcanum() -> void:
	var wl: Node = own(Builder.build(Builder.default_spec("warlock", 12))["creature"])
	assert_true(wl.spells.has("circle_of_death"), "신비한 비전 6레벨")
	assert_eq(wl.resource("innate_circle_of_death"), 1, "긴 휴식마다 1회")
	var w := _world()
	w["grid"].place(wl, Vector2i(0, 1))
	var foe := make_creature({"team": "enemy", "hp_max": 300})
	w["grid"].place(foe, Vector2i(5, 1))
	wl.reset_turn()
	assert_eq(Spellcasting.can_cast(w, wl, "circle_of_death", Vector2i(5, 1)), "", "6레벨 슬롯 없이도")
	assert_true(Spellcasting.cast(w, wl, "circle_of_death", Vector2i(5, 1)).get("ok", false))
	assert_eq(wl.resource("innate_circle_of_death"), 0)
	assert_true(foe.hp < 300)
