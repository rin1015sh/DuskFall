extends "res://tests/test_case.gd"
## 스크립트 주문 29종(구현 어려운 것 묶음 1): 소환·비행·부양·환영·정신 조작·감지·잠금·침묵·휴식 주문 등.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Actions := preload("res://scripts/rules/actions.gd")
const MF := preload("res://scripts/rules/monster_factory.gd")
const Rest := preload("res://scripts/rules/rest.gd")
const Interact := preload("res://scripts/rules/interact.gd")


func _caster(cls: String, spells: Array) -> Node:
	var c: Node = own(Builder.build(Builder.default_spec(cls, 5))["creature"])
	for s: String in spells:
		if not c.spells.has(s):
			c.spells.append(s)
	c.reset_turn()
	return c


func _foe(values: Dictionary = {}) -> Node:
	var v := {"team": "enemy", "hp_max": 40, "ac_base": 5, "abilities": {"str": 1, "dex": 1, "con": 1, "int": 1, "wis": 1, "cha": 1}, "creature_type": "humanoid"}
	v.merge(values, true)
	return make_creature(v)


func _cast(w: Dictionary, c: Node, id: String, aim: Vector2i, opts: Dictionary = {}) -> Dictionary:
	c.reset_turn()
	var r: Dictionary = Spellcasting.cast(w, c, id, aim, opts)
	assert_true(r.get("ok", false), "%s: %s" % [id, r.get("reason", "")])
	return r


func test_fly_altitude_high_ground_and_fall() -> void:
	var w := make_world(["......"])
	var wz := _caster("wizard", ["fly"])
	var e := _foe()
	w["grid"].place(wz, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(3, 0))
	_cast(w, wz, "fly", Vector2i(0, 0))
	assert_true(wz.has_flag("flying") and wz.altitude == 2)
	assert_eq(w["grid"].attack_context(wz, e)["height_diff"], 2, "공중은 고지")
	assert_true(wz.speed() >= 12, "비행 속도 12칸")
	var hp: int = wz.hp
	Dice.force([3])
	wz.break_concentration("시험")
	assert_eq(wz.altitude, 0)
	assert_true(wz.hp < hp, "끝나면 떨어진다")


func test_levitate_and_spider_climb() -> void:
	var w := make_world(["03..."])
	var wz := _caster("wizard", ["levitate", "spider_climb"])
	var e := _foe()
	w["grid"].place(wz, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(3, 0))
	Dice.force([1])
	_cast(w, wz, "levitate", Vector2i(3, 0))
	assert_eq(e.altitude, 4)
	assert_eq(e.speed(), 0, "떠 있으면 못 걷는다")
	_cast(w, wz, "spider_climb", Vector2i(0, 0))
	assert_true(w["grid"].can_step_sized(Vector2i(0, 0), Vector2i(1, 0), 1, wz), "벽 오르기")


func test_blink_vanishes_and_returns() -> void:
	var w := make_world(["...."])
	var wz := _caster("wizard", ["blink"])
	w["grid"].place(wz, Vector2i(0, 0))
	_cast(w, wz, "blink", Vector2i(0, 0))
	Dice.force([5])
	Spellcasting.on_turn_end(w, wz)
	assert_true(wz.has_flag("ethereal"), "4~6이면 사라진다")
	var e := _foe()
	w["grid"].place(e, Vector2i(1, 0))
	assert_eq(preload("res://scripts/rules/resolver.gd").can_attack(e, wz), "다른 차원에 있다")
	Spellcasting.on_turn_start(w, wz)
	assert_false(wz.has_flag("ethereal"), "자기 턴 시작에 돌아온다")


