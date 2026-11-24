extends "res://tests/test_case.gd"
## 레인저 BG3 하위 클래스(4단계, 3레벨): 사냥꾼 BG3판·야수 조련사·어둠 추적자·무리지기.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Features := preload("res://scripts/rules/features.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func _rg(lv: int, sub: String, extra: Dictionary = {}) -> Node:
	var spec := Builder.default_spec("ranger", lv)
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


func test_hunter() -> void:
	var r := _rg(11, "hunter", {"hunters_prey": "giant_killer", "defensive_tactics": "multiattack_defense"})
	var big := _foe({"size": "large"})
	var w := make_world(["......", "......", "......"])
	w["grid"].place(r, Vector2i(0, 0))
	w["grid"].place(big, Vector2i(1, 0))
	r.refresh_reaction()
	var hp: int = big.hp
	Dice.force([1, 15, 3])
	Combat._do_attack(w, big, r, {"name": "주먹", "bonus": 0, "kind": "melee", "weapon": false, "damage": [{"dice": "1", "damage_type": "bludgeoning"}]})
	assert_true(big.hp < hp, "거인 사냥꾼 반응 공격")
	var ctx := Combat.attack_context(w, big, r, {"kind": "melee"})
	assert_eq(int(ctx.get("attack_add", 0)), -4, "다중 공격 방어 −4")
	var e2 := _foe()
	w["grid"].place(e2, Vector2i(1, 1))
	r.reset_turn()
	Dice.force([15, 3, 15, 3])
	var res: Dictionary = Features.use(w, r, "whirlwind_attack")
	assert_eq(res["targets"], 2, "소용돌이: 1칸 안 적 모두")


func test_beast_master() -> void:
	var r := _rg(11, "beast_master")
	var w := make_world(["......", "......"])
	w["grid"].place(r, Vector2i(0, 0))
	r.reset_turn()
	r.options["ranger_companion"] = "bear"
	var res: Dictionary = Features.use(w, r, "rangers_companion")
	assert_true(res["ok"])
	var m: Node = res["summon"]
	assert_eq(m.hp_max, 99, "11레벨 곰 HP")
	assert_eq(m.ac_base, 18)
	assert_eq(m.attacks_per_action, 2, "야수의 분노")
	assert_false(m.is_hostile_to(r))


func test_gloom_stalker() -> void:
	var r := _rg(11, "gloom_stalker")
	assert_true(r.spells.has("disguise_self") and r.spells.has("fear"))
	assert_true("wis" in r.save_proficiencies and "int" in r.save_proficiencies, "강철 정신")
	var e := _foe({"ac_base": 30})
	var w := make_world(["......"])
	w["grid"].place(r, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(1, 0))
	r.reset_turn()
	r.turn["dread_ambush"] = true
	Combat.attack(w, r, e, {"weapon": r.weapon("main")})
	assert_eq(int(r.turn["attacks_left"]), 2, "매복: 공격 1회 더(3회 중 1회 씀)")
	assert_true(r.turn.get("flurry_used", false), "빗나가서 추적자의 연타")


func test_swarmkeeper() -> void:
	var r := _rg(11, "swarmkeeper", {"gathered_swarm": "bees"})
	assert_true(r.spells.has("faerie_fire") and r.spells.has("web"))
	var e := _foe()
	var w := make_world(["........"])
	w["grid"].place(r, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(1, 0))
	r.reset_turn()
	r.refresh_reaction()
	r.options["swarm_mode"] = "utility"
	Dice.force([15, 3, 1])
	Combat.attack(w, r, e, {"weapon": r.weapon("main")})
	assert_true(w["grid"].cell_of(e).x >= 3 and e.has_condition("prone"), "벌 군단: 밀기 + 강력한 무리 넘어짐")
	r.reset_turn()
	assert_true(Features.use(w, r, "writhing_tide")["ok"])
	assert_true(r.has_condition("flying"))
