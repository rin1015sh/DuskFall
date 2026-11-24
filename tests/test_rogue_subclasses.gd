extends "res://tests/test_case.gd"
## 로그 BG3 서브클래스(4단계): 도둑 BG3판·비전 사기꾼·그림자 칼날(암살자)·허세꾼(스워시버클러).

const Builder := preload("res://scripts/rules/character_builder.gd")
const Actions := preload("res://scripts/rules/actions.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Features := preload("res://scripts/rules/features.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Physics := preload("res://scripts/rules/physics.gd")


func _pc(lv: int, extra: Dictionary) -> Node:
	var spec := Builder.default_spec("rogue", lv)
	spec.merge(extra, true)
	var r := Builder.build(spec)
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func _foe(v: Dictionary = {}) -> Node:
	var d := {"team": "enemy", "ac_base": 5, "hp_max": 100, "abilities": {"str": 10, "dex": 10, "con": 10, "wis": 1, "cha": 1}}
	d.merge(v, true)
	return make_creature(d)


func test_thief_fall_resistance() -> void:
	var r := _pc(3, {})
	var out := Physics.fall(r, 4)
	assert_eq(int(out["damage"]), Physics.fall_damage(r, 4) / 2, "BG3 낙하 피해 절반")


func test_assassin() -> void:
	var r := _pc(3, {"subclass": "assassin"})
	var e := _foe()
	var w := make_world(["....."])
	w["grid"].place(r, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(1, 0))
	e.set_meta("not_acted_yet", true)  # 전투 시작(start_combat)이 붙이고, 그 생물의 첫 턴(begin_turn)이 뗀다
	e.apply_condition("surprised", -1, "combat_start")
	r.reset_turn()
	var p := Resolver.preview_attack(r, e, Combat.build_weapon_attack(r, r.weapon("main")), w["grid"].attack_context(r, e))
	assert_eq(int(p["mode"]), 1, "아직 행동하지 않은 대상에게 유리")
	Dice.force([12, 12])
	var res := Combat.attack(w, r, e)
	assert_true(res["crit"], "기습당한 대상 명중 → 치명타")
	w["turns"].begin_turn(e)
	assert_false(e.has_meta("not_acted_yet"), "첫 턴이 오면 풀린다")


func test_swashbuckler() -> void:
	var r := _pc(4, {"subclass": "swashbuckler"})
	assert_eq(r.initiative_bonus, r.proficiency_bonus, "대담함: 이니셔티브 + 숙련")
	var e := _foe()
	var w := make_world([".....", "....."])
	w["grid"].place(r, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(1, 0))
	r.reset_turn()
	Dice.force([12, 3, 3, 3])
	var res := Combat.attack(w, r, e)
	assert_true(int(res.get("sneak_attack", 0)) > 0, "곁에 다른 생물이 없으면 급소 공격")
	var list: Array = Actions.list_for(w, r)["class"]
	assert_true("wa_d_flick" in list and "wa_d_sand" in list and "wa_d_mockery" in list, "지저분한 수법")
	r.reset_turn()
	Dice.force([1])
	var m: Dictionary = Actions.execute(w, r, "wa_d_mockery", Vector2i(1, 0))
	assert_true(m["ok"])
	assert_true(e.has_condition("mocked"), "조롱: 다음 공격 불리")


func test_panache() -> void:
	var r := _pc(9, {"subclass": "swashbuckler"})
	var e := _foe({"creature_type": "humanoid"})
	var ally := make_creature({"team": "party", "hp_max": 20})
	var w := make_world(["....."])
	w["grid"].place(r, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(2, 0))
	w["grid"].place(ally, Vector2i(4, 0))
	r.reset_turn()
	Dice.force([18, 2])
	assert_true(Features.use(w, r, "panache", e)["success"])
	assert_true(e.has_condition("panache_goaded"))
	var atk := {"name": "몽둥이", "bonus": 0, "kind": "melee", "weapon": false, "damage": [{"dice": "1", "damage_type": "bludgeoning"}]}
	assert_eq(int(Resolver.preview_attack(e, ally, atk, {"distance_tiles": 1})["mode"]), -1, "나 아닌 생물 공격 불리")
	assert_eq(int(Resolver.preview_attack(e, r, atk, {"distance_tiles": 1})["mode"]), 0, "나는 그대로")


func test_arcane_trickster() -> void:
	var r := _pc(3, {"subclass": "arcane_trickster", "subclass_spells": {"cantrips": ["fire_bolt", "minor_illusion"], "spells": ["charm_person", "sleep", "magic_missile"]},
		"scores": {"str": 8, "dex": 15, "con": 14, "int": 13, "wis": 12, "cha": 10}, "bonus": {"dex": 2, "int": 1}})
	assert_true(r.spells.has("mage_hand"), "마법사의 손 항상 준비")
	assert_true(r.spells.has("charm_person") and r.spells.has("magic_missile"))
	assert_eq(r.resource("spell_slot_1"), 2)
	assert_eq(Spellcasting.ability_for(r, "sleep"), "int")
	var r9 := _pc(9, {"subclass": "arcane_trickster", "subclass_spells": {"cantrips": ["fire_bolt", "minor_illusion"], "spells": ["charm_person", "sleep", "magic_missile"]}})
	assert_true(r9.has_cap("magical_ambush"))
	var e := _foe()
	r9.apply_condition("invisible", -1, "hide")
	var s := Resolver.saving_throw(e, "wis", 10, {"source": r9, "magic": true})
	assert_eq(int(s["mode"]), -1, "마법 매복: 숨은 채 쓴 주문 내성 불리")
