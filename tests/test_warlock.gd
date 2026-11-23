extends "res://tests/test_case.gd"
## 워락: 계약 마법(같은 레벨 슬롯·짧은 휴식·올려 시전), 영창(고통·밀어내는 화살, 그림자 갑옷 무료 시전, 악마의 시야, 선행 레벨),
## 섬뜩한 화살(5레벨 광선 2개), 저주(명중 +1d6·자동 옮김), 마법적 기지, 악마 후원자(어둠의 축복·항상 준비).

const Builder := preload("res://scripts/rules/character_builder.gd")
const Features := preload("res://scripts/rules/features.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Rest := preload("res://scripts/rules/rest.gd")


func _wl(lv: int) -> Node:
	var r := Builder.build(Builder.default_spec("warlock", lv))
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func test_pact_magic_and_invocations() -> void:
	var w1 := _wl(1)
	assert_false(w1.has_cap("agonizing_blast"), "고통의 화살은 2레벨부터(명세에 있어도)")
	assert_true(w1.spells.has("mage_armor"), "그림자 갑옷")
	var w5 := _wl(5)
	assert_eq(w5.resource("spell_slot_3"), 2, "5레벨: 3레벨 슬롯 2")
	assert_eq(w5.resource("spell_slot_1"), 0)
	assert_eq(w5.resources["spell_slot_3"]["recharge"], "short", "짧은 휴식")
	assert_true(w5.has_cap("agonizing_blast") and w5.has_cap("repelling_blast"))
	assert_eq(w5.darkvision_tiles, 24, "악마의 시야")
	assert_true(w5.spells.has("fireball") and w5.spells.has("suggestion"), "악마의 주문")


func test_at_will_and_hex_upcast_slot() -> void:
	var w := make_world(["......."])
	var c := _wl(5)
	var foe := make_creature({"team": "enemy", "hp_max": 60, "ac_base": 1})
	var other := make_creature({"team": "enemy", "hp_max": 60, "ac_base": 1})
	w["grid"].place(c, Vector2i(0, 0))
	w["grid"].place(foe, Vector2i(3, 0))
	w["grid"].place(other, Vector2i(5, 0))
	c.reset_turn()
	assert_true(Spellcasting.cast(w, c, "mage_armor", Vector2i(0, 0)).get("ok", false))
	assert_eq(c.resource("spell_slot_3"), 2, "그림자 갑옷: 슬롯 없이")
	c.reset_turn()
	assert_true(Spellcasting.cast(w, c, "hex", Vector2i(3, 0)).get("ok", false))
	assert_eq(c.resource("spell_slot_3"), 1, "1레벨 주문도 3레벨 계약 슬롯으로")
	assert_true(foe.has_condition("hexed"))
	c.reset_turn()
	var hp: int = foe.hp
	Dice.force([15, 5, 3, 15, 5, 3])  # 광선마다 명중·1d10·저주 1d6
	assert_true(Spellcasting.cast(w, c, "eldritch_blast", Vector2i(3, 0)).get("ok", false))
	var per: int = 5 + c.ability_mod("cha") + 3
	assert_eq(hp - foe.hp, per * 2, "광선 2개(고통의 화살 + 매력, 저주 + 1d6)")
	Resolver.apply_damage(foe, [{"amount": 999, "damage_type": "force"}], {"attacker": c})
	assert_true(other.has_condition("hexed"), "저주가 옮겨 간다")
	assert_true(c.temp_hp > 0, "어둠의 축복")


func test_magical_cunning_and_short_rest() -> void:
	var w := make_world(["...."])
	var c := _wl(5)
	w["grid"].place(c, Vector2i(0, 0))
	c.resources["spell_slot_3"]["current"] = 0
	assert_true(Features.use(w, c, "magical_cunning")["ok"])
	assert_eq(c.resource("spell_slot_3"), 1, "절반(올림)")
	c.resources["spell_slot_3"]["current"] = 0
	Rest.short_rest(w, [c])
	assert_eq(c.resource("spell_slot_3"), 2, "짧은 휴식에 계약 슬롯 회복")


func test_more_invocations() -> void:
	var spec := Builder.default_spec("warlock", 2)
	spec["eldritch_invocations"] = ["pact_of_the_chain"]
	spec["eldritch_invocations_2"] = ["eldritch_mind", "mask_of_many_faces"]
	var c: Node = own(Builder.build(spec)["creature"])
	assert_true(c.has_cap("eldritch_mind"))
	assert_true("disguise_self" in c.get_meta("at_will") and "find_familiar" in c.get_meta("at_will"))
	c.start_concentration("hex", {"instance": -1, "turns_left": 10})
	Dice.force([5, 15])
	var r: Dictionary = Resolver.concentration_check(c, 4)
	assert_eq(int(r["mode"]), 1, "섬뜩한 정신: 집중 유지 유리")
