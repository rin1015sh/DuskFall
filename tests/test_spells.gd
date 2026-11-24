extends "res://tests/test_case.gd"
## 주문 시전(룰북 6단계 공통 변환·주문 변환표, SRD 5.2.1 원문): 효과 모델, 집중·지속, 상위 슬롯, 스크립트 주문.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Physics := preload("res://scripts/rules/physics.gd")


func _pc(class_id: String, level: int, extra: Dictionary = {}) -> Node:
	var spec := Builder.default_spec(class_id, level)
	spec.merge(extra, true)
	var r := Builder.build(spec)
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func _foe(values: Dictionary = {}) -> Node:
	var c := make_creature({"team": "enemy", "ac_base": 12, "hp_max": 60, "abilities": {"dex": 10, "con": 10, "wis": 10}})
	c.setup(values)
	return c


func _world(material: String = "stone") -> Dictionary:
	var rows: Array = []
	for i in 12:
		rows.append("....................")
	return make_world(rows, material)


func _cast(w: Dictionary, c: Node, sid: String, aim: Vector2i, opts: Dictionary = {}) -> Dictionary:
	if not c.spells.has(sid):
		c.spells.append(sid)
	c.reset_turn()
	return Spellcasting.cast(w, c, sid, aim, opts)


func test_bless_adds_d4_and_ends_with_concentration() -> void:
	var w := _world()
	var cleric := _pc("cleric", 1)
	var f := _pc("fighter", 1)
	var g := _foe({"ac_base": 30})
	w["grid"].place(cleric, Vector2i(0, 0))
	w["grid"].place(f, Vector2i(1, 0))
	w["grid"].place(g, Vector2i(2, 0))
	assert_true(_cast(w, cleric, "bless", Vector2i(1, 0))["ok"])
	assert_eq(cleric.concentration.get("id"), "bless")
	assert_eq(cleric.resource("spell_slot_1"), 1, "1레벨 슬롯")
	Dice.force([10, 4])
	var r := Resolver.attack(f, g, {"bonus": 5, "damage": []})
	assert_eq(r["total"], 10 + 5 + 4, "공격 굴림 + 1d4")
	cleric.break_concentration("시험")
	assert_eq(f.extra_modifiers.size(), 0, "집중이 끝나면 효과도 끝")


func test_new_concentration_ends_old() -> void:
	var w := _world()
	var cleric := _pc("cleric", 3)
	var f := _pc("fighter", 1)
	w["grid"].place(cleric, Vector2i(0, 0))
	w["grid"].place(f, Vector2i(1, 0))
	_cast(w, cleric, "bless", Vector2i(1, 0))
	_cast(w, cleric, "shield_of_faith", Vector2i(1, 0))
	assert_eq(cleric.concentration.get("id"), "shield_of_faith")
	assert_eq(f.ac(), 19 + 2, "Shield of Faith AC +2, 축복은 끝남")
	assert_eq(f.extra_modifiers.size(), 1)


func test_hold_person_repeat_save() -> void:
	var w := _world()
	var cleric := _pc("cleric", 3)
	var g := _foe()
	w["grid"].place(cleric, Vector2i(0, 0))
	w["grid"].place(g, Vector2i(3, 0))
	Dice.force([2])
	_cast(w, cleric, "hold_person", Vector2i(3, 0))
	assert_true(g.has_condition("paralyzed"))
	Dice.force([5])
	Spellcasting.on_turn_end(w, g)
	assert_true(g.has_condition("paralyzed"), "반복 내성 실패")
	Dice.force([19])
	Spellcasting.on_turn_end(w, g)
	assert_false(g.has_condition("paralyzed"), "턴 끝 반복 내성 성공 → 그 대상에게서 끝")


