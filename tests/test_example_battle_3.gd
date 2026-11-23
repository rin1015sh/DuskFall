extends "res://tests/test_case.gd"
## 룰북 9단계 예시 전투 3(5레벨, 절벽 길)의 핵심: 고지 투창 70%, 오우거 밀치기 불가, Topple, Shield 반응.
## 오우거 수치는 SRD 5.2.1 Ogre(큼, AC 11, HP 68, 투창 +6). 오우거 무게는 SRD에 없어 300kg로 둔다(테스트용).

const Actions := preload("res://scripts/rules/actions.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Physics := preload("res://scripts/rules/physics.gd")

const OGRE_JAVELIN := {"name": "투창", "bonus": 6, "kind": "ranged", "weapon": true,
	"damage": [{"dice": "2d6+4", "damage_type": "piercing"}], "range_tiles": [6, 24]}


func _setup() -> Dictionary:
	var rows: Array = []
	for i in 6:
		rows.append("..............")
	var w := make_world(rows)
	for x in 3:
		for y in 2:
			w["grid"].set_height(Vector2i(x, y), 3)  # 오우거 A의 바위(3단계)
	return w


func _ogre(values: Dictionary = {}) -> Node:
	var o := make_creature({"team": "enemy", "display_name": {"ko": "오우거", "en": "Ogre"}, "ac_base": 11,
		"hp_max": 68, "weight_kg": 300.0, "abilities": {"str": 19, "dex": 8, "con": 16},
		"weapon_proficiencies": ["simple", "martial"], "weapon_sets": {"melee": {"main": "greatclub", "off": ""},
		"ranged": {"main": "javelin"}}})
	o.setup(values)
	return o


func _wizard() -> Node:
	return make_creature({"team": "party", "is_player_character": true, "display_name": {"ko": "위저드", "en": "Wizard"},
		"ac_base": 15, "hp_max": 27, "abilities": {"int": 18, "dex": 14}, "proficiency_bonus": 3,
		"known_reactions": ["opportunity_attack", "shield"],
		"resources": {"spell_slot_1": {"current": 4, "max": 4}, "spell_slot_2": {"current": 3, "max": 3}}})


func _fighter() -> Node:
	return make_creature({"team": "party", "is_player_character": true, "display_name": {"ko": "전사", "en": "Fighter"},
		"ac_base": 19, "hp_max": 44, "abilities": {"str": 18, "dex": 12}, "proficiency_bonus": 3, "attacks_per_action": 2,
		"weapon_proficiencies": ["simple", "martial"],
		"weapon_sets": {"melee": {"main": "maul", "off": ""}, "ranged": {"main": "shortbow"}}})


## 1. 3단계 높은 바위 위 오우거 A의 투창: +6 + 고지 2 = +8, 위저드 AC 15에 70%. 사거리 +3칸.
func test_ogre_javelin_from_high_rock() -> void:
	var w := _setup()
	var a := _ogre()
	var wiz := _wizard()
	w["grid"].place(a, Vector2i(0, 0), 2)
	w["grid"].place(wiz, Vector2i(10, 3))
	var ctx: Dictionary = Combat.attack_context(w, a, wiz, OGRE_JAVELIN)
	assert_eq(w["grid"].effective_range(a, Vector2i(10, 3), 6), 9, "낮은 대상이라 사거리 3칸 연장")
	var p := preload("res://scripts/rules/resolver.gd").preview_attack(a, wiz, OGRE_JAVELIN, ctx)
	assert_eq(p["attack_bonus"], 8)
	assert_near(p["hit_chance"], 0.7, 0.0001, "(21 − 7) / 20")


## 4. 전사가 오우거 B를 밀치려 하지만 무게 한계(근력 18 × 12 = 216kg)를 넘어 막힌다.
func test_fighter_cannot_shove_ogre() -> void:
	var w := _setup()
	var f := _fighter()
	var b := _ogre()
	w["grid"].place(f, Vector2i(6, 3))
	w["grid"].place(b, Vector2i(7, 3), 2)
	var p := Physics.preview_shove(w["grid"], f, b)
	assert_false(p["valid"], "미리보기가 막는다(빨간색)")
	assert_true(p["reason"].contains("216"))
	assert_false(Combat.shove(w, f, b)["ok"])
	assert_eq(f.turn["bonus"], 1, "비용을 쓰지 않는다")


## 4. 대신 몰 무기 액션 '짓눌러 넘기기'(BG3식): 1d4 + 근력, 근력 내성 DC 15(8 + 숙련 3 + 근력 4)로 2턴 넘어뜨린다.
## 5. 넘어진 오우거 옆의 로그는 유리.
func test_topple_with_maul_then_advantage() -> void:
	var w := _setup()
	var f := _fighter()
	var b := _ogre()
	var rogue := make_creature({"team": "party", "abilities": {"dex": 16}, "weapon_proficiencies": ["simple", "martial"],
		"weapon_sets": {"melee": {"main": "shortsword", "off": ""}, "ranged": {"main": "shortbow"}}})
	w["grid"].place(f, Vector2i(6, 3))
	w["grid"].place(b, Vector2i(7, 3), 2)
	w["grid"].place(rogue, Vector2i(9, 3))
	f.reset_turn()
	Dice.force([14, 3, 2])  # 명중, 1d4 = 3, 근력 내성 2 → 실패
	var r1: Dictionary = Actions.execute(w, f, "wa_crushing_blow", Vector2i(7, 3))
	assert_true(r1["hit"])
	assert_eq(int(r1["wa_save"]["dc"]), 15)
	assert_true(b.has_condition("prone"), "넘어짐")
	assert_eq(b.hp, 68 - 7, "피해 3 + 4")
	assert_eq(int(f.turn["attacks_left"]), 1, "추가 공격이 남는다(무기 액션 = 공격 행동의 공격 하나)")
	assert_eq(Combat.preview_attack(w, rogue, b)["mode"], 1, "넘어진 대상, 인접 공격 유리(2×2 둘레에서 인접)")


## 6. 오우거 A 재투척: 위저드가 '매번 묻기'로 Shield를 써서 AC 20 → 빗나감.
func test_shield_reaction_ask_mode() -> void:
	var w := _setup()
	var a := _ogre()
	var wiz := _wizard()
	w["grid"].place(a, Vector2i(0, 0), 2)
	w["grid"].place(wiz, Vector2i(10, 3))
	var asked: Array = []
	w["reactions"].ask_callback = func(c: Node, id: String, info: Dictionary) -> bool:
		asked.append(id)
		return info["would_miss"]
	assert_eq(wiz.reaction_setting("shield"), "ask", "반응 주문 기본은 매번 묻기")
	Dice.force([10])  # 10 + 8 = 18 ≥ 15 명중 → Shield로 20 → 빗나감
	var ctx: Dictionary = Combat.attack_context(w, a, wiz, OGRE_JAVELIN)
	var r := preload("res://scripts/rules/resolver.gd").attack(a, wiz, OGRE_JAVELIN, ctx)
	assert_eq(asked, ["shield"])
	assert_false(r["hit"], "AC 20이 되어 빗나감")
	assert_eq(wiz.hp, 27)
	assert_eq(wiz.resource("spell_slot_1"), 3, "1레벨 슬롯 소모")
	assert_false(wiz.can_react(), "반응 소모")
	assert_eq(wiz.ac(), 20, "다음 자기 턴 시작까지 AC +5")
	w["turns"].begin_turn(wiz)
	assert_eq(wiz.ac(), 15, "자기 턴 시작에 끝")


func test_shield_auto_only_when_it_changes_outcome() -> void:
	var w := _setup()
	var a := _ogre()
	var wiz := _wizard()
	wiz.reaction_settings["shield"] = "auto"
	w["grid"].place(a, Vector2i(0, 0), 2)
	w["grid"].place(wiz, Vector2i(10, 3))
	Dice.force([19, 6, 6])  # 19 + 8 = 27: Shield로도 못 막음 → 쓰지 않는다
	var ctx: Dictionary = Combat.attack_context(w, a, wiz, OGRE_JAVELIN)
	preload("res://scripts/rules/resolver.gd").attack(a, wiz, OGRE_JAVELIN, ctx)
	assert_eq(wiz.resource("spell_slot_1"), 4, "결과가 바뀌지 않으면 자동으로 쓰지 않는다")
	assert_true(wiz.can_react())
