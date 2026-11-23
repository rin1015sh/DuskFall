extends "res://tests/test_case.gd"
## 클래스 기능 BG3식 개편(사용자 결정 2026-11-22): 재기의 숨결 1회, 뛰어난 운동선수 도약, 생명 영역 1레벨,
## 빠른 손 추가 보너스 행동, 2층 작업, 비전 회복 전투 밖, 급소 공격 수동, 교활한 일격 선택, 무기 액션, 상시 발동, 판정 실패 창.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Actions := preload("res://scripts/rules/actions.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Features := preload("res://scripts/rules/features.gd")
const Interact := preload("res://scripts/rules/interact.gd")


func _pc(cls: String, lv: int = 1) -> Node:
	return own(Builder.build(Builder.default_spec(cls, lv))["creature"])


func test_fighter_second_wind_and_athlete_jump() -> void:
	var f := _pc("fighter", 3)
	assert_eq(f.resources["second_wind"]["max"], 1)
	assert_eq(f.resources["second_wind"]["recharge"], "short")
	var f1 := _pc("fighter", 1)
	assert_eq(Combat.jump_distance(f), Combat.jump_distance(f1) + 1, "챔피언: 도약 +1칸")


func test_life_domain_at_level_1() -> void:
	var c := _pc("cleric", 1)
	assert_eq(c.subclass_id, "life")
	assert_true(c.has_feature("disciple_of_life"))
	assert_true(c.spells.has("bless") and c.spells.has("cure_wounds"), "영역 주문 항상 준비")
	assert_false(c.has_feature("preserve_life"), "생명 보존은 2레벨")
	assert_true(_pc("cleric", 2).has_feature("preserve_life"))


func test_thief_fast_hands_and_second_story() -> void:
	var r := _pc("rogue", 3)
	r.reset_turn()
	assert_eq(r.turn["bonus"], 2, "빠른 손: 보너스 행동 2개")
	var r1 := _pc("rogue", 1)
	assert_true(Combat.jump_distance(r) > Combat.jump_distance(r1), "2층 작업: 민첩 도약 + 1칸")
	var g := make_grid(["03"])
	g.place(r, Vector2i(0, 0))
	assert_true(g.can_step_sized(Vector2i(0, 0), Vector2i(1, 0), 1, r), "오르기 지점 없이 높은 칸을 오른다")
	var f := _pc("fighter", 3)
	g.place(f, Vector2i(0, 0))
	assert_false(g.can_step_sized(Vector2i(0, 0), Vector2i(1, 0), 1, f))


func test_arcane_recovery_out_of_combat_only() -> void:
	var w := make_world(["...."])
	var wz := _pc("wizard", 3)
	w["grid"].place(wz, Vector2i(0, 0))
	wz.resources["spell_slot_1"]["current"] = 0
	w["turns"].start_manual([wz])
	assert_false(Features.use(w, wz, "arcane_recovery")["ok"], "전투 중에는 못 쓴다")
	w["turns"].end_combat()
	assert_true(Features.use(w, wz, "arcane_recovery")["ok"], "전투 밖이면 언제나")
	assert_eq(wz.resource("arcane_recovery"), 0, "긴 휴식 1회")


func test_sneak_attack_manual_mode() -> void:
	var w := make_world(["....."])
	var r := _pc("rogue", 1)
	var ally := make_creature({"team": "party"})
	var e := make_creature({"team": "enemy", "hp_max": 50, "ac_base": 5})
	w["grid"].place(r, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(1, 0))
	w["grid"].place(ally, Vector2i(2, 0))
	Actions.toggle_passive(r, "sneak_attack")
	assert_eq(r.options["sneak_attack"], "manual")
	r.reset_turn()
	Dice.force([15, 3])
	var a: Dictionary = Combat.attack(w, r, e)
	assert_false(a.has("sneak_attack"), "수동이면 보통 공격에는 붙지 않는다")
	r.reset_turn()
	Dice.force([15, 3, 4])
	var s: Dictionary = Actions.execute(w, r, "sneak_melee", Vector2i(1, 0))
	assert_eq(int(s.get("sneak_attack", 0)), 1, "급소 공격 행동이면 붙는다")
	Actions.toggle_passive(r, "cunning_strike")
	assert_false(r.options.has("cunning_strike"), "1레벨에는 교활한 일격 설정이 없다(기능 데이터 toggle)")
	var r5 := _pc("rogue", 5)
	assert_true(Actions.passives(r5).any(func(p: Dictionary) -> bool: return p["id"] == "cunning_strike"), "5레벨 상시 발동 탭에 교활한 일격")
	Actions.toggle_passive(r5, "cunning_strike")
	assert_eq(r5.options["cunning_strike"], "poison", "교활한 일격 선택을 돌린다")


func test_weapon_actions() -> void:
	var w := make_world(["....", "...."])
	var f := _pc("fighter", 1)  # 롱소드 + 투창
	var e := make_creature({"team": "enemy", "hp_max": 50, "ac_base": 5, "abilities": {"dex": 1, "con": 1, "str": 1}})
	w["grid"].place(f, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(1, 0))
	var list: Array = Actions.list_for(w, f)["class"]
	assert_true("wa_sweep" in list and "wa_pommel" in list, "롱소드: 휩쓸기·손잡이 치기")
	assert_true("wa_impale" in list, "투창: 꿰뚫기")
	f.reset_turn()
	Dice.force([15, 2, 1])  # 명중, 1d4, 내성 1
	var r: Dictionary = Actions.execute(w, f, "wa_pommel", Vector2i(1, 0))
	assert_true(r["hit"])
	assert_true(e.has_condition("staggered"), "손잡이 치기: 반응 불가")
	assert_false(e.can_react())
	assert_eq(f.turn["bonus"], 0, "보너스 행동")
	assert_eq(Actions.unavailable(w, f, "wa_pommel"), "보너스 행동이 없다")
	f.reset_turn()
	assert_eq(Actions.unavailable(w, f, "wa_pommel"), "남은 횟수가 없다", "짧은 휴식에 1회")
	assert_eq(Actions.weapon_action_dc(f, "longsword"), 8 + 2 + 3)


func test_passives_reaction_toggle() -> void:
	var wz := _pc("wizard", 1)
	var ids: Array = Actions.passives(wz).map(func(p: Dictionary) -> String: return p["id"])
	assert_true("reaction:shield" in ids)
	Actions.toggle_passive(wz, "reaction:shield")
	assert_eq(wz.reaction_setting("shield"), "off")


func test_failure_window_rerolls() -> void:
	var w := {"inspiration": 1}
	var f := _pc("fighter", 2)
	Dice.force([5])  # 5 + 3 = 8 < 12: 보이는 굴림은 전술적 판단을 자동으로 쓰지 않는다
	var r: Dictionary = Interact.visible_check(w, f, "str", "athletics", 12)
	assert_false(r["success"])
	assert_eq(f.resource("second_wind"), 1)
	var opts: Array = Interact.reroll_options(w, f, r)
	assert_true("inspiration" in opts and "tactical_mind" in opts)
	Dice.force([9])
	var t: Dictionary = Interact.reroll(w, f, r, "tactical_mind")
	assert_true(t["success"], "전술적 판단 +1d10")
	assert_eq(f.resource("second_wind"), 0)
	Dice.force([18])
	var again: Dictionary = Interact.reroll(w, f, r, "inspiration")
	assert_true(again["success"] and again["rerolled"])
	assert_eq(w["inspiration"], 0)
