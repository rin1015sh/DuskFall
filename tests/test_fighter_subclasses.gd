extends "res://tests/test_case.gd"
## 전사 BG3 서브클래스(4단계): 전술의 대가(배틀 마스터)·비전 궁수(아케인 아처)·전투 기법 입문 재주.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Actions := preload("res://scripts/rules/actions.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func _pc(lv: int, extra: Dictionary) -> Node:
	var spec := Builder.default_spec("fighter", lv)
	spec.merge(extra, true)
	var r := Builder.build(spec)
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func _foe(v: Dictionary = {}) -> Node:
	var d := {"team": "enemy", "ac_base": 5, "hp_max": 100, "abilities": {"str": 10, "dex": 10, "con": 10, "wis": 1, "cha": 1}}
	d.merge(v, true)
	return make_creature(d)


func _bm(lv: int, mans: Array) -> Node:
	return _pc(lv, {"subclass": "battle_master", "manoeuvres": mans})


func test_battle_master_dice_and_known() -> void:
	var c := _bm(3, ["wa_m_trip_attack", "wa_m_rally", "wa_m_riposte", "wa_m_pushing_attack"])
	assert_eq(c.resource("superiority_dice"), 4)
	assert_eq(c.get_meta("special_attacks").size(), 3, "3레벨 기법 3개")
	assert_eq(Actions.special_die(c, "superiority_dice"), "1d8")
	var c10 := _bm(10, ["wa_m_trip_attack"])
	assert_eq(c10.resource("superiority_dice"), 5)
	assert_eq(Actions.special_die(c10, "superiority_dice"), "1d10", "10레벨 d10")
	var w := make_world([".....", "....."])
	w["grid"].place(c, Vector2i(0, 0))
	w["grid"].place(_foe(), Vector2i(1, 0))
	var list: Array = Actions.list_for(w, c)["class"]
	assert_true("wa_m_trip_attack" in list and "wa_m_rally" in list)
	assert_false("wa_m_riposte" in list, "반격은 상시 설정")
	assert_false("wa_m_pushing_attack" in list, "배우지 않은 기법")


func test_trip_attack_consumes_on_hit() -> void:
	var c := _bm(3, ["wa_m_trip_attack"])
	var e := _foe()
	var w := make_world([".....", "....."])
	w["grid"].place(c, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(1, 0))
	c.reset_turn()
	Dice.force([1])
	Actions.execute(w, c, "wa_m_trip_attack", Vector2i(1, 0))
	assert_eq(c.resource("superiority_dice"), 4, "빗나가면 주사위를 쓰지 않는다")
	c.reset_turn()
	Dice.force([15, 4, 5, 1])  # 명중, 롱소드 1d8, 우월 1d8, 근력 내성 1
	var r: Dictionary = Actions.execute(w, c, "wa_m_trip_attack", Vector2i(1, 0))
	assert_true(r["hit"])
	assert_eq(c.resource("superiority_dice"), 3)
	assert_true(e.has_condition("prone"))
	assert_eq(e.hp, 100 - 4 - 5 - c.ability_mod("str"), "무기 + 우월 주사위")


func test_rally_riposte_precision() -> void:
	var c := _bm(3, ["wa_m_rally", "wa_m_riposte", "wa_m_precision_attack"])
	var ally := make_creature({"team": "party", "hp_max": 20})
	var e := _foe({"abilities": {"str": 10, "dex": 10, "con": 10}})
	var w := make_world([".....", "....."])
	w["grid"].place(c, Vector2i(0, 0))
	w["grid"].place(ally, Vector2i(0, 1))
	w["grid"].place(e, Vector2i(1, 0))
	c.reset_turn()
	assert_true(Actions.execute(w, c, "wa_m_rally", Vector2i(0, 1))["ok"])
	assert_eq(ally.temp_hp, 8)
	# 반격: 적의 근접 공격이 빗나가면
	c.refresh_reaction()
	var atk := {"name": "몽둥이", "bonus": 0, "kind": "melee", "weapon": false, "damage": [{"dice": "5", "damage_type": "bludgeoning"}]}
	Dice.force([2, 15, 4, 4])
	var hp: int = e.hp
	Resolver.attack(e, c, atk, w["grid"].attack_context(e, c))
	assert_false(c.can_react(), "반격")
	assert_true(e.hp < hp)
	# 정밀 공격: 빗나가면 주사위로
	var e2 := _foe({"ac_base": 18})
	w["grid"].place(e2, Vector2i(1, 1))
	c.reset_turn()
	var before: int = c.resource("superiority_dice")
	var need: int = 18 - int(Combat.build_weapon_attack(c, c.weapon("main"))["bonus"]) - 3  # 3 모자라게
	Dice.force([need, 8, 4])
	var r := Combat.attack(w, c, e2)
	assert_true(r["hit"], "정밀 공격으로 명중")
	assert_eq(c.resource("superiority_dice"), before - 1)


