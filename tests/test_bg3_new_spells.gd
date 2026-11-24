extends "res://tests/test_case.gd"
## BG3에 있고 우리에게 없던 주문 38개(2026-11-24, BG3 수치 — SRD 밖 주문은 자체 이름): 핵심 동작.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const SimpleAI := preload("res://scripts/ai/simple_ai.gd")


func _pc(class_id: String, level: int) -> Node:
	var r := Builder.build(Builder.default_spec(class_id, level))
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func _foe(hp: int = 60, values: Dictionary = {}) -> Node:
	var v := {"team": "enemy", "hp_max": hp, "ac_base": 10, "abilities": {"str": 10, "dex": 10, "con": 10, "wis": 10, "int": 10}}
	v.merge(values, true)
	return make_creature(v)


func _world() -> Dictionary:
	var rows: Array = []
	for i in 14:
		rows.append("....................")
	return make_world(rows)


func _cast(w: Dictionary, c: Node, sid: String, aim: Vector2i, opts: Dictionary = {}) -> Dictionary:
	if not c.spells.has(sid):
		c.spells.append(sid)
	c.reset_turn()
	return Spellcasting.cast(w, c, sid, aim, opts)


func test_all_new_spells_present_with_original_names() -> void:
	var srd := ["shillelagh", "enthrall", "flame_blade", "heat_metal", "moonbeam", "phantasmal_force", "call_lightning", "plant_growth"]
	var orig := ["parry_veil", "winning_smile", "bramble_lash", "death_knell", "thunder_edge", "ember_edge", "storm_tether", "rime_mantle",
		"umbral_grasp", "binding_challenge", "thorn_volley", "thunderclap_strike", "arc_tether", "wrath_strike", "radiant_brand",
		"whirling_blades", "maddening_crown", "gloom_blade", "glare_strike", "steel_barrage", "zealots_mantle", "elemental_edge",
		"deathly_repose", "void_hunger", "storm_arrow", "strangling_vine", "mind_jolt_strike", "exile_strike", "sundering_wave", "twin_gate"]
	assert_eq(srd.size() + orig.size(), 38)
	for sid: String in srd:
		assert_eq(str(RulesDB.get_entry("spell", sid).get("source", "")), "SRD 5.2.1", sid)
	for sid: String in orig:
		var sp := RulesDB.get_entry("spell", sid)
		assert_eq(str(sp.get("source", "")), "original", sid)
		assert_eq(str(sp.get("game_status", "")), "included", sid)


func test_parry_veil_and_death_knell() -> void:
	var w := _world()
	var wz := _pc("wizard", 1)
	var e := _foe(20)
	w["grid"].place(wz, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(5, 0))
	_cast(w, wz, "parry_veil", Vector2i(0, 0))
	var hp: int = wz.hp
	Resolver.apply_damage(wz, [{"amount": 4, "damage_type": "slashing"}])
	assert_eq(wz.hp, hp - 2, "참격 저항")
	Dice.force([1, 8])
	_cast(w, wz, "death_knell", Vector2i(5, 0))
	assert_eq(e.hp, 12, "HP 가득 — 1d8")
	Dice.force([1, 12])
	_cast(w, wz, "death_knell", Vector2i(5, 0))
	assert_eq(e.hp, 0, "다친 대상 — 1d12")


func test_thunder_edge_move_damage_once() -> void:
	var w := _world()
	var wz := _pc("wizard", 1)
	wz.weapon_sets[wz.active_set] = {"main": "dagger"}
	var e := _foe()
	w["grid"].place(wz, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(1, 0))
	Dice.force([19, 2])
	assert_true(_cast(w, wz, "thunder_edge", Vector2i(1, 0)).get("hit", false))
	assert_true(e.has_condition("thunder_echo"))
	var hp: int = e.hp
	e.reset_turn()
	Dice.force([5])
	e.turn["disengaged"] = true
	Combat.move(w, e, Vector2i(3, 0))
	Combat.move(w, e, Vector2i(4, 0))
	assert_eq(e.hp, hp - 5, "움직이면 1d8 천둥 한 번")
	assert_false(e.has_condition("thunder_echo"), "한 번이면 끝")
	assert_eq(int(wz.turn["attacks_left"]), 0, "공격 행동이 아니다(추가 공격 없음)")


func test_storm_tether_and_bramble_lash_pull() -> void:
	var w := _world()
	var wz := _pc("wizard", 1)
	var e := _foe()
	w["grid"].place(wz, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(3, 0))
	Dice.force([1, 6])
	_cast(w, wz, "storm_tether", Vector2i(3, 0))
	assert_eq(w["grid"].cell_of(e), Vector2i(1, 0), "옆 칸까지 끌려온다")
	assert_eq(e.hp, 54, "옆이면 1d8 번개")
	var dr := _pc("druid", 1)
	var e2 := _foe()
	w["grid"].place(dr, Vector2i(0, 5))
	w["grid"].place(e2, Vector2i(6, 5))
	Dice.force([19, 3])
	_cast(w, dr, "bramble_lash", Vector2i(6, 5))
	assert_eq(w["grid"].cell_of(e2), Vector2i(4, 5), "2칸 끌어옴")


