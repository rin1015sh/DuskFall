extends "res://tests/test_case.gd"
## 공격 판정(룰북 8단계 판정 순서 3~7, 2단계 공통 처리 규칙 1, 4단계 고지·상태이상).

const Resolver := preload("res://scripts/rules/resolver.gd")

const SWORD := {"name": "롱소드", "bonus": 5, "kind": "melee", "weapon": true,
	"damage": [{"dice": "1d8+3", "damage_type": "slashing"}]}


func _pair(target_values: Dictionary = {}) -> Array:
	var a := make_creature({"display_name": {"ko": "공격자", "en": "A"}, "hp_max": 20})
	var t := make_creature({"display_name": {"ko": "대상", "en": "T"}, "hp_max": 30, "ac_base": 15})
	t.setup(target_values)
	return [a, t]


func test_hit_and_miss_against_ac() -> void:
	var p := _pair()
	Dice.force([10, 4])  # 10 + 5 = 15 vs AC 15 → 명중, 피해 4 + 3
	var r := Resolver.attack(p[0], p[1], SWORD)
	assert_true(r["hit"], "AC와 같으면 명중")
	assert_eq(p[1].hp, 23)
	Dice.force([9])
	assert_false(Resolver.attack(p[0], p[1], SWORD)["hit"], "14 < 15 빗나감")


func test_natural_20_and_1() -> void:
	var p := _pair({"ac_base": 40})
	Dice.force([20, 2, 5])
	var r := Resolver.attack(p[0], p[1], SWORD)
	assert_true(r["hit"] and r["crit"], "자연 20은 AC와 상관없이 치명타")
	assert_eq(r["damage"]["total"], 10, "치명타: 주사위만 2배 (2 + 5) + 3")
	p[1].ac_base = 1
	Dice.force([1])
	assert_false(Resolver.attack(p[0], p[1], SWORD)["hit"], "자연 1은 자동 빗나감")


func test_advantage_and_disadvantage_cancel() -> void:
	var p := _pair()
	p[0].apply_condition("poisoned", -1)  # 불리
	p[1].apply_condition("restrained", -1)  # 받는 공격 유리
	var r := Resolver.preview_attack(p[0], p[1], SWORD)
	assert_eq(r["mode"], 0, "유리 1 + 불리 1 → 상쇄")
	p[1].apply_condition("blinded", -1)  # 받는 공격 유리 하나 더
	assert_eq(Resolver.preview_attack(p[0], p[1], SWORD)["mode"], 0, "개수와 상관없이 상쇄")
	p[0].remove_condition("poisoned")
	assert_eq(Resolver.preview_attack(p[0], p[1], SWORD)["mode"], 1)


func test_prone_target_by_distance() -> void:
	var p := _pair()
	p[1].apply_condition("prone", -1)
	assert_eq(Resolver.preview_attack(p[0], p[1], SWORD, {"distance_tiles": 1})["mode"], 1, "인접 → 유리")
	assert_eq(Resolver.preview_attack(p[0], p[1], SWORD, {"distance_tiles": 2})["mode"], 1, "BG3: 2칸(3m) 안 → 유리")
	assert_eq(Resolver.preview_attack(p[0], p[1], SWORD, {"distance_tiles": 5})["mode"], 0, "그 밖 → 보정 없음(원거리 불리 없음)")


func test_high_ground() -> void:
	var p := _pair()
	assert_eq(Resolver.preview_attack(p[0], p[1], SWORD, {"height_diff": 1})["attack_bonus"], 5, "1단계는 보정 없음")
	assert_eq(Resolver.preview_attack(p[0], p[1], SWORD, {"height_diff": 2})["attack_bonus"], 7, "2단계 이상 높으면 +2")
	assert_eq(Resolver.preview_attack(p[0], p[1], SWORD, {"height_diff": -3})["attack_bonus"], 3, "낮으면 −2")