func test_fireball_area_half_and_grass() -> void:
	var w := _world("grass")
	var wiz := _pc("wizard", 5)
	var a := _foe({"abilities": {"dex": 10}})
	var b := _foe({"abilities": {"dex": 10}})
	w["grid"].place(wiz, Vector2i(0, 0))
	w["grid"].place(a, Vector2i(10, 5))
	w["grid"].place(b, Vector2i(12, 7))
	Dice.force([3, 19, 4, 4, 4, 4, 4, 4, 4, 4])
	var r := _cast(w, wiz, "fireball", Vector2i(10, 6))
	assert_eq(r["cells"].size(), 21, "반경 2칸(BG3 4m) 원형")
	assert_eq(a.hp, 60 - 32, "실패 8d6 = 32")
	assert_eq(b.hp, 60 - 16, "성공 절반")
	assert_eq(w["grid"].surface_id(Vector2i(10, 6)), "fire", "풀에 불이 붙는다(범위 칸 반응)")
	assert_eq(wiz.resource("spell_slot_3"), 1)


func test_upcast_dice_and_targets() -> void:
	var w := _world()
	var cleric := _pc("cleric", 5)
	var f := _pc("fighter", 5)
	w["grid"].place(cleric, Vector2i(0, 0))
	w["grid"].place(f, Vector2i(1, 0))
	f.hp = 1
	Dice.force([1, 1])
	_cast(w, cleric, "healing_word", Vector2i(1, 0), {"slot": 2})
	assert_eq(f.hp, 1 + 2 + 4 + 4, "2레벨 슬롯: 2d4(BG3 1d4 + 슬롯당 1d4) + 지혜 4 + 생명의 제자(2 + 2)")
	assert_eq(Spellcasting.max_targets(RulesDB.get_entry("spell", "hold_person"), 4), 3, "상위 슬롯 대상 +1씩")


func test_magic_missile_and_scorching_ray() -> void:
	var w := _world()
	var wiz := _pc("wizard", 3)
	var a := _foe()
	var b := _foe()
	w["grid"].place(wiz, Vector2i(0, 0))
	w["grid"].place(a, Vector2i(5, 0))
	w["grid"].place(b, Vector2i(5, 2))
	Dice.force([1, 1, 1, 1])
	_cast(w, wiz, "magic_missile", Vector2i(5, 0), {"slot": 2, "targets": [a, b]})
	assert_eq(a.hp, 60 - 4, "다트 4개(2레벨 슬롯)를 번갈아: a 2발")
	assert_eq(b.hp, 60 - 4)
	Dice.force([15, 3, 3, 1, 15, 2, 2])
	var r := _cast(w, wiz, "scorching_ray", Vector2i(5, 0))
	assert_eq(r["hits"], 2, "광선 3개 각각 공격(자연 1 빗나감)")


func test_mage_armor_and_misty_step() -> void:
	var w := _world()
	var wiz := _pc("wizard", 3)
	w["grid"].place(wiz, Vector2i(0, 0))
	_cast(w, wiz, "mage_armor", Vector2i(0, 0))
	assert_eq(wiz.ac(), 12 + 3, "갑옷이 없으면 13 + 민첩")
	_cast(w, wiz, "misty_step", Vector2i(5, 3))
	assert_eq(w["grid"].cell_of(wiz), Vector2i(5, 3), "순간이동 6칸")


func test_counterspell_reaction() -> void:
	var w := _world()
	var wiz := _pc("wizard", 5)
	var enemy := _pc("wizard", 5, {"team": "enemy"})
	w["grid"].place(wiz, Vector2i(0, 0))
	w["grid"].place(enemy, Vector2i(6, 0))
	assert_true("counterspell" in wiz.known_reactions)
	wiz.reaction_settings["counterspell"] = "auto"
	Dice.force([2])  # 적의 건강 내성 실패
	var r := _cast(w, enemy, "fireball", Vector2i(0, 2))
	assert_true(r.get("countered", false), "Counterspell로 끊김")
	assert_eq(enemy.resource("spell_slot_3"), 2, "끊긴 주문은 슬롯을 쓰지 않는다")
	assert_eq(wiz.resource("spell_slot_3"), 1, "대응 주문은 3레벨 슬롯")
	assert_false(wiz.can_react())


