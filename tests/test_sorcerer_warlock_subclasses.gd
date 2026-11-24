extends "res://tests/test_case.gd"
## 소서러·워락 BG3 하위 클래스(4단계, 1레벨): 용의 혈통 BG3판·야생 마법·폭풍·그림자 / 악마 BG3판·요정·위대한 옛것·주술검사.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Features := preload("res://scripts/rules/features.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Sorcery := preload("res://scripts/rules/sorcery.gd")


func _pc(cls: String, lv: int, sub: String, extra: Dictionary = {}) -> Node:
	var spec := Builder.default_spec(cls, lv)
	spec["subclass"] = sub
	spec["species"] = "human"
	spec.merge(extra, true)
	var r := Builder.build(spec)
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func _foe(v: Dictionary = {}) -> Node:
	var d := {"team": "enemy", "ac_base": 5, "hp_max": 100, "abilities": {"str": 1, "dex": 1, "con": 1, "wis": 1, "cha": 1}}
	d.merge(v, true)
	return make_creature(d)


func test_subclass_at_level_1() -> void:
	var s := _pc("sorcerer", 1, "draconic", {"draconic_ancestry": "green"})
	assert_true(s.spells.has("ray_of_sickness"), "초록 용: 병약 광선")
	assert_eq(s.ac(), 13 + s.ability_mod("dex"))
	var w := _pc("warlock", 1, "hexblade")
	assert_true(w.feature_data.has("hexblades_curse"))


func test_wild_magic() -> void:
	var s := _pc("sorcerer", 11, "wild_magic")
	var w := make_world(["......"])
	w["grid"].place(s, Vector2i(0, 0))
	s.reset_turn()
	assert_true(Features.use(w, s, "tides_of_chaos")["ok"])
	Dice.force([2, 15])
	var r := Resolver.saving_throw(s, "str", 10)
	assert_eq(int(r["mode"]), 1, "혼돈의 물결 유리")
	assert_false(s.has_condition("tides_of_chaos"))
	Sorcery.surge(w, s, "shield")
	assert_true(s.has_condition("surge_shield"))
	# 운 비틀기
	var ally := make_creature({"team": "party", "hp_max": 30, "ac_base": 12})
	var e := _foe()
	w["grid"].place(ally, Vector2i(1, 0))
	w["grid"].place(e, Vector2i(2, 0))
	s.refresh_reaction()
	Dice.force([8, 4])  # 8 + 5 = 13 vs 12 → −4 → 빗나감
	var res: Dictionary = Combat._do_attack(w, e, ally, {"name": "주먹", "bonus": 5, "kind": "melee", "weapon": false, "damage": [{"dice": "1", "damage_type": "bludgeoning"}]})
	assert_false(res["hit"], "운 비틀기")


func test_storm() -> void:
	var s := _pc("sorcerer", 11, "storm")
	assert_true("lightning" in s.damage_resistances)
	var e := _foe()
	var w := make_world(["........"])
	w["grid"].place(s, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(2, 0))
	s.reset_turn()
	var hp: int = e.hp
	Spellcasting.cast(w, s, "thunderwave", Vector2i(1, 0))
	assert_true(e.hp <= hp - 5, "폭풍의 심장 레벨/2")
	s.reset_turn()
	s.turn["tempest_ready"] = true
	assert_true(Features.use(w, s, "tempestuous_flight", Vector2i(5, 0))["ok"], "폭풍 비행")


func test_shadow_magic() -> void:
	var s := _pc("sorcerer", 6, "shadow_magic")
	var e := _foe()
	var w := make_world(["........"])
	w["grid"].place(s, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(4, 0))
	s.reset_turn()
	assert_true(Features.use(w, s, "hound_of_ill_omen", e)["ok"])
	assert_true(e.has_condition("ill_omen"))
	s.hp = 1
	Resolver.apply_damage(s, [{"amount": 20, "damage_type": "fire"}])
	assert_eq(s.hp, 1, "무덤의 힘")
	assert_false(s.is_down())


func test_warlock_patrons() -> void:
	var h := _pc("warlock", 10, "hexblade")
	var e := _foe()
	var w := make_world(["......"])
	w["grid"].place(h, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(1, 0))
	h.reset_turn()
	assert_true(Features.use(w, h, "hexblades_curse", e)["ok"])
	Dice.force([15, 3])
	var r: Dictionary = Combat.attack(w, h, e, {"weapon": h.weapon("main")})
	assert_true(r["extra_damage"].any(func(x: Dictionary) -> bool: return x["dice"] == str(h.proficiency_bonus)), "저주: 피해 + 숙련")
	assert_eq(int(r["crit_threshold"]), 19, "치명타 범위 −1")
	h.hp = 10
	Resolver.apply_damage(e, [{"amount": 999, "damage_type": "fire"}])
	assert_true(h.hp > 10, "저주받은 대상이 죽으면 회복")
	var g := _pc("warlock", 10, "great_old_one")
	assert_true("psychic" in g.damage_resistances)
	var e2 := _foe()
	var w2 := make_world(["......"])
	w2["grid"].place(g, Vector2i(0, 0))
	w2["grid"].place(e2, Vector2i(1, 0))
	g.turn["reaction"] = 0  # 지옥의 질책 반응 빼고
	Resolver.apply_damage(g, [{"amount": 10, "damage_type": "psychic"}], {"attacker": e2})
	assert_eq(e2.hp, 95, "생각의 방패 반사(저항 후 5)")
	var f := _pc("warlock", 6, "archfey")
	var e3 := _foe()
	var w3 := make_world(["......"])
	w3["grid"].place(f, Vector2i(0, 0))
	w3["grid"].place(e3, Vector2i(1, 0))
	f.reset_turn()
	Dice.force([1])
	assert_true(Features.use(w3, f, "fey_presence")["ok"])
	assert_true(e3.has_condition("charmed"), "요정의 존재감")