func test_auto_crit_within_one_tile() -> void:
	var p := _pair()
	p[1].apply_condition("paralyzed", -1)
	Dice.force([15, 2, 2])
	var r := Resolver.attack(p[0], p[1], SWORD, {"distance_tiles": 1})
	assert_true(r["crit"] and r["auto_crit"], "마비: 1칸 안 명중은 치명타")
	Dice.force([15, 2])
	r = Resolver.attack(p[0], p[1], SWORD, {"distance_tiles": 3})
	assert_true(r["hit"] and not r["crit"], "멀면 일반 명중")


func test_shield_reaction_rechecks_hit() -> void:
	var p := _pair()
	var shield := func(res: Dictionary) -> void:
		if res["target"] == p[1] and res["hit"] and not res["crit"]:
			res["ac_bonus"] += 5
	EventBus.on_after_attack_roll.connect(shield)
	Dice.force([14])  # 14 + 5 = 19 vs 15 → 명중, Shield로 20 → 빗나감
	var r := Resolver.attack(p[0], p[1], SWORD)
	EventBus.on_after_attack_roll.disconnect(shield)
	assert_false(r["hit"], "명중 직후 반응으로 AC를 올리면 다시 판정")
	assert_eq(p[1].hp, 30)


func test_charmed_cannot_attack_charmer() -> void:
	var p := _pair()
	p[0].apply_condition("charmed", 10, p[1])
	var r := Resolver.attack(p[0], p[1], SWORD)
	assert_false(r["valid"])
	var other := make_creature({"hp_max": 5})
	assert_true(Resolver.preview_attack(p[0], other, SWORD)["valid"], "다른 대상은 공격 가능")


func test_incapacitated_cannot_attack() -> void:
	var p := _pair()
	p[0].apply_condition("stunned", 1)
	assert_false(Resolver.attack(p[0], p[1], SWORD)["valid"])


func test_hidden_attacker_has_advantage_and_is_revealed() -> void:
	var p := _pair()
	p[0].apply_condition("invisible", -1, "hide")
	assert_eq(Resolver.preview_attack(p[0], p[1], SWORD)["mode"], 1, "숨은 상태 → 유리")
	Dice.force([3, 4])
	Resolver.attack(p[0], p[1], SWORD)
	assert_false(p[0].has_condition("invisible"), "공격 굴림을 하면 숨기가 풀린다")


func test_spell_invisibility_not_removed_by_attack_roll() -> void:
	# 주문 Invisibility의 '공격하면 끝남'은 주문 효과에서 처리한다(5단계). 상태 자체는 숨기만 풀린다.
	var p := _pair()
	p[0].apply_condition("invisible", -1, p[0])
	Dice.force([3, 4])
	Resolver.attack(p[0], p[1], SWORD)
	assert_true(p[0].has_condition("invisible"))


func test_see_invisible_negates_invisibility() -> void:
	var p := _pair()
	p[1].apply_condition("invisible", -1)
	assert_eq(Resolver.preview_attack(p[0], p[1], SWORD)["mode"], -1, "투명한 대상 공격은 불리")
	p[0].senses.append("see_invisible")
	assert_eq(Resolver.preview_attack(p[0], p[1], SWORD)["mode"], 0, "볼 수 있으면 효과 없음")


func test_coated_weapon_adds_damage_to_weapon_attacks_only() -> void:
	var p := _pair()
	p[0].apply_condition("coated_weapon", 0, null, {"damage_type": "poison"})
	Dice.force([15, 4, 3])
	var r := Resolver.attack(p[0], p[1], SWORD)
	assert_eq(r["damage"]["by_type"], {"slashing": 7, "poison": 3})
	var spell := {"name": "주문", "bonus": 5, "weapon": false, "damage": [{"dice": "1d10", "damage_type": "fire"}]}
	Dice.force([15, 6])
	r = Resolver.attack(p[0], p[1], spell)
	assert_eq(r["damage"]["by_type"], {"fire": 6}, "주문 공격에는 붙지 않는다")


func test_attack_log_format() -> void:
	var p := _pair()
	Dice.force([12, 5])
	Resolver.attack(p[0], p[1], SWORD)
	var found := false
	for e in Dice.roll_log:
		if e["text"].contains("12 + 5 = 17 vs AC 15 → 명중"):
			found = true
	assert_true(found, "주사위 + 수정치 = 합계 vs AC 형식")
