extends "res://tests/test_case.gd"
## 시범 클래스 레인저(데이터만 + 일반 엔진 장치): 선호하는 적(사냥꾼의 표식 무료 시전), 표식 추가 피해·자동 옮기기,
## 얽어매는 일격(다음 무기 명중 → 내성 → 휘감김, 행동으로 풀기), 휘감기(덩굴 표면·속박 풀기), 나무껍질 피부(AC 17 바닥),
## 좋은열매(소지품·긴 휴식에 사라짐), 사냥꾼의 먹잇감(거상 학살자·무리 파괴자), 5레벨 추가 공격.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Actions := preload("res://scripts/rules/actions.gd")
const Rest := preload("res://scripts/rules/rest.gd")


func _ranger(lv: int, extra: Dictionary = {}) -> Node:
	var spec := Builder.default_spec("ranger", lv)
	spec.merge(extra, true)
	var r := Builder.build(spec)
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func _foe(hp := 40, ac := 5) -> Node:
	var f := make_creature({"team": "enemy", "hp_max": hp, "ac_base": ac})
	return f


func test_build_and_favored_enemy_free_casts() -> void:
	var r1 := _ranger(1)
	assert_true(r1.skill_bonuses.has("history"), "선호하는 적: 레인저 기사(역사)")
	assert_true("poison" in r1.damage_resistances, "자연 탐험가: 황무지 방랑자(독)")
	assert_eq(_ranger(5).attacks_per_action, 2, "5레벨 추가 공격")
	assert_true(_ranger(3).has_cap("extra_damage_wounded"), "추천 빌드: 거상 학살자")
	var w := make_world(["......"])
	var foe := _foe()
	w["grid"].place(r1, Vector2i(0, 0))
	w["grid"].place(foe, Vector2i(4, 0))

func test_mark_bonus_damage_and_auto_transfer() -> void:
	var w := make_world([".......", "......."])
	var r := _ranger(1, {"spells": ["hunters_mark", "cure_wounds"]})  # BG3: 준비 주문으로
	var a := _foe(40)
	var b := _foe(40)
	w["grid"].place(r, Vector2i(0, 0))
	w["grid"].place(a, Vector2i(1, 0))
	w["grid"].place(b, Vector2i(4, 1))
	r.reset_turn()
	Spellcasting.cast(w, r, "hunters_mark", Vector2i(1, 0))
	r.reset_turn()
	Dice.force([18])
	var res: Dictionary = Combat.attack(w, r, a)
	assert_true(res["hit"], "명중")
	assert_true(res.get("extra_damage", []).any(func(e: Dictionary) -> bool: return e["damage_type"] == "force" and e["dice"] == "1d6"), "표식 +1d6 역장")
	Resolver.apply_damage(a, [{"amount": 999, "damage_type": "force"}], {"attacker": r})
	assert_true(b.has_condition("hunters_marked"), "쓰러지면 가장 가까운 적에게 자동으로 옮긴다")
	assert_false(a.has_condition("hunters_marked"))


func test_ensnaring_strike_and_escape() -> void:
	var w := make_world(["....."])
	var r := _ranger(1)
	var foe := _foe(60)
	foe.abilities["str"] = 6
	w["grid"].place(r, Vector2i(0, 0))
	w["grid"].place(foe, Vector2i(1, 0))
	r.reset_turn()
	assert_true(Spellcasting.cast(w, r, "ensnaring_strike", Vector2i(0, 0)).get("ok", false))
	assert_true(r.has_condition("ensnaring_ready"), "준비")
	r.reset_turn()
	Dice.force([18, 2])  # 공격 18 명중, 대상 근력 내성 2 실패
	Combat.attack(w, r, foe, {"weapon": "shortsword"})
	assert_false(r.has_condition("ensnaring_ready"), "발동하면 사라진다")
	assert_true(foe.has_condition("ensnared") and foe.has_condition("restrained"), "휘감김(속박 포함)")
	foe.reset_turn()
	Dice.force([20])
	var e: Dictionary = Combat.escape(w, foe)
	assert_true(e.get("ok", false) and e.get("success", false), "행동으로 풀었다 %s" % str(e))
	assert_false(foe.has_condition("ensnared"))


func test_entangle_barkskin_goodberry() -> void:
	var w := make_world(["........", "........", "........", "........"])
	var r := _ranger(5)
	var foe := _foe(30)
	foe.abilities["str"] = 1
	w["grid"].place(r, Vector2i(0, 0))
	w["grid"].place(foe, Vector2i(5, 2))
	r.reset_turn()
	Dice.force([1])
	assert_true(Spellcasting.cast(w, r, "entangle", Vector2i(5, 2)).get("ok", false))
	assert_eq(w["grid"].surface_id(Vector2i(5, 2)), "vines", "휘감는 덩굴(어려운 지형)")
	assert_true(foe.has_condition("restrained") and foe.condition_instance("restrained")["params"].has("escape_dc"), "속박 — 행동으로 풀 수 있다")
	var ally := make_creature({"team": "party", "ac_base": 11})
	w["grid"].place(ally, Vector2i(1, 0))
	r.reset_turn()
	assert_true(Spellcasting.cast(w, r, "barkskin", Vector2i(1, 0)).get("ok", false))
	assert_eq(ally.ac(), 17, "AC 17 바닥")
	r.reset_turn()
	assert_true(Spellcasting.cast(w, r, "goodberry", Vector2i(0, 0)).get("ok", false))
	assert_eq(int(r.inventory.get("goodberry", 0)), 10, "좋은열매 10개(시전자 소지품)")
	var keys: Array = Actions.list_for(w, r)["items"]
	assert_true("drink:goodberry" in keys and not "throw_potion:goodberry" in keys, "먹기는 되고 던지기는 없다")
	Rest.long_rest(w, [r], {"tiny_hut": true})
	assert_eq(int(r.inventory.get("goodberry", 0)), 0, "긴 휴식에 사라진다")


func test_hunters_prey_options() -> void:
	var w := make_world([".....", "....."])
	var r := _ranger(3)
	var foe := _foe(40)
	foe.hp = 30
	w["grid"].place(r, Vector2i(0, 0))
	w["grid"].place(foe, Vector2i(1, 0))
	r.reset_turn()
	Dice.force([18])
	var res: Dictionary = Combat.attack(w, r, foe, {"weapon": "shortsword"})
	assert_true(res.get("extra_damage", []).any(func(e: Dictionary) -> bool: return e["dice"] == "1d8"), "거상 학살자 +1d8(다친 대상)")
	var w2 := make_world([".....", "....."])
	var h := _ranger(3, {"hunters_prey": "horde_breaker"})
	var a := _foe(60, 1)
	var b := _foe(60, 1)
	w2["grid"].place(h, Vector2i(0, 0))
	w2["grid"].place(a, Vector2i(1, 0))
	w2["grid"].place(b, Vector2i(1, 1))
	h.reset_turn()
	var hp_before: int = b.hp
	Dice.force([18, 3, 18, 3])  # 공격·피해, 무리 파괴자 공격·피해
	Combat.attack(w2, h, a, {"weapon": "shortsword"})
	assert_true(h.turn.get("horde_used", false), "무리 파괴자로 한 번 더")
	assert_true(b.hp < hp_before, "옆의 다른 적도 맞았다")
	assert_eq(int(h.turn.get("attacks_left", 0)), 0, "공격 횟수는 그대로(1회 공격)")