func test_sweeping_and_commander() -> void:
	var c := _bm(3, ["wa_m_sweeping_attack", "wa_m_commanders_strike"])
	var a := _foe()
	var b := _foe()
	var ally := _pc(1, {})
	ally.team = "party"
	var w := make_world([".....", ".....", "....."])
	w["grid"].place(c, Vector2i(1, 1))
	w["grid"].place(a, Vector2i(2, 1))
	w["grid"].place(b, Vector2i(2, 2))
	w["grid"].place(ally, Vector2i(3, 1))
	c.reset_turn()
	Dice.force([15, 6, 15, 6])
	var r: Dictionary = Actions.execute(w, c, "wa_m_sweeping_attack", Vector2i(2, 1))
	assert_eq(r["sweep"].size(), 2, "앞쪽 적 둘")
	assert_eq(a.hp, 94, "우월 주사위만")
	c.reset_turn()
	ally.refresh_reaction()
	Dice.force([15, 5, 3])
	var r2: Dictionary = Actions.execute(w, c, "wa_m_commanders_strike", Vector2i(2, 1))
	assert_true(r2.get("hit", false), str(r2))
	assert_false(ally.can_react(), "아군이 반응으로 공격")
	assert_eq(int(c.turn["bonus"]), 0)


func test_arcane_archer() -> void:
	var c := _pc(3, {"subclass": "arcane_archer", "arcane_archer_lore": "true_strike", "arcane_shot": ["wa_a_bursting", "wa_a_seeking", "wa_a_shadow"],
		"weapons": {"melee": {"main": "longsword", "off": ""}, "ranged": {"main": "longbow"}}})
	assert_eq(c.resource("arcane_arrows"), 4)
	assert_true(c.skill_bonuses.has("arcana") and c.skill_bonuses.has("nature"))
	assert_true(c.spells.has("true_strike"))
	var a := _foe()
	var b := _foe()
	var w := make_world(["..........", ".........."])
	w["grid"].place(c, Vector2i(0, 0))
	w["grid"].place(a, Vector2i(6, 0))
	w["grid"].place(b, Vector2i(7, 0))
	c.reset_turn()
	Dice.force([15, 5, 3, 3])  # 명중, 롱보우 1d8, 폭발 2d6
	var r: Dictionary = Actions.execute(w, c, "wa_a_bursting", Vector2i(6, 0))
	assert_true(r["hit"])
	assert_eq(b.hp, 94, "폭발: 곁의 적 역장 2d6")
	assert_eq(c.resource("arcane_arrows"), 3)
	c.reset_turn()
	Dice.force([4, 3, 1])  # 무기 1d8, 1d6, 민첩 내성
	var r2: Dictionary = Actions.execute(w, c, "wa_a_seeking", Vector2i(7, 0))
	assert_true(r2["hit"] and b.has_condition("outlined"), "추적 화살: 굴림 없이 맞고 윤곽")
	assert_eq(Actions.weapon_action_dc(c, "wa_a_seeking"), 8 + c.proficiency_bonus + c.ability_mod("int"))


func test_curving_shot_and_magic_arrow() -> void:
	var c := _pc(7, {"subclass": "arcane_archer", "arcane_archer_lore": "light", "arcane_shot": ["wa_a_bursting"],
		"weapons": {"melee": {"main": "longsword", "off": ""}, "ranged": {"main": "longbow"}}})
	assert_true(Combat.build_weapon_attack(c, "longbow")["magical"], "마법 화살")
	var a := _foe({"ac_base": 30})
	var b := _foe()
	var w := make_world(["..........", ".........."])
	w["grid"].place(c, Vector2i(0, 0))
	w["grid"].place(a, Vector2i(6, 0))
	w["grid"].place(b, Vector2i(7, 1))
	c.reset_turn()
	c.active_set = "ranged"
	Dice.force([2, 15, 5])
	var r := Combat.attack(w, c, a, {"weapon": "longbow"})
	assert_true(r.has("curving"), "빗나가면 휘는 화살")
	assert_true(b.hp < 100)
	assert_eq(int(c.turn["bonus"]), 0)


