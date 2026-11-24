extends "res://tests/test_case.gd"
## 드루이드 BG3 회합(4단계, 2레벨에 고름): 대지 BG3판·월광(달)·균사(포자)·별빛(별).

const Builder := preload("res://scripts/rules/character_builder.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Features := preload("res://scripts/rules/features.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const WildShape := preload("res://scripts/rules/effects/wild_shape.gd")


func _dr(lv: int, sub: String, extra: Dictionary = {}) -> Node:
	var spec := Builder.default_spec("druid", lv)
	spec["subclass"] = sub
	spec.merge(extra, true)
	var r := Builder.build(spec)
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func _foe(v: Dictionary = {}) -> Node:
	var d := {"team": "enemy", "ac_base": 10, "hp_max": 100, "abilities": {"str": 10, "dex": 10, "con": 1, "wis": 1, "cha": 1}}
	d.merge(v, true)
	return make_creature(d)


const CLUB := {"name": "몽둥이", "bonus": 5, "kind": "melee", "weapon": false, "damage": [{"dice": "5", "damage_type": "bludgeoning"}]}


func test_land() -> void:
	var d := _dr(6, "land", {"circle_land_spells": "underdark"})
	assert_true(d.spells.has("web") and d.spells.has("gaseous_form"), "지하 땅 주문")
	assert_true(d.has_cap("ignore_difficult_terrain"), "대지 걸음")
	assert_true(d.resources.has("natural_recovery"))
	var d10 := _dr(10, "land")
	assert_true("poison" in d10.damage_immunities and "poisoned" in d10.condition_immunities, "자연의 수호")
	var fey := _foe({"creature_type": "fey"})
	assert_false(d10.apply_condition("charmed", 2, fey), "요정이 거는 매혹 면역")


func test_moon() -> void:
	var d := _dr(2, "moon")
	assert_true("brown_bear" in WildShape.forms_for(d), "2레벨 갈색 곰")
	var d10 := _dr(10, "moon")
	var f := WildShape.forms_for(d10)
	assert_true("saber_toothed_tiger" in f and "earth_elemental" in f, "8·10레벨 형태")
	var w := make_world(["....."])
	w["grid"].place(d10, Vector2i(0, 0))
	d10.reset_turn()
	d10.options["wild_shape_form"] = "earth_elemental"
	assert_true(Features.use(w, d10, "wild_shape")["ok"])
	assert_eq(d10.ac_base, 17, "흙 정령 AC")
	d10.hp -= 20
	var hp: int = d10.hp
	d10.reset_turn()
	assert_true(Features.use(w, d10, "lunar_mend")["ok"], "달빛 치유")
	assert_true(d10.hp > hp)


func test_spores() -> void:
	var d := _dr(2, "spores")
	assert_true(d.spells.has("chill_touch"))
	var e := _foe()
	var ally := make_creature({"team": "party", "hp_max": 30, "ac_base": 5})
	var w := make_world(["......"])
	w["grid"].place(d, Vector2i(0, 0))
	w["grid"].place(ally, Vector2i(2, 0))
	w["grid"].place(e, Vector2i(3, 0))
	d.refresh_reaction()
	Dice.force([15, 1, 4])
	Combat._do_attack(w, e, ally, CLUB)
	assert_eq(e.hp, 96, "포자 후광 1d4")
	d.reset_turn()
	assert_true(Features.use(w, d, "symbiotic_entity")["ok"])
	assert_eq(d.temp_hp, 8, "임시 HP 레벨 × 4")


func test_stars() -> void:
	var d := _dr(6, "stars")
	assert_true(d.spells.has("guiding_bolt") and d.resource("innate_guiding_bolt") == d.proficiency_bonus, "별자리 지도")
	var e := _foe()
	var w := make_world(["........"])
	w["grid"].place(d, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(5, 0))
	d.reset_turn()
	d.options["starry_form"] = "archer"
	assert_true(Features.use(w, d, "starry_form")["ok"])
	d.reset_turn()  # 다음 턴(형상은 긴 휴식까지)
	Dice.force([15, 4])
	var r: Dictionary = Features.use(w, d, "luminous_arrow", e)
	assert_true(r.get("hit", false), str(r))
	assert_eq(e.hp, 100 - 4 - d.ability_mod("wis"), "빛의 화살")
	d.remove_condition("starry_archer")
	d.apply_condition("starry_dragon", -1, d)
	d.concentration = {"spell": "bless"}
	Dice.force([2])
	var c := Resolver.concentration_check(d, 10)
	assert_eq(int(c["natural"]), 10, "용: 집중 유지 9 이하는 10")
	assert_true(d.get_meta("omen") in ["weal", "woe"], "우주의 징조")
