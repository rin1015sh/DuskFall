extends "res://tests/test_case.gd"
## 몽크 BG3 길(4단계, 3레벨): 열린 손 BG3판·그림자·사대 원소·술 취한 달인.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Features := preload("res://scripts/rules/features.gd")
const Actions := preload("res://scripts/rules/actions.gd")
const Rest := preload("res://scripts/rules/rest.gd")


func _mk(lv: int, sub: String, extra: Dictionary = {}) -> Node:
	var spec := Builder.default_spec("monk", lv)
	spec["subclass"] = sub
	spec["species"] = "human"
	spec.merge(extra, true)
	var r := Builder.build(spec)
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func _foe(v: Dictionary = {}) -> Node:
	var d := {"team": "enemy", "ac_base": 5, "hp_max": 100, "abilities": {"str": 10, "dex": 1, "con": 1, "wis": 1, "cha": 1}}
	d.merge(v, true)
	return make_creature(d)


func test_open_hand() -> void:
	var m := _mk(11, "open_hand")
	var e := _foe()
	var e2 := _foe()
	var w := make_world(["......", "......"])
	w["grid"].place(m, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(1, 0))
	w["grid"].place(e2, Vector2i(2, 0))
	m.reset_turn()
	m.options["manifestation"] = "soul"
	Dice.force([15])
	var r: Dictionary = Features.use(w, m, "ki_resonation_punch", e)
	assert_true(r["hit"] and e.has_condition("resonating_ki"))
	assert_true(r["extra_damage"].any(func(p: Dictionary) -> bool: return p["damage_type"] == "radiant"), "발현: 영혼 광휘")
	e2.apply_condition("resonating_ki", 10, m)
	var hp2: int = e2.hp
	var ki: int = m.resource("focus")
	Dice.force([3, 3, 3, 1, 3, 3, 3, 1, 1])
	var b: Dictionary = Features.use(w, m, "ki_resonation_blast", e)
	assert_eq(b["blasts"], 2, "연쇄 폭발")
	assert_true(e2.hp < hp2)
	assert_eq(m.resource("focus"), ki - 1)
	m.hp = 10
	m.reset_turn()
	m.resources["focus"]["current"] = 0
	assert_true(Features.use(w, m, "wholeness_of_body")["ok"])
	assert_eq(m.hp, mini(10 + 33, m.hp_max), "레벨 × 3 회복")
	assert_eq(m.resource("focus"), m.resources["focus"]["max"] / 2, "기 절반")
	m.reset_turn()
	assert_eq(int(m.turn["bonus"]), 2, "완전함: 보너스 행동 1 더")
	Rest.long_rest(w, [m])
	assert_true(m.extra_modifiers.any(func(x: Dictionary) -> bool: return x.get("source") == "tranquillity"), "평온")


func test_shadow() -> void:
	var m := _mk(11, "shadow")
	var e := _foe()
	var w := make_world(["..........", ".........."])
	for x in 10:
		for y in 2:
			w["grid"].set_base_light(Vector2i(x, y), w["grid"].Light.DIM)
	w["grid"].place(m, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(9, 0))
	m.reset_turn()
	assert_true(Features.use(w, m, "shadow_step", Vector2i(5, 0))["ok"])
	assert_true(m.has_condition("shadow_stepped"))
	m.reset_turn()
	assert_true(Features.use(w, m, "shadow_cloak")["ok"])
	assert_true(m.has_condition("invisible"))
	m.reset_turn()
	m.options["stunning_strike"] = "off"
	var ki: int = m.resource("focus")
	Dice.force([15, 3, 2, 2, 2])
	var r: Dictionary = Features.use(w, m, "shadow_strike", e)
	assert_true(r["ok"] and w["grid"].distance_between(m, e) == 1, "그림자 일격 순간 이동")
	assert_eq(m.resource("focus"), ki - 3, "기 3")
	m.reset_turn()
	assert_true(Features.use(w, m, "shadow_arts_darkness", Vector2i(3, 1))["ok"], "그림자 기술: 어둠")


func test_four_elements() -> void:
	var m := _mk(9, "four_elements", {"elemental_disciplines": ["fist_of_unbroken_air", "sweeping_cinder_strike", "water_whip", "flames_of_the_phoenix", "gong_of_the_summit"]})
	assert_true(m.has_cap("disc_fist_of_unbroken_air") and m.has_cap("disc_gong_of_the_summit"))
	assert_false(m.has_cap("disc_flames_of_the_phoenix"), "11레벨 수련은 9레벨에 못 고른다")
	var w := make_world(["..........", ".........."])
	var e := _foe()
	w["grid"].place(m, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(3, 0))
	m.options["stunning_strike"] = "off"
	var list: Array = Actions.list_for(w, m)["class"]
	assert_true("feature:water_whip" in list and not "feature:blade_of_rime" in list, "고른 수련만")
	m.reset_turn()
	var ki: int = m.resource("focus")
	Dice.force([5, 5, 5, 5, 1])
	assert_true(Features.use(w, m, "water_whip", e)["ok"])
	assert_eq(w["grid"].cell_of(e), Vector2i(1, 0), "물 채찍: 끌어옴")
	assert_eq(e.hp, 80, "향상된 원소 시전 4d10")
	assert_eq(m.resource("focus"), ki - 2)
	m.reset_turn()
	assert_true(Features.use(w, m, "sweeping_cinder_strike", Vector2i(1, 0))["ok"], "불타는 손(기 주문)")
	assert_eq(m.resource("focus"), ki - 4)
