extends "res://tests/test_case.gd"
## 룰북 9단계 예시 전투 1(1레벨, 어두운 동굴)의 수치를 재현한다.
## 고블린 전사 수치는 SRD 5.2.1 Goblin Warrior(AC 15, HP 10, 단궁 +4, 1d6+2, 유리면 +1d4).

const Resolver := preload("res://scripts/rules/resolver.gd")

const SHORTBOW := {"name": "단궁", "bonus": 4, "kind": "ranged", "weapon": true,
	"damage": [{"dice": "1d6+2", "damage_type": "piercing"}],
	"extra_if_advantage": [{"dice": "1d4", "damage_type": "piercing"}]}


func _goblin() -> Node:
	return make_creature({"display_name": {"ko": "고블린 전사", "en": "Goblin Warrior"},
		"abilities": {"str": 8, "dex": 15, "con": 10, "int": 10, "wis": 8, "cha": 8},
		"ac_base": 15, "hp_max": 10, "senses": ["darkvision"]})


func _wizard() -> Node:
	return make_creature({"display_name": {"ko": "위저드", "en": "Wizard"}, "is_player_character": true,
		"abilities": {"int": 16, "dex": 14}, "ac_base": 12, "hp_max": 7})


func _cleric() -> Node:
	return make_creature({"display_name": {"ko": "클레릭", "en": "Cleric"}, "is_player_character": true,
		"abilities": {"wis": 16}, "ac_base": 18, "hp_max": 11})


## 3. 바위 턱(2단계 높음)의 숨은 고블린이 위저드에게 단궁: +6, 유리, 명중 약 94%, 평균 8.
func test_round1_hit_chance_about_94_percent() -> void:
	var gob := _goblin()
	var wiz := _wizard()
	gob.apply_condition("invisible", -1, "hide")
	var ctx := {"distance_tiles": 6, "height_diff": 2}
	var p := Resolver.preview_attack(gob, wiz, SHORTBOW, ctx)
	assert_eq(p["attack_bonus"], 6, "단궁 +4, 고지 +2")
	assert_eq(p["mode"], 1, "숨은 상태 → 유리")
	assert_near(p["hit_chance"], 0.9375, 0.0001, "0.75 → 1 − 0.25²")
	assert_near(p["damage"]["avg"], 8.0, 0.0001, "1d6+2 평균 5.5 + 유리 추가 1d4 평균 2.5")
	assert_true(p["damage"]["avg"] >= wiz.hp_max, "평균 피해로 위저드(HP 7)가 쓰러진다")


func test_round1_wizard_drops_then_healing_word() -> void:
	var gob := _goblin()
	var wiz := _wizard()
	var cleric := _cleric()
	gob.apply_condition("invisible", -1, "hide")
	Dice.force([15, 8, 4, 2])  # 유리 d20 [15, 8] → 15 + 6 = 21, 피해 1d6 = 4, 유리 추가 1d4 = 2
	var r := Resolver.attack(gob, wiz, SHORTBOW, {"distance_tiles": 6, "height_diff": 2})
	assert_true(r["hit"])
	assert_eq(r["damage"]["total"], 8, "4 + 2 + 2")
	assert_eq(wiz.hp, 0)
	assert_true(wiz.has_condition("unconscious"), "캐릭터는 쓰러진다(즉사 아님: 남은 1 < 최대 HP 7)")
	assert_false(wiz.dead)
	assert_false(gob.has_condition("invisible"), "공격했으니 숨기가 풀린다")
	# 4. 클레릭 Healing Word: 2d4 + 지혜 수정치(+3)
	Dice.force([2, 3])
	var healed := Resolver.heal(wiz, Dice.roll("2d4", "Healing Word")["total"] + cleric.ability_mod("wis"), cleric)
	assert_eq(healed, 7, "2 + 3 + 3 = 8 → 최대 HP 7까지")
	assert_false(wiz.has_condition("unconscious"), "위저드가 일어난다")


## 7. 젖은 고블린에게 Ray of Frost(1d8 냉기): 젖음으로 냉기 2배 → 쓰러진다.
func test_ray_of_frost_on_wet_goblin() -> void:
	var gob := _goblin()
	var wiz := _wizard()
	gob.apply_condition("wet")
	var ray := {"name": "Ray of Frost", "bonus": wiz.proficiency_bonus + wiz.ability_mod("int"),
		"kind": "ranged", "weapon": false, "damage": [{"dice": "1d8", "damage_type": "cold"}]}
	var p := Resolver.preview_attack(wiz, gob, ray, {"distance_tiles": 4})
	assert_near(p["hit_chance"], 0.55, 0.0001, "+5 vs AC 15")
	assert_eq(p["damage"]["max"], 16.0, "미리보기도 취약 반영")
	Dice.force([12, 5])
	var r := Resolver.attack(wiz, gob, ray, {"distance_tiles": 4})
	assert_eq(r["damage"]["total"], 10, "5 × 2")
	assert_true(gob.dead, "몬스터는 0 HP에서 즉사")