func test_charm_suggestion_calm_end_on_damage() -> void:
	var w := make_world(["......"])
	for c in w["grid"].all_cells():
		w["grid"].add_zone(c, "z")
	var wz := _caster("wizard", ["charm_person", "suggestion"])
	var a := _foe()
	var b := _foe()
	w["grid"].place(wz, Vector2i(0, 0))
	w["grid"].place(a, Vector2i(2, 0))
	w["grid"].place(b, Vector2i(4, 0))
	Dice.force([1])
	_cast(w, wz, "charm_person", Vector2i(2, 0))
	assert_true(a.has_condition("charmed"))
	assert_true(w["dialogue_tags"].has("charmed"))
	preload("res://scripts/rules/resolver.gd").apply_damage(a, [{"amount": 1, "damage_type": "fire"}])
	assert_false(a.has_condition("charmed"), "피해를 받으면 끝난다")
	w["turns"].start_combat("z")
	Dice.force([1])
	_cast(w, wz, "suggestion", Vector2i(4, 0))
	assert_eq(b.team, "neutral", "싸움을 멈추고 떠난다")
	assert_false(b in w["turns"].order)


func test_illusion_lures_and_blocks_sight() -> void:
	var w := make_world([".........", ".........", "........."])
	var wz := _caster("wizard", ["minor_illusion", "silent_image"])
	var e := _foe()
	e.facing = Vector2i(-1, 0)
	w["grid"].place(wz, Vector2i(0, 1))
	w["grid"].place(e, Vector2i(6, 1))
	_cast(w, wz, "minor_illusion", Vector2i(5, 2))
	assert_eq(e.facing, Vector2i(-1, 1), "미끼 쪽을 돌아본다")
	_cast(w, wz, "silent_image", Vector2i(3, 1))
	assert_false(w["grid"].has_line_of_sight(Vector2i(0, 1), Vector2i(6, 1)), "환영 벽이 시야를 가린다")


func test_summons() -> void:
	var w := make_world([".......", "......."])
	var wz := _caster("wizard", ["find_familiar", "flaming_sphere"])
	var cl := _caster("cleric", ["spiritual_weapon", "animate_dead"])
	cl.team = "party"
	var e := _foe()
	w["grid"].place(wz, Vector2i(0, 0))
	w["grid"].place(cl, Vector2i(0, 1))
	w["grid"].place(e, Vector2i(4, 0))
	var r: Dictionary = _cast(w, wz, "find_familiar", Vector2i(1, 0))
	var owl: Node = own(r["summon"])
	assert_eq(owl.team, wz.team)
	assert_true(owl.has_flag("flying"))
	var corpse := _foe()
	w["grid"].place(corpse, Vector2i(2, 1))
	corpse.dead = true
	var z: Dictionary = _cast(w, cl, "animate_dead", Vector2i(2, 1))
	own(z["summon"])
	assert_eq(z["summon"].get_meta("monster")["id"], "zombie", "시체는 좀비로")
	Dice.force([15, 5])
	r = _cast(w, cl, "spiritual_weapon", Vector2i(3, 0))
	assert_true(r["attack"].get("hit", false), "시전 때 바로 공격")
	cl.reset_turn()
	Dice.force([15, 5])
	var s: Dictionary = Actions.execute(w, cl, "entity:spiritual_weapon", Vector2i(4, 0))
	assert_true(s.get("hit", false), "보너스 행동으로 다시")
	_cast(w, wz, "flaming_sphere", Vector2i(2, 0))
	var hp: int = e.hp
	Dice.force([1, 3, 3])
	wz.reset_turn()
	Actions.execute(w, wz, "entity:flaming_sphere", Vector2i(4, 0))
	assert_true(e.hp < hp, "굴려서 닿으면 불 피해")


