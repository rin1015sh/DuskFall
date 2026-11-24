extends "res://tests/test_case.gd"
## 바바리안: 분노(저항·근력 피해 +2·근력 유리·주문 불가·중갑 불가), 맨몸 방어(10 + 민첩 + 건강), 위험 감지, 무모한 공격,
## 원시 지식(기능 숙련), 빠른 이동, 광전사 광란.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Features := preload("res://scripts/rules/features.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Equipment := preload("res://scripts/rules/equipment.gd")


func _bar(lv: int) -> Node:
	var r := Builder.build(Builder.default_spec("barbarian", lv))
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func test_build_unarmored_fast_skills() -> void:
	var b := _bar(5)
	assert_eq(b.ac(), 10 + b.ability_mod("dex") + b.ability_mod("con"), "맨몸 방어")
	assert_eq(b.speed_tiles, 8, "빠른 이동 +2칸")
	assert_true(b.skill_bonuses.has("intimidation"), "원시 지식")
	assert_eq(b.resource("rage"), 3)
	assert_eq(b.attacks_per_action, 2)
	Dice.force([5, 15])
	assert_eq(int(Resolver.saving_throw(b, "dex", 10)["mode"]), 1, "위험 감지")
	b.inventory = {"plate_armor": 1}
	Equipment.equip({}, b, "plate_armor")
	assert_eq(b.speed_tiles, 6, "중갑이면 빠른 이동 없음")
	assert_false(Features.use({}, b, "rage")["ok"], "중갑이면 분노 불가")


func test_rage_effects() -> void:
	var w := make_world(["...."])
	var b := _bar(3)
	w["grid"].place(b, Vector2i(0, 0))
	b.reset_turn()
	var before: String = Combat.build_weapon_attack(b, "greataxe")["damage"][0]["dice"]
	assert_true(Features.use(w, b, "rage")["ok"])
	assert_eq(b.resource("rage"), 2)
	var after: String = Combat.build_weapon_attack(b, "greataxe")["damage"][0]["dice"]
	assert_eq(after, "1d12%+d" % (b.ability_mod("str") + 2), "분노 피해 +2 (%s → %s)" % [before, after])
	var r := Resolver.apply_damage(b, [{"amount": 10, "damage_type": "slashing"}], {})
	assert_eq(int(r["total"]), 5, "참격 저항")
	Dice.force([5, 15])
	assert_eq(int(Resolver.ability_check(b, "str", 10)["mode"]), 1, "근력 판정 유리")
	assert_true(b.has_flag("no_spellcasting"), "분노 중 주문 불가")


func test_reckless_and_frenzy() -> void:
	var w := make_world(["....."])
	var b := _bar(3)
	var f := make_creature({"team": "enemy", "hp_max": 80, "ac_base": 5})
	w["grid"].place(b, Vector2i(0, 0))
	w["grid"].place(f, Vector2i(1, 0))
	b.reset_turn()
	Features.use(w, b, "rage")
	assert_true(Features.use(w, b, "reckless_attack")["ok"])
	Dice.force([18, 18])
	var res: Dictionary = Combat.attack(w, b, f, {"weapon": "greataxe"})
	assert_eq(int(res["mode"]), 1, "무모한 공격: 근력 공격 유리")
	assert_true(b.has_condition("frenzy"), "광전사: 분노가 광란(BG3)")
	assert_false(Features.use(w, b, "reckless_attack")["ok"], "턴에 한 번")
	Dice.force([5, 15])
	var back: Dictionary = Combat.attack(w, f, b, {"weapon": "unarmed"})
	assert_eq(int(back["mode"]), 1, "나를 노리는 공격 유리")
