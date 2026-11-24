extends "res://tests/test_case.gd"
## 바드 BG3 학파(4단계, 3레벨): 지식·용맹·칼날·매혹.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Features := preload("res://scripts/rules/features.gd")
const Actions := preload("res://scripts/rules/actions.gd")


func _bd(lv: int, sub: String, extra: Dictionary = {}) -> Node:
	var spec := Builder.default_spec("bard", lv)
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


func test_valour_combat_inspiration() -> void:
	var b := _bd(6, "valour")
	assert_true(b.has_cap("combat_inspiration") and b.has_cap("extra_attack"))
	var ally := make_creature({"team": "party", "hp_max": 30, "ac_base": 12})
	var e := _foe()
	var w := make_world(["....."])
	w["grid"].place(b, Vector2i(0, 0))
	w["grid"].place(ally, Vector2i(1, 0))
	w["grid"].place(e, Vector2i(2, 0))
	b.reset_turn()
	assert_true(Features.use(w, b, "bardic_inspiration", ally)["ok"])
	Dice.force([8, 6])  # 8 + 5 = 13 vs AC 12 → 영감 d8=6 → AC 18 빗나감
	var r: Dictionary = Combat._do_attack(w, e, ally, CLUB)
	assert_false(r.get("hit", false), "전투 영감으로 AC")
	assert_false(ally.has_condition("bardic_inspiration"), "영감을 썼다")


func test_swords_flourishes() -> void:
	var b := _bd(3, "swords", {"species": "human"})
	var learned: Array = b.get_meta("special_attacks", [])
	assert_true("wa_f_defensive" in learned and "wa_f_mobile" in learned)
	var e := _foe()
	var w := make_world(["........"])
	w["grid"].place(b, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(1, 0))
	var n: int = b.resource("bardic_inspiration")
	b.reset_turn()
	Dice.force([1])
	Actions.execute(w, b, "wa_f_defensive", Vector2i(1, 0))
	assert_eq(b.resource("bardic_inspiration"), n, "빗나가면 영감을 쓰지 않는다")
	b.reset_turn()
	Dice.force([15, 3, 3])
	var r: Dictionary = Actions.execute(w, b, "wa_f_defensive", Vector2i(1, 0))
	assert_true(r.get("hit", false))
	assert_eq(b.resource("bardic_inspiration"), n - 1)
	assert_true(b.has_condition("defensive_flourish"), "AC +4")
	b.reset_turn()
	Dice.force([15, 3, 3])
	Actions.execute(w, b, "wa_f_mobile", Vector2i(1, 0))
	assert_eq(w["grid"].cell_of(e), Vector2i(5, 0), "4칸 밀림")


func test_glamour_mantles() -> void:
	var b := _bd(6, "glamour")
	var ally := make_creature({"team": "party", "hp_max": 30, "ac_base": 5})
	var e := _foe()
	var w := make_world(["......"])
	w["grid"].place(b, Vector2i(0, 0))
	w["grid"].place(ally, Vector2i(1, 0))
	w["grid"].place(e, Vector2i(2, 0))
	b.reset_turn()
	assert_true(Features.use(w, b, "mantle_of_inspiration")["ok"])
	assert_eq(ally.temp_hp, 8, "6레벨 임시 HP 8")
	Dice.force([15])
	Combat._do_attack(w, e, ally, CLUB)
	assert_true(e.has_condition("charmed"), "근접 공격자 매혹")
	b.reset_turn()
	assert_false(Features.use(w, b, "majesty_command", e)["ok"], "망토 없이 불가")
	assert_true(Features.use(w, b, "mantle_of_majesty")["ok"])
	assert_true(b.has_condition("mantle_of_majesty"))
	assert_eq(b.resource("mantle_of_majesty"), 0)


func test_lore_trimmed() -> void:
	var b := _bd(12, "lore")
	assert_true(b.feature_data.has("cutting_words"))