func test_glyph_knock_arcane_lock_find_traps() -> void:
	var w := make_world(["......", "......"])
	var cl := _caster("cleric", ["glyph_of_warding", "find_traps"])
	var wz := _caster("wizard", ["knock", "arcane_lock"])
	w["grid"].place(cl, Vector2i(0, 0))
	w["grid"].place(wz, Vector2i(0, 1))
	_cast(w, cl, "glyph_of_warding", Vector2i(1, 0))
	var e := _foe()
	w["grid"].place(e, Vector2i(5, 0))
	own(load("res://scripts/rules/exploration.gd").new().setup(w, [cl, wz]))
	var hp: int = e.hp
	Dice.force([1])
	w["grid"].move_creature(e, Vector2i(1, 0))
	assert_true(e.hp < hp, "적이 밟으면 룬이 터진다")
	w["grid"].place_object(Vector2i(1, 1), {"id": "chest", "material": "wood", "hp": 5, "lock": {"dc": 15, "locked": false}})
	_cast(w, wz, "arcane_lock", Vector2i(1, 1))
	assert_true(w["grid"].object_at(Vector2i(1, 1))["lock"]["arcane"])
	_cast(w, wz, "knock", Vector2i(1, 1))
	assert_false(w["grid"].object_at(Vector2i(1, 1))["lock"]["locked"])
	w["traps"].append({"id": "pit", "cell": [5, 1], "state": "armed", "dc_find": 30, "dc_disarm": 30, "effects": []})
	_cast(w, cl, "find_traps", Vector2i(0, 0))
	assert_true(w["traps"][-1]["found"])


func test_warding_bond_protection_size_silence() -> void:
	var w := make_world(["......"])
	var cl := _caster("cleric", ["warding_bond", "protection_from_evil_and_good", "silence"])
	var wz := _caster("wizard", ["enlarge_reduce", "fireball"])
	w["grid"].place(cl, Vector2i(0, 0))
	w["grid"].place(wz, Vector2i(1, 0))
	_cast(w, cl, "warding_bond", Vector2i(1, 0))
	var chp: int = cl.hp
	preload("res://scripts/rules/resolver.gd").apply_damage(wz, [{"amount": 10, "damage_type": "fire"}])
	assert_eq(cl.hp, chp - 5, "저항으로 절반, 시전자도 같은 양")
	_cast(w, cl, "protection_from_evil_and_good", Vector2i(1, 0))
	var undead: Node = own(MF.spawn("skeleton"))
	w["grid"].place(undead, Vector2i(2, 0))
	assert_true(wz.has_condition("protected_from_types"))
	_cast(w, wz, "enlarge_reduce", Vector2i(1, 0), {"mode": "enlarge"})
	assert_eq(wz.attack_riders.size(), 1)
	assert_true(wz.weight_kg > 70)
	_cast(w, cl, "silence", Vector2i(1, 0))
	wz.reset_turn()
	assert_eq(Spellcasting.can_cast(w, wz, "fireball", Vector2i(5, 0)), "침묵 구역에서는 음성 구성 요소 주문을 쓸 수 없다")


func test_tiny_hut_prayer_gust_disguise() -> void:
	var w := make_world(["........", "........"])
	var wz := _caster("wizard", ["tiny_hut", "gust_of_wind", "disguise_self"])
	var cl := _caster("cleric", ["prayer_of_healing"])
	w["grid"].place(wz, Vector2i(0, 0))
	w["grid"].place(cl, Vector2i(0, 1))
	w["grid"].set_flag(Vector2i(0, 0), "no_camp")
	w["grid"].set_flag(Vector2i(0, 1), "no_camp")
	_cast(w, wz, "tiny_hut", Vector2i(0, 0))
	assert_true(Rest.long_rest(w, [wz, cl], {"caller": wz})["ok"], "Tiny Hut이면 캠프 불가 구역에서도")
	wz.hp = 5
	Dice.force([3, 4])
	_cast(w, cl, "prayer_of_healing", Vector2i(0, 0))
	assert_true(wz.hp >= mini(wz.hp_max, 5 + 7 + cl.ability_mod("wis")), "BG3: 주변 아군 2d8 + 수정치(생명 영역 보너스 별도)")
	var e := _foe()
	w["grid"].place(e, Vector2i(2, 0))
	Dice.force([1])
	_cast(w, wz, "gust_of_wind", Vector2i(5, 0))
	assert_eq(w["grid"].cell_of(e), Vector2i(5, 0), "3칸 밀려난다")
	assert_true(e.has_condition("off_balance"), "BG3: 균형 잃음")
	_cast(w, wz, "disguise_self", Vector2i(0, 0))
	assert_true(wz.get_meta("disguised", false))
