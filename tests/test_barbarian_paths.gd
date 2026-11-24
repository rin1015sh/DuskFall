extends "res://tests/test_case.gd"
## 바바리안 BG3 길(4단계, 3레벨): 광전사 BG3판·야생의 심장·야생 마법·거인.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Features := preload("res://scripts/rules/features.gd")
const Primal := preload("res://scripts/rules/primal.gd")
const Physics := preload("res://scripts/rules/physics.gd")


func _bb(lv: int, sub: String, extra: Dictionary = {}) -> Node:
	var spec := Builder.default_spec("barbarian", lv)
	spec["subclass"] = sub
	spec["species"] = "human"
	spec.merge(extra, true)
	var r := Builder.build(spec)
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func _foe(v: Dictionary = {}) -> Node:
	var d := {"team": "enemy", "ac_base": 5, "hp_max": 100, "abilities": {"str": 10, "dex": 10, "con": 1, "wis": 1, "cha": 1}}
	d.merge(v, true)
	return make_creature(d)


func test_berserker_frenzy() -> void:
	var b := _bb(10, "berserker")
	var e := _foe()
	var w := make_world(["......"])
	w["grid"].place(b, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(1, 0))
	b.reset_turn()
	assert_false(Features.use(w, b, "frenzied_strike", e)["ok"], "광란 전에는 못 쓴다")
	assert_true(Features.use(w, b, "rage")["ok"])
	assert_true(b.has_condition("frenzy"))
	b.reset_turn()
	Dice.force([15])
	assert_true(Features.use(w, b, "frenzied_strike", e)["ok"])
	assert_eq(int(b.condition_instance("frenzied_strain")["params"]["n"]), 1, "긴장 1층")
	b.reset_turn()
	Dice.force([15, 2])
	var r: Dictionary = Features.use(w, b, "enraged_throw", e)
	assert_true(r.get("hit", false) and e.has_condition("prone"), "격노의 투척 넘어짐")
	b.remove_condition("raging")
	assert_false(b.has_condition("frenzy") or b.has_condition("frenzied_strain"), "분노와 함께 끝남")
	b.reset_turn()
	Dice.force([1])
	assert_true(Features.use(w, b, "intimidating_presence", e)["ok"])
	assert_true(e.has_condition("frightened"), "위협적인 존재감")


func test_wildheart_hearts() -> void:
	var b := _bb(6, "wildheart", {"bestial_heart": "bear", "animal_aspect": "stallion"})
	var w := make_world(["......"])
	w["grid"].place(b, Vector2i(0, 0))
	b.reset_turn()
	Features.use(w, b, "rage")
	assert_true(b.has_condition("rage_bear_heart"))
	assert_true("fire" in b.active_conditions().filter(func(a: Dictionary) -> bool: return a["id"] == "rage_bear_heart")[0]["def"]["modifiers"][0]["damage_types"])
	b.hp -= 20
	b.reset_turn()
	assert_true(Features.use(w, b, "unrelenting_ferocity")["ok"])
	b.reset_turn()
	assert_false(Features.use(w, b, "unrelenting_ferocity")["ok"], "분노마다 1회")
	b.reset_turn()
	Combat.dash(b)
	assert_eq(b.temp_hp, 12, "종마: 레벨 × 2")
	var wolf := _bb(3, "wildheart", {"bestial_heart": "wolf"})
	var ally := make_creature({"team": "party", "hp_max": 20})
	var e := _foe()
	var w2 := make_world(["......"])
	w2["grid"].place(wolf, Vector2i(0, 0))
	w2["grid"].place(e, Vector2i(1, 0))
	w2["grid"].place(ally, Vector2i(2, 0))
	wolf.reset_turn()
	Features.use(w2, wolf, "rage")
	var ctx := Combat.attack_context(w2, ally, e, {"kind": "melee"})
	assert_true("늑대의 심장" in ctx["advantage"], "늑대: 아군 근접 유리")


func test_wildheart_elk_stampede() -> void:
	var b := _bb(3, "wildheart", {"bestial_heart": "elk"})
	var e := _foe()
	var w := make_world([".........."])
	w["grid"].place(b, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(3, 0))
	b.reset_turn()
	var sp: int = b.speed()
	Features.use(w, b, "rage")
	assert_eq(b.speed(), sp + 3, "엘크: 이동 +3칸")
	b.reset_turn()
	w["grid"].move_creature(e, Vector2i(3, 0))
	Dice.force([15, 3, 1])
	var r: Dictionary = Features.use(w, b, "primal_stampede", Vector2i(6, 0))
	assert_true(r["ok"] and r["moved"])
	assert_eq(w["grid"].cell_of(b), Vector2i(2, 0), "길을 막은 적 앞에서 멈춤")
	assert_eq(r["hits"], 1)
	assert_true(e.has_condition("prone"), "근력 내성 실패 넘어짐")


func test_wild_magic() -> void:
	var b := _bb(10, "wild_magic")
	var e := _foe()
	var w := make_world([".........."])
	w["grid"].place(b, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(3, 0))
	b.reset_turn()
	Dice.force([5])  # d8 = 5 → 보호의 빛
	Features.use(w, b, "rage")
	assert_true(b.has_condition("wm_protective_lights"))
	var ctx := Combat.attack_context(w, e, b, {"kind": "ranged", "range_tiles": [12, 12]})
	assert_eq(int(ctx.get("ac_add", 0)), 1, "보호의 빛 AC +1")
	Primal.surge(w, b, "wm_teleport")
	assert_false(b.has_condition("wm_protective_lights"), "효과가 바뀐다")
	b.reset_turn()
	assert_true(Features.use(w, b, "wild_teleport", Vector2i(8, 0))["ok"])
	assert_eq(w["grid"].cell_of(b), Vector2i(8, 0))
	b.remove_condition("raging")
	assert_false(b.has_condition("wm_teleport"), "분노와 함께 끝남")
	assert_eq(b.resource("bolstering_magic"), b.proficiency_bonus)
	var ally := make_creature({"team": "party", "hp_max": 20})
	w["grid"].place(ally, Vector2i(7, 0))
	b.reset_turn()
	assert_true(Features.use(w, b, "bolstering_magic_boon", ally)["ok"])
	assert_true(ally.has_condition("bolstering_boon"))


func test_giant() -> void:
	var b := _bb(10, "giant")
	var e := _foe({"weight_kg": 70.0})
	var w := make_world(["..........", ".........."])
	w["grid"].place(b, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(1, 0))
	b.reset_turn()
	Features.use(w, b, "rage")
	assert_true(b.has_condition("giants_rage") and b.has_flag("throw_rage_double"))
	b.options["elemental_cleaver"] = "cold"
	assert_true(Features.use(w, b, "elemental_cleaver")["ok"])
	assert_true(b.has_condition("elemental_cleaver_cold"))
	b.reset_turn()
	Dice.force([1, 2])
	var r: Dictionary = Features.use(w, b, "mighty_impel", e)
	assert_true(r["thrown"])
	assert_eq(w["grid"].cell_of(e), Vector2i(7, 0), "6칸 던짐")
	assert_true(e.has_condition("prone"))