func test_haste_and_lethargy() -> void:
	var w := _world()
	var wiz := _pc("wizard", 5)
	var f := _pc("fighter", 5)
	w["grid"].place(wiz, Vector2i(0, 0))
	w["grid"].place(f, Vector2i(1, 0))
	_cast(w, wiz, "haste", Vector2i(1, 0))
	assert_eq(f.ac(), 19 + 2)
	assert_eq(f.speed(), 12, "속도 2배")
	w["turns"].begin_turn(f)
	assert_eq(f.turn["action"], 2, "추가 행동")
	wiz.break_concentration("시험")
	assert_true(f.has_condition("incapacitated"), "끝나면 다음 턴 끝까지 무력화")
	assert_eq(f.speed(), 0)


func test_spirit_guardians_on_enter() -> void:
	var w := _world()
	var cleric := _pc("cleric", 5)
	var g := _foe({"abilities": {"wis": 8}})
	w["grid"].place(cleric, Vector2i(5, 5))
	w["grid"].place(g, Vector2i(10, 5))
	_cast(w, cleric, "spirit_guardians", Vector2i(5, 5))
	g.reset_turn()
	Dice.force([2, 4, 4, 4])
	Combat.move(w, g, Vector2i(8, 5))
	assert_eq(g.hp, 60, "반경 2칸(BG3 3m) 밖")
	Combat.move(w, g, Vector2i(7, 5))
	assert_eq(g.hp, 60 - 12, "발산에 들어오면 지혜 내성, 실패 3d8")
	Combat.move(w, g, Vector2i(6, 5))
	assert_eq(g.hp, 48, "한 턴에 한 번")


func test_mirror_image_deflects() -> void:
	var w := _world()
	var wiz := _pc("wizard", 3)
	var g := _foe()
	w["grid"].place(wiz, Vector2i(0, 0))
	w["grid"].place(g, Vector2i(1, 0))
	_cast(w, wiz, "mirror_image", Vector2i(0, 0))
	Dice.force([18, 5])
	var r := Resolver.attack(g, wiz, {"bonus": 5, "damage": [{"dice": "1d6", "damage_type": "slashing"}]})
	assert_true(r.get("mirror_image", false), "분신이 대신 맞음")
	assert_eq(wiz.get_meta("mirror_images"), 2)


func test_invisibility_ends_on_attack() -> void:
	var w := _world()
	var wiz := _pc("wizard", 3)
	var g := _foe()
	w["grid"].place(wiz, Vector2i(0, 0))
	w["grid"].place(g, Vector2i(1, 0))
	_cast(w, wiz, "invisibility", Vector2i(0, 0))
	assert_true(wiz.has_condition("invisible"))
	Dice.force([10, 2])
	Resolver.attack(wiz, g, {"bonus": 2, "damage": [{"dice": "1d6", "damage_type": "bludgeoning"}]})
	assert_false(wiz.has_condition("invisible"), "공격하면 끝")


func test_revivify_within_ten_turns() -> void:
	var w := _world()
	var cleric := _pc("cleric", 5)
	var f := _pc("fighter", 1)
	w["grid"].place(cleric, Vector2i(0, 0))
	w["grid"].place(f, Vector2i(1, 0))
	Resolver.apply_damage(f, [{"amount": 40, "damage_type": "slashing"}])
	assert_true(f.dead)
	assert_true(_cast(w, cleric, "revivify", Vector2i(1, 0))["ok"])
	assert_false(f.dead)
	assert_eq(f.hp, 1)


func test_guiding_bolt_next_attack_advantage() -> void:
	var w := _world()
	var cleric := _pc("cleric", 1, {"spells": ["guiding_bolt"]})
	var f := _pc("fighter", 1)
	var g := _foe()
	w["grid"].place(cleric, Vector2i(0, 0))
	w["grid"].place(f, Vector2i(4, 1))
	w["grid"].place(g, Vector2i(5, 0))
	Dice.force([15, 1, 1, 1, 1])
	_cast(w, cleric, "guiding_bolt", Vector2i(5, 0))
	var atk := {"bonus": 5, "damage": []}
	assert_eq(Resolver.preview_attack(f, g, atk)["mode"], 1, "다음 공격 유리")
	Dice.force([3, 4])
	Resolver.attack(f, g, atk)
	assert_eq(Resolver.preview_attack(f, g, atk)["mode"], 0, "한 번 쓰면 끝")


