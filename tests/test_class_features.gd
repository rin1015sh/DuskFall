extends "res://tests/test_case.gd"
## 클래스·종족·재주 기능의 동작(룰북 6단계, SRD 5.2.1 원문 수치).

const Builder := preload("res://scripts/rules/character_builder.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Features := preload("res://scripts/rules/features.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")


func _pc(class_id: String, level: int, extra: Dictionary = {}) -> Node:
	var spec := Builder.default_spec(class_id, level)
	spec.merge(extra, true)
	var r := Builder.build(spec)
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func _foe(values: Dictionary = {}) -> Node:
	var c := make_creature({"team": "enemy", "ac_base": 12, "hp_max": 60, "abilities": {"dex": 10, "con": 10}})
	c.setup(values)
	return c


func _world(rows: Array = [".......", ".......", "......."]) -> Dictionary:
	return make_world(rows)


func test_second_wind_and_tactical_shift() -> void:
	var w := _world()
	var f := _pc("fighter", 5)
	w["grid"].place(f, Vector2i(0, 0))
	f.hp = 10
	Dice.force([6])
	var r := Features.use(w, f, "second_wind")
	assert_true(r["ok"])
	assert_eq(f.hp, 21, "1d10 + 전사 레벨 5")
	assert_eq(f.turn["bonus"], 0, "보너스 행동")
	assert_eq(f.resource("second_wind"), 0)
	assert_eq(f.turn["free_move_no_oa"], 3, "전술적 이동: 속도 절반")


func test_action_surge_not_for_magic() -> void:
	var w := _world()
	var f := _pc("fighter", 2)
	w["grid"].place(f, Vector2i(0, 0))
	Combat.dash(f)
	assert_true(Features.use(w, f, "action_surge")["ok"])
	assert_eq(f.turn["action"], 1, "추가 행동")
	assert_eq(f.resource("action_surge"), 0)


func test_tactical_mind() -> void:
	var f := _pc("fighter", 2)
	Dice.force([5, 8])  # 판정 5 + 근력 3 = 8 < 12 → +1d10(8) = 16 성공
	var r := Resolver.ability_check(f, "str", 12)
	assert_true(r["success"], "전술적 판단으로 성공")
	assert_eq(f.resource("second_wind"), 0, "성공했으니 1회 소모")
	f.resources["second_wind"]["current"] = 1
	Dice.force([2, 1])  # 2 + 3 = 5 < 12, +1 = 6 → 여전히 실패
	r = Resolver.ability_check(f, "str", 12)
	assert_false(r["success"])
	assert_eq(f.resource("second_wind"), 1, "그래도 실패면 소모하지 않는다")


func test_improved_critical_19() -> void:
	var w := _world()
	var f := _pc("fighter", 3)
	var g := _foe({"ac_base": 30})
	w["grid"].place(f, Vector2i(0, 0))
	w["grid"].place(g, Vector2i(1, 0))
	Dice.force([19, 1, 1])
	var r := Combat.attack(w, f, g)
	assert_true(r["crit"], "챔피언: 19도 치명타")
	assert_eq(f.turn["free_move_no_oa"], 3, "뛰어난 운동선수: 치명타 뒤 속도 절반")


func test_sneak_attack_conditions() -> void:
	var w := _world()
	var rogue := _pc("rogue", 5)
	var ally := _pc("fighter", 1)
	var g := _foe()
	w["grid"].place(rogue, Vector2i(0, 1))
	w["grid"].place(g, Vector2i(1, 1))
	# 유리도 인접 아군도 없으면 안 붙는다
	Dice.force([15, 3])
	var r := Combat.attack(w, rogue, g)
	assert_false(r.has("sneak_attack"))
	# 인접 아군이 있으면 붙는다(3d6)
	w["grid"].place(ally, Vector2i(2, 1))
	rogue.reset_turn()
	Dice.force([15, 3, 2, 2, 2])
	r = Combat.attack(w, rogue, g)
	assert_eq(r["sneak_attack"], 3)
	assert_eq(r["damage"]["total"], 3 + 4 + 6, "1d6+4 + 3d6")
	# 턴당 1회
	rogue.turn["attacks_left"] = 1
	Dice.force([15, 3])
	assert_false(Combat.attack(w, rogue, g).has("sneak_attack"), "턴당 1회")


func test_cunning_strike_trip() -> void:
	var w := _world()
	var rogue := _pc("rogue", 5)
	var g := _foe()
	rogue.extra_modifiers.append({"effect": {"type": "advantage", "roll": "attack", "side": "self", "value": "advantage"}, "source": "test"})
	w["grid"].place(rogue, Vector2i(0, 1))
	w["grid"].place(g, Vector2i(1, 1))
	rogue.turn["cunning_strike"] = "trip"
	Dice.force([15, 15, 3, 2, 2, 5])  # 유리 [15,15], 1d6+4, 2d6(3d6에서 1개), 민첩 내성 5
	var r := Combat.attack(w, rogue, g)
	assert_eq(r["sneak_attack"], 2, "주사위 하나를 쓴다")
	assert_true(g.has_condition("prone"), "넘어뜨리기")


func test_uncanny_dodge_halves() -> void:
	var w := _world()
	var rogue := _pc("rogue", 5)
	var g := _foe({"abilities": {"str": 16}, "weapon_proficiencies": ["martial"],
		"weapon_sets": {"melee": {"main": "greatsword", "off": ""}, "ranged": {"main": ""}}})
	w["grid"].place(rogue, Vector2i(0, 1))
	w["grid"].place(g, Vector2i(1, 1))
	var before: int = rogue.hp
	Dice.force([18, 6, 6])
	Combat.attack(w, g, rogue)
	assert_eq(before - rogue.hp, 7, "(6 + 6 + 3) / 2 내림")
	assert_false(rogue.can_react(), "반응 소모")


func test_savage_attacker_and_gwf() -> void:
	var w := _world()
	var f := _pc("fighter", 1, {"background": "soldier", "fighting_style": "great_weapon_fighting",
		"weapons": {"melee": {"main": "greatsword", "off": ""}, "ranged": {"main": "javelin"}}})
	var g := _foe()
	w["grid"].place(f, Vector2i(0, 0))
	w["grid"].place(g, Vector2i(1, 0))
	Dice.force([15, 1, 2, 5, 6])  # 첫 굴림 1·2 → 3·3(대형 무기 전투) = 6, 둘째 5 + 6 = 11 → 큰 쪽
	var r := Combat.attack(w, f, g)
	assert_eq(r["damage"]["total"], 11 + 3, "야만적 공격: 두 번 굴려 큰 쪽 + 근력 3")


func test_archery_bonus() -> void:
	var f := _pc("fighter", 1, {"fighting_style": "archery"})
	assert_eq(Combat.build_weapon_attack(f, "longbow")["bonus"], 5, "민첩 1 + 숙련 2 + 궁술 2")
	assert_eq(Combat.build_weapon_attack(f, "longsword")["bonus"], 5, "근접 무기에는 궁술 없음(근력 3 + 숙련 2)")


func test_halfling_luck() -> void:
	var rogue := _pc("rogue", 1)
	Dice.force([1, 17])
	var r := Resolver.ability_check(rogue, "dex", 10)
	assert_eq(r["natural"], 17, "자연 1을 다시 굴린다")


func test_dwarf_poison_save_advantage() -> void:
	var cleric := _pc("cleric", 1)
	Dice.force([3, 18])
	var r := Resolver.save_effect([cleric], {"ability": "con", "dc": 12}, [{"type": "apply_condition", "id": "poisoned"}])
	assert_true(r[0]["save"]["success"], "중독 내성 유리 [3, 18]")


func test_divine_spark_and_preserve_life() -> void:
	var w := _world()
	var cleric := _pc("cleric", 3)
	var f := _pc("fighter", 3)
	var r2 := _pc("rogue", 3)
	w["grid"].place(cleric, Vector2i(0, 0))
	w["grid"].place(f, Vector2i(2, 0))
	w["grid"].place(r2, Vector2i(3, 0))
	f.hp = 4
	r2.hp = 3
	assert_true(Features.use(w, cleric, "preserve_life")["ok"])
	assert_eq(r2.hp, r2.hp_max / 2, "HP 비율이 낮은 로그부터 최대 HP 절반까지(3 → 12)")
	assert_eq(f.hp, 4 + 15 - 9, "남은 6이 전사에게(레벨 3 × 5 = 15)")
	assert_eq(cleric.resource("channel_divinity"), 1)
	cleric.reset_turn()
	f.hp = 5
	Dice.force([4])
	Features.use(w, cleric, "divine_spark", f, {"mode": "heal"})
	assert_eq(f.hp, 5 + 4 + 3, "1d8 + 지혜 3")


func test_turn_undead() -> void:
	var w := _world()
	var cleric := _pc("cleric", 5)
	var zombie := _foe({"creature_type": "undead", "abilities": {"wis": 6}})
	var goblin := _foe()
	w["grid"].place(cleric, Vector2i(0, 0))
	w["grid"].place(zombie, Vector2i(3, 0))
	w["grid"].place(goblin, Vector2i(3, 1))
	Dice.force([2, 5, 5, 5, 5])  # 내성 실패, 언데드 소각 4d8(지혜 19 → +4)
	Features.use(w, cleric, "turn_undead")
	assert_true(zombie.has_condition("frightened") and zombie.has_condition("incapacitated"))
	assert_eq(zombie.hp, 60 - 20, "언데드 소각")
	assert_false(goblin.has_condition("frightened"), "언데드만")


func test_disciple_of_life() -> void:
	var w := _world()
	var cleric := _pc("cleric", 3)
	var f := _pc("fighter", 3)
	w["grid"].place(cleric, Vector2i(0, 0))
	w["grid"].place(f, Vector2i(1, 0))
	f.hp = 1
	Dice.force([2, 2])
	Spellcasting.cast(w, cleric, "healing_word", Vector2i(1, 0))
	assert_eq(f.hp, 1 + 4 + 3 + 3, "2d4 + 지혜 3 + (2 + 슬롯 1)")


func test_potent_cantrip_on_miss() -> void:
	var w := _world()
	var wiz := _pc("wizard", 3)
	var g := _foe({"ac_base": 30})
	w["grid"].place(wiz, Vector2i(0, 0))
	w["grid"].place(g, Vector2i(4, 0))
	Dice.force([5, 8])
	Spellcasting.cast(w, wiz, "fire_bolt", Vector2i(4, 0))
	assert_eq(g.hp, 56, "빗나가도 1d10 절반(8 → 4)")


func test_arcane_recovery() -> void:
	var wiz := _pc("wizard", 5)
	wiz.resources["spell_slot_1"]["current"] = 0
	wiz.resources["spell_slot_3"]["current"] = 0
	var r := Features.run("arcane_recovery", {"self": wiz})
	assert_eq(wiz.resources["spell_slot_3"]["current"], 1, "레벨 5 → 3레벨분: 3레벨 슬롯 1")
	assert_eq(wiz.resources["spell_slot_1"]["current"], 0)


func test_orc_traits() -> void:
	var w := _world()
	var orc := _pc("fighter", 1, {"species": "orc", "origin_feat": "", "species_skill": ""})
	w["grid"].place(orc, Vector2i(0, 0))
	assert_true(Features.use(w, orc, "adrenaline_rush")["ok"])
	assert_eq(orc.temp_hp, 2)
	assert_eq(orc.turn["movement"], 12, "질주")
	Resolver.apply_damage(orc, [{"amount": orc.hp + orc.temp_hp, "damage_type": "slashing"}])
	assert_eq(orc.hp, 1, "끈질긴 인내")
	assert_eq(orc.resource("relentless_endurance"), 0)


func test_cunning_action_and_steady_aim() -> void:
	var w := _world()
	var rogue := _pc("rogue", 3)
	w["grid"].place(rogue, Vector2i(0, 0))
	assert_true(Combat.cunning_action(w, rogue, "dash")["ok"])
	assert_eq(rogue.turn["bonus"], 1, "질주를 보너스 행동으로(빠른 손: 보너스 행동 2개 중 1개)")
	assert_true(Combat.cunning_action(w, rogue, "disengage")["ok"], "빠른 손(BG3식): 보너스 행동 하나 더")
	assert_false(Combat.cunning_action(w, rogue, "hide")["ok"], "세 번째는 없다")
	rogue.reset_turn()
	assert_true(Features.use(w, rogue, "steady_aim")["ok"])
	assert_eq(rogue.turn["movement"], 0, "속도 0")
	var g := _foe()
	w["grid"].place(g, Vector2i(1, 0))
	assert_eq(Combat.preview_attack(w, rogue, g)["mode"], 1, "다음 공격 유리")
