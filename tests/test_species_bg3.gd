extends "res://tests/test_case.gd"
## 종족 BG3 개편(changes.md 2026-11-24): 무기·갑옷 훈련, 암시야 8/16칸, 드로우·하프엘프·하프오크·아스트란·드래곤본.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Features := preload("res://scripts/rules/features.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func _b(cls: String, lv: int, extra: Dictionary) -> Node:
	var spec := Builder.default_spec(cls, lv)
	spec.merge(extra, true)
	var r := Builder.build(spec)
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func test_racial_training() -> void:
	var e := _b("wizard", 1, {"species": "elf", "lineage": "elf_wood"})
	assert_true(e.weapon_proficiencies.has("longbow"), "엘프 무기 훈련")
	assert_true(e.skill_bonuses.has("perception") and e.skill_bonuses.has("stealth"), "예리한 감각·숲의 은신")
	assert_eq(e.darkvision_tiles, 8, "암시야 12m")
	var h := _b("wizard", 1, {"species": "human"})
	assert_true(h.weapon_proficiencies.has("halberd") and h.has_cap("carry_quarter_more"), "시민 군사 훈련·다재다능")
	var d := _b("wizard", 1, {"species": "dwarf", "lineage": "dwarf_gray"})
	assert_eq(d.darkvision_tiles, 16, "회색 드워프 뛰어난 암시야")
	assert_eq(d.speed_tiles, 5, "드워프 7.5m")
	assert_true("paralyzed" in d.save_advantage_vs)


func test_astran() -> void:
	var a := _b("fighter", 5, {"species": "astran", "astral_knowledge": "int"})
	assert_true(a.skill_bonuses.has("arcana") and a.skill_bonuses.has("history"), "별계의 지식: 지능 기능 전부")
	assert_true(a.spells.has("misty_step"), "염력 5레벨")


func test_dragonborn_breath() -> void:
	var dbn := _b("fighter", 5, {"species": "dragonborn", "lineage": "dragonborn_red"})
	assert_true("fire" in dbn.damage_resistances)
	var foe := make_creature({"team": "enemy", "hp_max": 50, "abilities": {"str": 10, "dex": 1, "con": 10, "wis": 10, "cha": 10}})
	var w := make_world(["......", "......"])
	w["grid"].place(dbn, Vector2i(0, 0))
	w["grid"].place(foe, Vector2i(2, 0))
	dbn.reset_turn()
	Dice.force([3, 3, 3, 1])
	var r: Dictionary = Features.use(w, dbn, "breath_weapon_red", Vector2i(2, 0))
	assert_true(r["ok"] and r["targets"] == 1, "원뿔 숨결")
	assert_eq(foe.hp, 41, "5레벨 3d6")
	assert_eq(dbn.resource("breath_weapon"), 0)


func test_half_orc_savage() -> void:
	var o := _b("fighter", 1, {"species": "half_orc"})
	var foe := make_creature({"team": "enemy", "hp_max": 80, "ac_base": 5})
	var w := make_world(["...."])
	w["grid"].place(o, Vector2i(0, 0))
	w["grid"].place(foe, Vector2i(1, 0))
	o.reset_turn()
	Dice.force([20])
	var r: Dictionary = load("res://scripts/rules/combat.gd").attack(w, o, foe, {"weapon": o.weapon("main")})
	assert_true(r["crit"] and r["extra_damage"].size() >= 1, "야만적인 공격")