func test_martial_adept() -> void:
	var c := _pc(4, {"asi": {"4": {"feat": "martial_adept"}}, "martial_adept": ["wa_m_trip_attack", "wa_m_rally"]})
	assert_eq(c.resource("superiority_dice"), 1)
	assert_eq(Actions.special_die(c, "superiority_dice"), "1d6")
	assert_eq(c.get_meta("special_attacks").size(), 2)
	var bm := _pc(4, {"subclass": "battle_master", "manoeuvres": ["wa_m_pushing_attack"], "asi": {"4": {"feat": "martial_adept"}}, "martial_adept": ["wa_m_trip_attack", "wa_m_rally"]})
	assert_eq(bm.resource("superiority_dice"), 5, "배틀 마스터 4 + 1")
	assert_eq(Actions.special_die(bm, "superiority_dice"), "1d8", "큰 주사위")


const Spellcasting := preload("res://scripts/rules/spellcasting.gd")


func _ek(lv: int, sp: Dictionary) -> Node:
	return _pc(lv, {"subclass": "eldritch_knight", "subclass_spells": sp,
		"scores": {"str": 15, "dex": 12, "con": 14, "int": 13, "wis": 10, "cha": 8}, "bonus": {"str": 2, "int": 1}})


func test_eldritch_knight_spellcasting() -> void:
	var c := _ek(3, {"cantrips": ["fire_bolt", "shocking_grasp"], "spells": ["shield", "magic_missile", "sleep", "burning_hands"]})
	assert_eq(c.resource("spell_slot_1"), 2, "3레벨 1레벨 슬롯 2")
	assert_true(c.spells.has("fire_bolt") and c.spells.has("shield") and c.spells.has("sleep"))
	assert_false(c.spells.has("burning_hands"), "아는 주문 3개까지")
	assert_eq(Spellcasting.ability_for(c, "fire_bolt"), "int")
	var c7 := _ek(7, {"cantrips": ["fire_bolt", "shocking_grasp"], "spells": ["shield", "magic_missile", "sleep", "burning_hands", "thunderwave", "scorching_ray"]})
	assert_eq(c7.resource("spell_slot_2"), 2, "7레벨 2레벨 슬롯 2")
	assert_true(c7.spells.has("scorching_ray"))
	var bad := Builder.default_spec("fighter", 3)
	bad["subclass"] = "eldritch_knight"
	bad["subclass_spells"] = {"cantrips": ["fire_bolt"], "spells": ["sleep", "charm_person", "shield"]}
	assert_true(Array(Builder.validate(bad)).any(func(e: String) -> bool: return e.contains("학파")), "3레벨 학파 밖 주문은 하나만")


func test_war_magic_and_eldritch_strike() -> void:
	var c := _ek(10, {"cantrips": ["fire_bolt", "shocking_grasp", "light"], "spells": ["shield", "magic_missile", "sleep"]})
	var e := _foe({"abilities": {"str": 10, "dex": 10, "con": 10, "wis": 10}})
	var w := make_world(["......", "......"])
	w["grid"].place(c, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(1, 0))
	c.reset_turn()
	Dice.force([15, 3, 3])
	assert_true(Spellcasting.cast(w, c, "shocking_grasp", Vector2i(1, 0)).get("ok", false))
	assert_eq(Actions.unavailable(w, c, "war_magic_attack"), "", "전쟁 마법: 보너스 행동 공격")
	Dice.force([15, 4])
	assert_true(Actions.execute(w, c, "war_magic_attack", Vector2i(1, 0)).get("hit", false))
	assert_true(e.has_meta("eldritch_strike") and e.get_meta("eldritch_strike") == c, "비전 일격 표시")
	var s := Resolver.saving_throw(e, "wis", 10, {"source": c, "magic": true})
	assert_eq(int(s["mode"]), -1, "다음 주문 내성 불리")
	assert_true(c.is_condition_immune("disarmed"), "무기 결속")