func test_rime_mantle_retaliates_while_temp_hp() -> void:
	var w := _world()
	var wl := _pc("warlock", 3)
	var e := _foe()
	w["grid"].place(wl, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(1, 0))
	_cast(w, wl, "rime_mantle", Vector2i(0, 0), {"slot": 2})
	assert_eq(wl.temp_hp, 10, "임시 HP 5 × 2")
	wl.reaction_settings["hellish_rebuke"] = "off"
	e.reset_turn()
	Dice.force([19])
	Combat.attack(w, e, wl, {"weapon": "unarmed"})
	assert_eq(e.hp, 50, "근접 공격자에게 냉기 10")
	wl.temp_hp = 0
	e.reset_turn()
	Dice.force([19])
	Combat.attack(w, e, wl, {"weapon": "unarmed"})
	assert_eq(e.hp, 50, "임시 HP가 없으면 끝")
	assert_false(wl.has_condition("rime_mantle"))


func test_thunderclap_and_radiant_brand_smites() -> void:
	var w := _world()
	var p := _pc("paladin", 5)
	var e := _foe(80, {"abilities": {"str": 1}})
	w["grid"].place(p, Vector2i(2, 2))
	w["grid"].place(e, Vector2i(3, 2))
	Dice.force([18])
	var r := _cast(w, p, "thunderclap_strike", Vector2i(3, 2), {"weapon": "longsword"})
	assert_true(r.get("hit", false))
	assert_eq(w["grid"].cell_of(e), Vector2i(5, 2), "2칸 밀림")
	assert_true(e.has_condition("prone"), "넘어짐")
	var e2 := _foe(80)
	w["grid"].place(e2, Vector2i(1, 2))
	Dice.force([18])
	_cast(w, p, "radiant_brand", Vector2i(1, 2), {"weapon": "longsword", "slot": 2})
	assert_true(e2.has_condition("branded"))
	e2.apply_condition("invisible", 5)
	assert_false(e2.active_conditions().any(func(a: Dictionary) -> bool: return a["id"] == "invisible"), "낙인 — 투명 억제")


func test_exile_strike_banishes_only_low_hp() -> void:
	var w := _world()
	var p := _pc("paladin", 9)
	var big := _foe(200)
	var small := _foe(70)
	w["grid"].place(p, Vector2i(2, 2))
	w["grid"].place(big, Vector2i(3, 2))
	w["grid"].place(small, Vector2i(1, 2))
	Dice.force([18])
	_cast(w, p, "exile_strike", Vector2i(3, 2), {"weapon": "longsword", "free": true})  # 5레벨 주문(상한 12에서는 두루마리·물품)
	assert_false(big.has_condition("banished"), "HP가 많으면 추방 안 됨")
	Dice.force([18])
	_cast(w, p, "exile_strike", Vector2i(1, 2), {"weapon": "longsword", "free": true})
	assert_true(small.has_condition("banished") or small.dead, "맞은 뒤 50 이하 — 추방")


func test_arc_tether_and_call_lightning_recast_without_slot() -> void:
	var w := _world()
	var wz := _pc("wizard", 5)
	var e := _foe(80)
	w["grid"].place(wz, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(5, 0))
	Dice.force([19, 6])
	_cast(w, wz, "arc_tether", Vector2i(5, 0))
	var slots: int = wz.resource("spell_slot_1")
	Dice.force([7])
	var r := _cast(w, wz, "arc_tether", Vector2i(5, 0))
	assert_true(r.get("recast", false), "다시 쓰기")
	assert_eq(e.hp, 80 - 6 - 7)
	assert_eq(wz.resource("spell_slot_1"), slots, "슬롯을 쓰지 않는다")
	var dr := _pc("druid", 5)
	var a := _foe(80)
	w["grid"].place(dr, Vector2i(0, 8))
	w["grid"].place(a, Vector2i(6, 8))
	_cast(w, dr, "call_lightning", Vector2i(6, 8))
	var s3: int = dr.resource("spell_slot_3")
	var hp: int = a.hp
	_cast(w, dr, "call_lightning", Vector2i(6, 8))
	assert_true(a.hp < hp, "다시 내리친다")
	assert_eq(dr.resource("spell_slot_3"), s3, "슬롯 없이")


func test_whirling_blades_damage_without_save() -> void:
	var w := _world()
	var wz := _pc("wizard", 3)
	var e := _foe(80, {"abilities": {"dex": 30}})
	w["grid"].place(wz, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(8, 0))
	var r := _cast(w, wz, "whirling_blades", Vector2i(6, 0))
	assert_true(r.get("ok", false), str(r))
	e.reset_turn()
	Combat.move(w, e, Vector2i(6, 0))
	assert_true(e.hp < 80, "들어오면 4d4 참격(내성 없음)")


