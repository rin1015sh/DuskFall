extends "res://tests/test_case.gd"
## 피해 수정·적용, 임시 HP, 집중, 0 HP·사망 내성(룰북 8단계 판정 순서 8~10, 7단계, SRD Damage and Healing).

const Resolver := preload("res://scripts/rules/resolver.gd")


func _dmg(t: Node, amount: int, type: String, opts: Dictionary = {}) -> Dictionary:
	return Resolver.apply_damage(t, [{"amount": amount, "damage_type": type}], opts)


func test_resistance_vulnerability_immunity() -> void:
	var c := make_creature({"hp_max": 100, "damage_resistances": ["fire"], "damage_vulnerabilities": ["cold"],
		"damage_immunities": ["poison"]})
	assert_eq(_dmg(c, 9, "fire")["total"], 4, "저항: 절반 내림")
	assert_eq(_dmg(c, 9, "cold")["total"], 18, "취약: 2배")
	assert_eq(_dmg(c, 9, "poison")["total"], 0, "면역: 0")
	assert_eq(_dmg(c, 9, "slashing")["total"], 9)


func test_resistance_and_vulnerability_cancel() -> void:
	# 룰북 4단계 중첩 규칙 4: 같은 유형에 저항과 취약이 함께 있으면 상쇄(원문의 절반 후 2배 대신).
	var c := make_creature({"hp_max": 100, "damage_resistances": ["cold"]})
	c.apply_condition("wet")
	assert_eq(_dmg(c, 9, "cold")["total"], 9)


func test_multiplier_before_resistance() -> void:
	# 내성 성공 절반(배율) → 저항 순서. 15 × 0.5 = 7(내림) → 저항 3
	var c := make_creature({"hp_max": 100, "damage_resistances": ["fire"]})
	var r := Resolver.apply_damage(c, [{"amount": 15, "damage_type": "fire", "multiplier": 0.5}])
	assert_eq(r["total"], 3)


func test_resistance_applies_once_per_type() -> void:
	var c := make_creature({"hp_max": 100, "damage_resistances": ["fire"]})
	var r := Resolver.apply_damage(c, [{"amount": 3, "damage_type": "fire"}, {"amount": 3, "damage_type": "fire"}])
	assert_eq(r["total"], 3, "한 피해의 같은 유형은 합친 뒤 한 번만 절반(6 → 3)")


func test_temp_hp_first_and_no_stack() -> void:
	var c := make_creature({"hp_max": 20})
	Resolver.grant_temp_hp(c, 5)
	Resolver.grant_temp_hp(c, 3)
	assert_eq(c.temp_hp, 5, "임시 HP는 더하지 않고 큰 쪽")
	var r := _dmg(c, 7, "slashing")
	assert_eq(r["temp_absorbed"], 5)
	assert_eq(c.hp, 18, "남은 2만 HP에서")
	assert_eq(c.temp_hp, 0)


func test_temp_hp_does_not_wake() -> void:
	var c := make_creature({"hp_max": 10, "is_player_character": true})
	_dmg(c, 10, "slashing")
	Resolver.grant_temp_hp(c, 5)
	assert_true(c.has_condition("unconscious"), "임시 HP는 회복이 아니다")


func test_concentration_dc() -> void:
	var c := make_creature({"hp_max": 200, "abilities": {"con": 10}})
	c.start_concentration("bless")
	Dice.force([9])
	var r := _dmg(c, 12, "slashing")
	assert_eq(r["concentration"]["dc"], 10, "DC = max(10, 6)")
	assert_true(c.concentration.is_empty(), "9 < 10 실패 → 집중 깨짐")
	c.start_concentration("bless")
	Dice.force([19])
	r = _dmg(c, 44, "slashing")
	assert_eq(r["concentration"]["dc"], 22, "DC = 44 / 2")
	c.start_concentration("bless")
	Dice.force([20])
	r = _dmg(c, 100, "slashing")
	assert_eq(r["concentration"]["dc"], 30, "DC 최대 30")
	assert_true(r["concentration"]["success"], "집중 유지 내성은 자연 20 자동 성공")


func test_concentration_natural_1_fails() -> void:
	var c := make_creature({"hp_max": 50, "abilities": {"con": 30}})
	c.start_concentration("bless")
	Dice.force([1])
	_dmg(c, 2, "slashing")
	assert_true(c.concentration.is_empty(), "자연 1 자동 실패(+10이어도)")


func test_concentration_check_even_if_temp_hp_absorbs() -> void:
	var c := make_creature({"hp_max": 20})
	Resolver.grant_temp_hp(c, 10)
	c.start_concentration("bless")
	Dice.force([2])
	var r := _dmg(c, 4, "slashing")
	assert_false(r["concentration"].is_empty(), "임시 HP가 막아도 피해를 받은 것")


