extends "res://tests/test_case.gd"
## 레벨 상한 20 — 3구간(16~20레벨) 기능과 서사 은혜.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Features := preload("res://scripts/rules/features.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")


func _pc(cid: String, lv: int, extra: Dictionary = {}) -> Node:
	var spec := Builder.default_spec(cid, lv)
	spec.merge(extra, true)
	var r := Builder.build(spec)
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func test_capstones_abilities() -> void:
	var b := _pc("barbarian", 20)
	assert_true(int(b.abilities["str"]) > 20 and int(b.abilities["str"]) <= 25, "원시의 투사: 근력 20 초과(%d)" % b.abilities["str"])
	var b19 := _pc("barbarian", 19)
	assert_true("boon_of_irresistible_offense" in b19.features, "19레벨 서사 은혜 재주")
	assert_true(b19.has_cap("ignore_physical_resistance"))
	var m := _pc("monk", 20)
	assert_true(int(m.abilities["dex"]) > 20, "몸과 마음")
	assert_eq(_pc("fighter", 20).attacks_per_action, 4, "추가 공격 3회")


func test_barbarian_might_and_brutal() -> void:
	var b := _pc("barbarian", 18)
	Dice.force([1])
	var s := Resolver.saving_throw(b, "str", int(b.abilities["str"]))
	assert_true(s["success"], "불굴의 힘: 합계 하한 = 근력 점수")


func test_rogue_elusive_and_luck() -> void:
	var r := _pc("rogue", 20)
	var foe := make_creature({"team": "enemy", "hp_max": 50})
	var w := make_world(["....."])
	w["grid"].place(r, Vector2i(0, 0))
	w["grid"].place(foe, Vector2i(1, 0))
	r.apply_condition("prone", -1)
	var p := Resolver.preview_attack(foe, r, {"name": "x", "bonus": 5, "kind": "melee", "damage": [{"dice": "1", "damage_type": "slashing"}]},
		w["grid"].attack_context(foe, r))
	assert_true(int(p["mode"]) <= 0, "포착 불가: 넘어져도 유리 없음")
	var bonus: int = r.save_bonus("dex")
	Dice.force([2])
	assert_true(Resolver.saving_throw(r, "dex", 15 + bonus)["success"], "행운의 일격: 20으로")
	assert_eq(r.resource("stroke_of_luck"), 0)


func test_ranger_and_paladin() -> void:
	var rg := _pc("ranger", 20)
	var foe := make_creature({"team": "enemy", "hp_max": 300, "ac_base": 10})
	var w := make_world([".........."])
	w["grid"].place(rg, Vector2i(0, 0))
	w["grid"].place(foe, Vector2i(5, 0))
	foe.apply_condition("hunters_marked", -1, rg)
	var atk := Combat.build_weapon_attack(rg, rg.weapon_sets["ranged"]["main"])
	var p := Resolver.preview_attack(rg, foe, atk, w["grid"].attack_context(rg, foe))
	assert_eq(int(p["mode"]), 1, "정밀한 사냥꾼")
	Dice.force([15])
	var res := Resolver.attack(rg, foe, atk, w["grid"].attack_context(rg, foe))
	assert_true(res["extra_damage"].any(func(x: Dictionary) -> bool: return x["dice"] == "1d10"), "적 처단자: d10")
	var pd := _pc("paladin", 20)
	var w2 := make_world(["........"])
	var enemy := make_creature({"team": "enemy", "hp_max": 100})
	w2["grid"].place(pd, Vector2i(0, 0))
	w2["grid"].place(enemy, Vector2i(4, 0))
	pd.reset_turn()
	assert_true(Features.use(w2, pd, "holy_nimbus")["ok"])
	Resolver.start_turn(enemy, {"in_combat": true})
	assert_eq(enemy.hp, 100 - pd.ability_mod("cha") - pd.proficiency_bonus, "성스러운 후광(오라 6칸)")


func test_fighter_survivor_and_monk_defense() -> void:
	var f := _pc("fighter", 18)
	f.hp = f.hp_max / 2
	var before: int = f.hp
	Resolver.start_turn(f, {"in_combat": true})
	assert_eq(f.hp, before + 5 + f.ability_mod("con"), "영웅적 반격")
	var m := _pc("monk", 18)
	var w := make_world(["...."])
	w["grid"].place(m, Vector2i(0, 0))
	m.reset_turn()
	assert_true(Features.use(w, m, "superior_defense")["ok"])
	assert_true(m.resists("fire") and not m.resists("force"), "탁월한 방어")


func test_wizard_spell_mastery_and_druid() -> void:
	var wz := _pc("wizard", 20)
	assert_true("magic_missile" in wz.get_meta("at_will", []) and "misty_step" in wz.get_meta("at_will", []), "주문 숙달")
	assert_eq(wz.resource("innate_fireball"), 1, "대표 주문")
	assert_eq(str(wz.resources["innate_fireball"]["recharge"]), "short")
	var d := _pc("druid", 18)
	var w := make_world(["......"])
	w["grid"].place(d, Vector2i(0, 0))
	d.apply_condition("wild_shaped", -1, d)
	d.reset_turn()
	assert_eq(Spellcasting.can_cast(w, d, "healing_word", Vector2i(0, 0)), "", "야수 주문")
	var cl := _pc("cleric", 17)
	assert_true(cl.has_cap("max_healing_dice"), "최상의 치유")