func test_maddened_attacks_nearest_even_ally() -> void:
	var w := _world()
	var wz := _pc("wizard", 3)
	var e := _foe(60)
	var ally := _foe(60)
	w["grid"].place(wz, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(6, 0))
	w["grid"].place(ally, Vector2i(7, 0))
	Dice.force([1])
	_cast(w, wz, "maddening_crown", Vector2i(6, 0))
	assert_true(e.has_condition("maddened"))
	e.reset_turn()
	Dice.force([19, 2])
	SimpleAI.take_turn(w, e)
	assert_true(ally.hp < 60, "가장 가까운 동료를 공격")
	var beast := _foe(60, {"creature_type": "beast"})
	w["grid"].place(beast, Vector2i(6, 6))
	Dice.force([1])
	_cast(w, wz, "maddening_crown", Vector2i(6, 6))
	assert_false(beast.has_condition("maddened"), "인간형만")


func test_conjured_blades_and_shillelagh() -> void:
	var w := _world()
	var dr := _pc("druid", 3)
	w["grid"].place(dr, Vector2i(0, 0))
	var before: String = dr.weapon("main")
	_cast(w, dr, "flame_blade", Vector2i(0, 0))
	assert_eq(dr.weapon("main"), "conjured_flame_blade")
	var atk := Combat.build_weapon_attack(dr, "conjured_flame_blade")
	assert_true(str(atk["damage"][0]["dice"]).begins_with("3d6"), "3d6 화염")
	assert_eq(str(atk["damage"][0]["damage_type"]), "fire")
	dr.break_concentration("시험") if not dr.concentration.is_empty() else null
	Spellcasting.end_instance(Spellcasting.instances.keys().filter(func(k: int) -> bool: return Spellcasting.instances[k]["spell"] == "flame_blade")[0])
	assert_eq(dr.weapon("main"), before, "끝나면 원래 무기")
	dr.weapon_sets[dr.active_set] = {"main": "quarterstaff"}
	assert_true(_cast(w, dr, "shillelagh", Vector2i(0, 0)).get("ok", false))
	var q := Combat.build_weapon_attack(dr, "quarterstaff")
	assert_eq(str(q["ability"]), "wis", "시전 능력")
	assert_true(str(q["damage"][0]["dice"]).begins_with("1d8") and q["magical"], "1d8, 마법")


func test_heat_metal_recast_bonus_action() -> void:
	var w := _world()
	var bd := _pc("bard", 3)
	var e := _foe(80, {"abilities": {"con": 1}})
	w["grid"].place(bd, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(5, 0))
	_cast(w, bd, "heat_metal", Vector2i(5, 0))
	assert_true(e.has_condition("disarmed"), "건강 내성 실패 — 무기 놓침")
	var hp: int = e.hp
	bd.reset_turn()
	var r := Spellcasting.cast(w, bd, "heat_metal", Vector2i(5, 0))
	assert_true(r.get("recast", false))
	assert_eq(int(bd.turn["bonus"]), 0, "보너스 행동")
	assert_true(e.hp < hp)


func test_area_spells_targets() -> void:
	var w := _world()
	var p := _pc("paladin", 9)
	var ally := _pc("fighter", 3)
	var e := _foe(80, {"abilities": {"con": 1}})
	w["grid"].place(p, Vector2i(5, 5))
	w["grid"].place(ally, Vector2i(6, 5))
	w["grid"].place(e, Vector2i(5, 7))
	var hp: int = ally.hp
	_cast(w, p, "sundering_wave", Vector2i(5, 5), {"free": true})
	assert_eq(ally.hp, hp, "적만")
	assert_true(e.hp < 80 and e.has_condition("prone"))
	p.reset_turn()
	_cast(w, p, "zealots_mantle", Vector2i(5, 5))
	assert_true(ally.has_condition("zealous") and not e.has_condition("zealous"), "주변 아군만 +1d4 광휘")


func test_plant_growth_quarter_speed_and_vine_pull() -> void:
	var w := _world()
	var dr := _pc("druid", 7)
	w["grid"].place(dr, Vector2i(0, 0))
	_cast(w, dr, "plant_growth", Vector2i(10, 6))
	assert_eq(w["grid"].step_cost(Vector2i(10, 5), Vector2i(10, 6)), 4, "1칸 이동 4")
	var e := _foe(60, {"abilities": {"dex": 1}})
	w["grid"].place(e, Vector2i(6, 3))
	_cast(w, dr, "strangling_vine", Vector2i(2, 3))
	assert_eq(w["grid"].cell_of(e), Vector2i(3, 3), "덩굴 쪽으로 끌려온다(옆 칸까지)")


func test_twin_gate_moves_creatures() -> void:
	var w := _world()
	var wz := _pc("wizard", 11)
	w["grid"].place(wz, Vector2i(0, 0))
	_cast(w, wz, "twin_gate", Vector2i(8, 0), {"second_cell": Vector2i(2, 8)})
	var e := _foe()
	w["grid"].place(e, Vector2i(10, 0))
	e.reset_turn()
	Combat.move(w, e, Vector2i(8, 0))
	assert_eq(w["grid"].cell_of(e), Vector2i(2, 8), "관문으로 옮겨 간다(적도)")