func test_monster_dies_at_zero() -> void:
	var g := make_creature({"hp_max": 10})
	var r := _dmg(g, 12, "slashing")
	assert_true(r["died"] and g.dead, "몬스터는 0 HP에서 즉사")


func test_character_drops_unconscious() -> void:
	var pc := make_creature({"hp_max": 12, "is_player_character": true})
	pc.start_concentration("bless")
	var r := _dmg(pc, 15, "slashing")
	assert_true(r["dropped"])
	assert_false(pc.dead, "남은 피해 3 < 최대 HP 12")
	assert_true(pc.has_condition("unconscious") and pc.has_condition("prone"))
	assert_true(pc.concentration.is_empty(), "무의식 → 집중 깨짐")


func test_massive_damage() -> void:
	# 원문 예: 최대 HP 12, 현재 6, 피해 18 → 남은 12 = 최대 HP → 사망
	var pc := make_creature({"hp_max": 12, "hp": 6, "is_player_character": true})
	_dmg(pc, 18, "slashing")
	assert_true(pc.dead)


func test_damage_at_zero_hp() -> void:
	var pc := make_creature({"hp_max": 12, "is_player_character": true})
	_dmg(pc, 12, "slashing")
	_dmg(pc, 3, "slashing")
	assert_eq(pc.death_saves["failures"], 1, "0 HP에서 피해 → 실패 1")
	_dmg(pc, 3, "slashing", {"crit": true})
	assert_true(pc.dead, "치명타는 실패 2 → 누적 3 → 사망")
	var pc2 := make_creature({"hp_max": 12, "is_player_character": true})
	_dmg(pc2, 12, "slashing")
	_dmg(pc2, 12, "slashing")
	assert_true(pc2.dead, "0 HP에서 최대 HP 이상 피해 → 사망")


func test_death_saves() -> void:
	var pc := make_creature({"hp_max": 10, "is_player_character": true})
	_dmg(pc, 10, "slashing")
	Dice.force([10, 15, 12])
	for i in 3:
		Resolver.start_turn(pc)
	assert_true(pc.stable, "성공 3회 → 안정")
	assert_eq(pc.death_saves, {"successes": 0, "failures": 0})
	Dice.force([5])
	Resolver.start_turn(pc)
	assert_eq(Dice.forced_left(), 1, "안정 상태는 사망 내성을 굴리지 않는다")
	Dice.clear_forced()


func test_death_save_natural_rolls() -> void:
	var pc := make_creature({"hp_max": 10, "is_player_character": true})
	_dmg(pc, 10, "slashing")
	Dice.force([1])
	Resolver.death_save(pc)
	assert_eq(pc.death_saves["failures"], 2, "자연 1 → 실패 2")
	Dice.force([20])
	Resolver.death_save(pc)
	assert_eq(pc.hp, 1, "자연 20 → HP 1")
	assert_false(pc.has_condition("unconscious"))
	assert_eq(pc.death_saves["failures"], 0, "회복하면 초기화")
	_dmg(pc, 1, "slashing")
	Dice.force([3, 4, 9])
	for i in 3:
		Resolver.death_save(pc)
	assert_true(pc.dead, "실패 3회 → 사망")


func test_heal_wakes_but_stays_prone() -> void:
	var pc := make_creature({"hp_max": 10, "is_player_character": true})
	_dmg(pc, 10, "slashing")
	assert_eq(Resolver.heal(pc, 30), 10, "최대 HP를 넘는 회복은 버린다")
	assert_false(pc.has_condition("unconscious"))
	assert_true(pc.has_condition("prone"), "무의식이 풀려도 넘어짐은 남는다(원문)")


func test_dead_cannot_be_healed() -> void:
	var g := make_creature({"hp_max": 5})
	_dmg(g, 5, "slashing")
	assert_eq(Resolver.heal(g, 5), 0)


func test_out_of_combat_drop_is_stable() -> void:
	var pc := make_creature({"hp_max": 10, "is_player_character": true})
	_dmg(pc, 10, "slashing", {"in_combat": false})
	assert_true(pc.stable, "전투 밖 쓰러짐은 안정 상태(7단계 결정 2)")


func test_hp_zero_hook_can_prevent() -> void:
	var pc := make_creature({"hp_max": 10, "is_player_character": true})
	var endure := func(info: Dictionary) -> void:
		info["creature"].hp = 1
		info["prevented"] = true
	EventBus.on_hp_zero.connect(endure)
	_dmg(pc, 10, "slashing")
	EventBus.on_hp_zero.disconnect(endure)
	assert_eq(pc.hp, 1, "끈질긴 인내 같은 효과가 먼저")
	assert_false(pc.has_condition("unconscious"))


func test_burning_damages_at_turn_start() -> void:
	var c := make_creature({"hp_max": 20})
	c.apply_condition("burning")
	Dice.force([3])
	Resolver.start_turn(c)
	assert_eq(c.hp, 17, "연소: 턴 시작 1d4 화염")