func test_fog_cloud_removed_when_concentration_ends() -> void:
	var w := _world()
	var wiz := _pc("wizard", 1)
	w["grid"].place(wiz, Vector2i(0, 0))
	_cast(w, wiz, "fog_cloud", Vector2i(6, 6))
	assert_eq(w["grid"].cloud_id(Vector2i(6, 6)), "fog")
	wiz.break_concentration("시험")
	assert_eq(w["grid"].cloud_id(Vector2i(6, 6)), "", "집중이 끝나면 구름도 사라진다")


func test_feather_fall_bonus_action_buff() -> void:
	# BG3: 보너스 행동, 자신 주변 6칸(9m) 아군 모두 10턴 낙하 피해 면역
	var w := _world()
	var wiz := _pc("wizard", 1, {"spells": ["feather_fall", "magic_missile"]})
	var f := _pc("fighter", 1)
	var far := _pc("fighter", 1)
	var foe := _foe()
	w["grid"].place(wiz, Vector2i(0, 0))
	w["grid"].place(f, Vector2i(1, 0))
	w["grid"].place(far, Vector2i(10, 0))
	w["grid"].place(foe, Vector2i(0, 2))
	assert_true(_cast(w, wiz, "feather_fall", Vector2i(0, 0)).get("ok", false))
	assert_eq(int(wiz.turn["bonus"]), 0, "보너스 행동")
	assert_true(Physics.fall(f, 6)["prevented"], "주변 아군 낙하 피해 면역")
	assert_true(Physics.fall(wiz, 6)["prevented"], "시전자 자신도")
	assert_false(Physics.fall(far, 6)["prevented"], "6칸 밖은 아니다")
	assert_false(Physics.fall(foe, 6)["prevented"], "적은 아니다")


func test_slow_penalties() -> void:
	var w := _world()
	var wiz := _pc("wizard", 5)
	var g := _foe({"ac_base": 15, "speed_tiles": 6})
	w["grid"].place(wiz, Vector2i(0, 0))
	w["grid"].place(g, Vector2i(8, 5))
	Dice.force([2])
	_cast(w, wiz, "slow", Vector2i(8, 5))
	assert_eq(g.ac(), 13, "AC −2")
	assert_eq(g.speed(), 3, "속도 절반")
	assert_false(g.can_react(), "반응 불가")


func test_all_script_spells_implemented() -> void:
	# 모든 스크립트 주문이 구현됐다(구현 어려운 것 묶음 1, 2026-11-22)
	for e: Dictionary in RulesDB.entries("spell"):
		if e.has("script") and e["game_status"] == "included":
			var inst: Object = load("res://scripts/rules/features.gd").script_for(e["script"])
			assert_true(inst != null and inst.is_implemented(), "%s(%s)" % [e["id"], e["script"]])



## 반응 주문은 주문 데이터 cast.trigger로 고른다: 지옥의 질책(on_damage_taken) — 맞으면 공격자에게 반격(타고난 무료 횟수 먼저).
func test_hellish_rebuke_reaction_by_trigger() -> void:
	var w := _world()
	var t := _pc("fighter", 3, {"species": "tiefling", "lineage": "tiefling_infernal"})
	assert_true(t.spells.has("hellish_rebuke") and "hellish_rebuke" in t.known_reactions, "혈통 주문이 반응 목록에 %s" % str(t.known_reactions))
	var g := _foe()
	w["grid"].place(t, Vector2i(0, 0))
	w["grid"].place(g, Vector2i(1, 0))
	t.reaction_settings["hellish_rebuke"] = "auto"
	t.reset_turn()
	var hp: int = g.hp
	Dice.force([1])  # 고블린 민첩 내성 1 실패
	Resolver.apply_damage(t, [{"amount": 3, "damage_type": "slashing"}], {"attacker": g})
	assert_true(g.hp < hp, "공격자가 불 피해를 받았다")
	assert_eq(int(t.turn.get("reaction", 1)), 0, "반응을 썼다")
