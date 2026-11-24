extends "res://tests/test_case.gd"
## 2구간(11~12레벨) 기능 — 레벨 상한 12(2026-11-23).

const Builder := preload("res://scripts/rules/character_builder.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Features := preload("res://scripts/rules/features.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Actions := preload("res://scripts/rules/actions.gd")


func _pc(cid: String, lv: int, extra: Dictionary = {}) -> Node:
	var spec := Builder.default_spec(cid, lv)
	spec.merge(extra, true)
	var r := Builder.build(spec)
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func _arena(a: Node, b: Node) -> Dictionary:
	var w := make_world(["..........", "..........", ".........."])
	w["grid"].place(a, Vector2i(1, 1))
	w["grid"].place(b, Vector2i(2, 1))
	a.reset_turn()
	return w


func test_fighter_11() -> void:
	var f := _pc("fighter", 12)
	assert_eq(f.attacks_per_action, 3, "추가 공격 2회")
	assert_eq(f.crit_threshold, 19, "향상된 치명타(우월한 치명타 15레벨은 없음)")


func test_barbarian_11() -> void:
	var b := _pc("barbarian", 12)
	var foe := make_creature({"team": "enemy", "hp_max": 300})
	var w := _arena(b, foe)
	assert_true(Features.use(w, b, "rage")["ok"])
	Dice.force([15])
	Resolver.apply_damage(b, [{"amount": b.hp + 5, "damage_type": "fire"}])
	assert_eq(b.hp, 24, "끈질긴 분노: 바바리안 레벨 × 2")


func test_rogue_11() -> void:
	var r := _pc("rogue", 12)
	assert_true(r.has_cap("reliable_talent") and not r.feature_data.has("improved_cunning_strike"), "BG3 11레벨: 믿음직한 재능")


func test_paladin_radiant_strikes() -> void:
	var p := _pc("paladin", 12)
	var foe := make_creature({"team": "enemy", "hp_max": 300, "ac_base": 1})
	var w := _arena(p, foe)
	Dice.force([15])
	var res := Resolver.attack(p, foe, Combat.build_weapon_attack(p, p.weapon("main")), w["grid"].attack_context(p, foe))
	assert_true(res["extra_damage"].any(func(x: Dictionary) -> bool: return x["damage_type"] == "radiant"), "빛나는 일격")


func test_level_cap_12() -> void:
	assert_eq(load("res://scripts/rules/levels.gd").level_cap(), 12)
	var wz := _pc("wizard", 12)
	assert_eq(wz.resource("spell_slot_7"), 0, "7레벨 슬롯 없음")
	assert_eq(wz.resource("spell_slot_6"), 1)
	assert_eq(wz.proficiency_bonus, 4)
