extends "res://tests/test_case.gd"
## 무기 액션(BG3 기본 20종 구조, 이름·설명 자체 — 사용자 결정 2026-11-23, 무기 마스터리 대신).

const Builder := preload("res://scripts/rules/character_builder.gd")
const Actions := preload("res://scripts/rules/actions.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const MF := preload("res://scripts/rules/monster_factory.gd")


func _pc(cls: String, lv: int = 1) -> Node:
	var r := Builder.build(Builder.default_spec(cls, lv))
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


## 재주·기능 없는 전사형 생물(야만적 공격 같은 피해 재굴림이 끼지 않게): 근력 16(+3), 숙련 +2
func _fighter(main: String, lv: int = 1, ranged: String = "") -> Node:
	return make_creature({"team": "party", "hp_max": 40, "abilities": {"str": 16, "dex": 10}, "proficiency_bonus": 2,
		"attacks_per_action": 2 if lv >= 5 else 1, "weapon_proficiencies": ["simple", "martial"],
		"weapon_sets": {"melee": {"main": main, "off": ""}, "ranged": {"main": ranged}}})


func _foe(extra: Dictionary = {}) -> Node:
	var v := {"team": "enemy", "hp_max": 60, "ac_base": 5, "abilities": {"dex": 1, "con": 1, "str": 1, "wis": 1}}
	v.merge(extra, true)
	return make_creature(v)


func _arena(f: Node, foes: Array) -> Dictionary:
	var w := make_world([".......", ".......", "......."])
	w["grid"].place(f, Vector2i(1, 1))
	var cells := [Vector2i(2, 1), Vector2i(2, 0), Vector2i(2, 2)]
	for i in foes.size():
		w["grid"].place(foes[i], cells[i])
	f.reset_turn()
	return w


func test_list_and_dc() -> void:
	var f := _fighter("longsword", 1, "javelin")
	var w := _arena(f, [_foe()])
	var list: Array = Actions.list_for(w, f)["class"]
	for k: String in ["wa_pommel", "wa_rending_cut", "wa_charging_thrust", "wa_impale"]:
		assert_true(k in list, k)
	assert_false("wa_sweep" in list, "롱소드는 휩쓸기가 없다(BG3)")
	var mod := maxi(f.ability_mod("str"), f.ability_mod("dex"))
	assert_eq(Actions.weapon_action_dc(f, "wa_charging_thrust"), 8 + 2 + mod, "기본 DC")
	assert_eq(Actions.weapon_action_dc(f, "wa_pommel"), 8 + 2 + mod + 2, "DC + 2")


func test_pommel_reeling() -> void:
	var f := _fighter("longsword")
	var e := _foe({"abilities": {"dex": 16, "con": 1, "str": 1, "wis": 1}, "ac_base": 13})
	var w := _arena(f, [e])
	var ac0: int = e.ac()
	Dice.force([15, 2, 1])  # 명중, 1d4, 내성 1
	var r: Dictionary = Actions.execute(w, f, "wa_pommel", Vector2i(2, 1))
	assert_true(r.get("hit", false), str(r))
	assert_eq(e.hp, 60 - 2, "1d4 타격, 능력 수정치 없음")
	assert_true(e.has_condition("reeling"))
	assert_false(e.can_react(), "반응 불가")
	assert_eq(e.ac(), ac0 - 3, "AC에 민첩 보너스 없음")
	assert_eq(f.turn["bonus"], 0, "보너스 행동")
	f.reset_turn()
	assert_eq(Actions.unavailable(w, f, "wa_pommel"), "남은 횟수가 없다", "짧은 휴식에 1회")
	# 돕기로 풀린다(BG3)
	var ally := make_creature({"team": "enemy", "hp_max": 10})
	w["grid"].place(ally, Vector2i(3, 1))
	ally.reset_turn()
	assert_true(Combat.help(w, ally, e)["ok"])
	assert_false(e.has_condition("reeling"))


func test_action_weapon_action_keeps_extra_attack() -> void:
	var f := _fighter("longsword", 5)
	var w := _arena(f, [_foe()])
	Dice.force([15, 4, 20])  # 명중, 1d8, 내성 성공
	var r: Dictionary = Actions.execute(w, f, "wa_rending_cut", Vector2i(2, 1))
	assert_true(r["ok"])
	assert_eq(int(f.turn["action"]), 0)
	assert_eq(int(f.turn["attacks_left"]), 1, "추가 공격 하나가 남는다")
	assert_eq(f.resource("wa_rending_cut"), 0, "성공해도 빗나가도 쓴 것")


func test_bleeding_ticks_and_heal_ends() -> void:
	var f := _fighter("longsword")
	var e := _foe()
	var w := _arena(f, [e])
	Dice.force([15, 4, 1])
	Actions.execute(w, f, "wa_rending_cut", Vector2i(2, 1))
	assert_true(e.has_condition("bleeding"))
	var hp: int = e.hp
	Resolver.start_turn(e, {"in_combat": true})
	assert_eq(e.hp, hp - 2, "턴 시작 참격 2")
	Resolver.heal(e, 1)
	assert_false(e.has_condition("bleeding"), "회복하면 풀린다")
	var skel := _foe()
	skel.creature_type = "undead"
	assert_false(skel.apply_condition("bleeding", 2), "언데드는 출혈 면역")


func test_sweep_three_targets_half_damage() -> void:
	var f := _fighter("greatsword")
	var a := _foe()
	var b := _foe()
	var c := _foe()
	var w := _arena(f, [a, b, c])
	Dice.force([15, 6, 6, 15, 6, 6, 15, 6, 6])
	var r: Dictionary = Actions.execute(w, f, "wa_sweep", Vector2i(2, 1))
	assert_eq(r["cleave"].size(), 2, "대상 + 곁의 둘")
	var full: int = 12 + f.ability_mod("str")
	assert_eq(a.hp, 60 - full / 2, "무기 피해 절반")
	assert_eq(b.hp, 60 - full / 2)
	assert_eq(c.hp, 60 - full / 2)


func test_stances() -> void:
	var f := _fighter("glaive")
	var e := _foe()
	var w := _arena(f, [e])
	var mv: int = f.turn["movement"]
	assert_true(Actions.execute(w, f, "wa_set_stance", Vector2i(1, 1))["ok"])
	assert_eq(int(f.turn["movement"]), mv - 4, "이동력 4칸")
	assert_true(f.turn.get("stance_brace_melee", false))
	Dice.force([15, 1, 10])  # 명중, 1d10 두 번 → 큰 쪽 10
	Combat.attack(w, f, e)
	assert_eq(e.hp, 60 - 10 - f.ability_mod("str"), "두 번 굴려 큰 쪽")
	var g := _fighter("greataxe")
	var e2 := _foe()
	var w2 := _arena(g, [e2])
	assert_true(Actions.execute(w2, g, "wa_gather_strength", Vector2i(1, 1))["ok"])
	Dice.force([15, 5])
	Combat.attack(w2, g, e2)
	assert_eq(e2.hp, 60 - 5 - 2 * g.ability_mod("str"), "힘 모으기: 근력 수정치 추가")


func test_follow_through_on_miss() -> void:
	var f := _fighter("maul")
	var e := _foe({"ac_base": 30})
	var w := _arena(f, [e])
	Dice.force([2])
	var r := Combat.attack(w, f, e)
	assert_false(r["hit"])
	assert_eq(e.hp, 60 - maxi(1, f.ability_mod("str")), "빗나가도 근력 수정치")
	assert_false(f.can_react(), "반응을 쓴다")
	assert_false("wa_follow_through" in Actions.list_for(w, f)["class"], "단축 막대에는 없다")


func test_off_balance_ends_on_damage() -> void:
	var f := _fighter("rapier")
	var e := _foe()
	var w := _arena(f, [e])
	Dice.force([15, 2, 1])
	Actions.execute(w, f, "wa_feint", Vector2i(2, 1))
	assert_true(e.has_condition("off_balance"))
	assert_eq(int(Combat.preview_attack(w, f, e)["mode"]), 1, "이 대상을 노린 공격 유리")
	Resolver.apply_damage(e, [{"amount": 1, "damage_type": "fire"}])
	assert_false(e.has_condition("off_balance"), "피해를 받으면 풀린다")


func test_winded_crippled_hamstrung_open_wound() -> void:
	var e := _foe({"speed_tiles": 6})
	e.apply_condition("winded", 2)
	e.reset_turn()
	assert_eq(int(e.turn["action"]), 0, "숨 막힘: 행동 하나 적음")
	e.apply_condition("crippled", 2)
	assert_eq(e.speed(), 0)
	e.remove_condition("crippled")
	e.apply_condition("hamstrung", 2)
	assert_eq(e.speed(), 3, "속도 절반")
	var f := _fighter("longsword")
	var w := _arena(f, [e])
	e.apply_condition("open_wound", 2)
	Dice.force([15, 4])
	Combat.attack(w, f, e)
	assert_eq(e.hp, 60 - 4 - f.ability_mod("str") - 2, "벌어진 상처: 관통 2 추가")


func test_disarm() -> void:
	var f := _fighter("trident")
	var gob: Node = own(MF.spawn("goblin_warrior", "enemy"))
	var w := _arena(f, [gob])
	assert_true(MF.actions(gob).any(func(a: Dictionary) -> bool: return a["id"] == "scimitar"))
	Dice.force([19, 1, 1])
	var r: Dictionary = Actions.execute(w, f, "wa_knock_aside", Vector2i(2, 1))
	assert_true(r["hit"])
	assert_true(gob.has_condition("disarmed"))
	assert_false(MF.actions(gob).any(func(a: Dictionary) -> bool: return a["id"] == "scimitar"), "무기 공격을 못 쓴다")
	var wolf: Node = own(MF.spawn("wolf", "enemy"))
	w["grid"].place(wolf, Vector2i(0, 0))
	f.resources["wa_knock_aside"]["current"] = 1
	f.reset_turn()
	assert_eq(Actions.execute(w, f, "wa_knock_aside", Vector2i(0, 0)).get("reason", ""), "무기를 든 대상만")


func test_running_shot_needs_dash() -> void:
	var f := _fighter("shortsword", 1, "hand_crossbow")
	var e := _foe()
	var w := _arena(f, [e])
	assert_eq(Actions.unavailable(w, f, "wa_running_shot"), "이번 턴에 질주나 이탈을 해야 한다")
	Combat.disengage(f)
	assert_eq(Actions.unavailable(w, f, "wa_running_shot"), "")


func test_charge() -> void:
	var f := _fighter("spear")
	var e := _foe()
	var w := make_world([".........", "........."])
	w["grid"].place(f, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(5, 0))
	f.reset_turn()
	Dice.force([15, 2, 1])
	var r: Dictionary = Actions.execute(w, f, "wa_charging_thrust", Vector2i(5, 0))
	assert_true(r.get("hit", false), str(r))
	assert_eq(w["grid"].distance_between(f, e), 1, "붙었다")
	assert_true(e.has_condition("off_balance"))


func test_follow_through_toggle() -> void:
	var f := _fighter("maul")
	assert_true(Actions.passives(f).any(func(p: Dictionary) -> bool: return p["id"] == "wa_follow_through"), "상시 설정에 끈기")
	Actions.toggle_passive(f, "wa_follow_through")
	var e := _foe({"ac_base": 30})
	var w := _arena(f, [e])
	Dice.force([2])
	Combat.attack(w, f, e)
	assert_eq(e.hp, 60, "끄면 피해 없음")
