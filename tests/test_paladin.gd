extends "res://tests/test_case.gd"
## 팔라딘(데이터만 + 일반 장치): 신성한 손길(풀·해독), 팔라딘의 강타(항상 준비·무료 1회), 신성한 강타(근접 명중에 발동·상위 슬롯·언데드),
## 타오르는 강타(지속 피해·반복 내성), 신의 은총(명중마다), 영웅심(턴 시작 임시 HP), 신성 변환·신성한 무기, 맹세 주문, 반쪽 시전자 슬롯.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Features := preload("res://scripts/rules/features.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func _pal(lv: int, extra: Dictionary = {}) -> Node:
	var spec := Builder.default_spec("paladin", lv)
	spec.merge(extra, true)
	var r := Builder.build(spec)
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func _foe(hp := 60, extra := {}) -> Node:
	var f := make_creature({"team": "enemy", "hp_max": hp, "ac_base": 5})
	f.setup(extra)
	return f


func test_build_and_spells() -> void:
	var p1 := _pal(1)
	assert_eq(p1.resource("lay_on_hands"), 3, "BG3: 신성한 손길 3회")
	assert_false(p1.spells.has("divine_smite"), "강타는 2레벨부터")
	var p5 := _pal(5)
	assert_eq(p5.resource("lay_on_hands"), 4, "4레벨 4회")
	assert_eq(p5.resource("spell_slot_2"), 2, "반쪽 시전자 5레벨 4/2")
	assert_eq(p5.attacks_per_action, 2)
	for s: String in ["divine_smite", "protection_from_evil_and_good", "sanctuary", "lesser_restoration", "silence"]:
		assert_true(p5.spells.has(s), "항상 준비 %s" % s)
	assert_eq(p5.resource("channel_divinity"), 1, "맹세 변환 1회(BG3)")
	assert_false(p5.resources.has("innate_divine_smite"), "무료 강타 없음(BG3)")


func test_lay_on_hands_pool_and_cure() -> void:
	var w := make_world(["...."])
	var p := _pal(3)
	var ally := make_creature({"team": "party", "hp_max": 30})
	w["grid"].place(p, Vector2i(0, 0))
	w["grid"].place(ally, Vector2i(1, 0))
	ally.hp = 25
	ally.apply_condition("poisoned", 10)
	p.reset_turn()
	var r := Features.use(w, p, "lay_on_hands", ally)
	assert_true(r["ok"], str(r))
	assert_false(ally.has_condition("poisoned"), "해독")
	assert_eq(ally.hp, 30)
	assert_eq(p.resource("lay_on_hands"), 2, "1회 사용(BG3)")
	p.reset_turn()
	assert_false(Features.use(w, p, "lay_on_hands", ally)["ok"], "회복할 것이 없다")


func test_divine_smite_free_then_slot_upcast_undead() -> void:
	var w := make_world(["....."])
	var p := _pal(5)
	var zombie := _foe(80, {"creature_type": "undead"})
	w["grid"].place(p, Vector2i(0, 0))
	w["grid"].place(zombie, Vector2i(1, 0))
	p.reset_turn()
	var r: Dictionary = Spellcasting.cast(w, p, "divine_smite", Vector2i(0, 0))
	assert_true(r.get("ok", false), str(r))
	assert_eq(p.resource("innate_divine_smite"), 0, "무료 1회 먼저")
	assert_true(p.has_condition("divine_smite_ready"))
	p.reset_turn()
	Dice.force([18])
	var res: Dictionary = Combat.attack(w, p, zombie, {"weapon": "javelin", "thrown": true})
	assert_true(p.has_condition("divine_smite_ready"), "원거리(던지기) 명중에는 발동하지 않고 남는다")
	p.reset_turn()
	Dice.force([18])
	res = Combat.attack(w, p, zombie, {"weapon": "longsword"})
	assert_false(p.has_condition("divine_smite_ready"), "근접 명중에 발동하고 사라진다")
	assert_true(res.get("extra_damage", []).any(func(e: Dictionary) -> bool: return e["damage_type"] == "radiant" and e["dice"] == "2d8+1d8"), "언데드 +1d8 %s" % str(res.get("extra_damage")))
	p.reset_turn()
	Spellcasting.cast(w, p, "divine_smite", Vector2i(0, 0), {"slot": 2})
	assert_eq(p.resource("spell_slot_2"), 1, "2레벨 슬롯")
	p.reset_turn()
	Dice.force([18])
	res = Combat.attack(w, p, zombie, {"weapon": "longsword"})
	assert_true(res.get("extra_damage", []).any(func(e: Dictionary) -> bool: return e["dice"] == "2d8+1d8+1d8"), "상위 슬롯 +1d8 %s" % str(res.get("extra_damage")))


func test_searing_smite_dot_and_divine_favor() -> void:
	var w := make_world(["....."])
	var p := _pal(3, {"spells": ["searing_smite", "divine_favor", "bless", "heroism"]})
	var f := _foe(80, {"abilities": {"con": 1}})
	w["grid"].place(p, Vector2i(0, 0))
	w["grid"].place(f, Vector2i(1, 0))
	p.reset_turn()
	assert_true(Spellcasting.cast(w, p, "searing_smite", Vector2i(0, 0)).get("ok", false))
	p.reset_turn()
	Dice.force([18])
	Combat.attack(w, p, f, {"weapon": "longsword"})
	assert_true(f.has_condition("seared"), "타오름")
	assert_true(f.condition_instance("seared")["params"].has("repeat_save"), "턴 끝 건강 내성")
	var hp: int = f.hp
	Resolver.start_turn(f)
	assert_true(f.hp < hp, "턴 시작 화염 피해")
	p.reset_turn()
	Spellcasting.cast(w, p, "divine_favor", Vector2i(0, 0))
	p.reset_turn()
	Dice.force([18])
	var res: Dictionary = Combat.attack(w, p, f, {"weapon": "longsword"})
	assert_true(res.get("extra_damage", []).any(func(e: Dictionary) -> bool: return e["dice"] == "1d4"), "신의 은총 +1d4")
	assert_true(p.has_condition("divine_favor"), "신의 은총은 남는다")


func test_heroism_and_sacred_weapon() -> void:
	var w := make_world(["....."])
	var p := _pal(3)
	var ally := make_creature({"team": "party", "hp_max": 20})
	w["grid"].place(p, Vector2i(0, 0))
	w["grid"].place(ally, Vector2i(1, 0))
	p.reset_turn()
	assert_true(Spellcasting.cast(w, p, "heroism", Vector2i(1, 0)).get("ok", false))
	assert_false(ally.apply_condition("frightened", 2), "공포 면역")
	Resolver.start_turn(ally)
	assert_eq(ally.temp_hp, maxi(1, p.ability_mod("cha")), "턴 시작 임시 HP")
	var before: int = Combat.build_weapon_attack(p, "longsword")["bonus"]
	p.reset_turn()
	assert_true(Features.use(w, p, "sacred_weapon")["ok"])
	assert_eq(p.resource("channel_divinity"), 0)
	assert_eq(int(Combat.build_weapon_attack(p, "longsword")["bonus"]), before + maxi(1, p.ability_mod("cha")), "명중 + 매력")


func test_divine_sense_and_faithful_steed() -> void:
	var w := make_world([".........", "........."])
	var p := _pal(5)
	var undead := _foe(30, {"creature_type": "undead"})
	var orc := _foe(30)
	w["grid"].place(p, Vector2i(0, 0))
	w["grid"].place(undead, Vector2i(6, 0))
	w["grid"].place(orc, Vector2i(6, 1))
	undead.apply_condition("invisible", -1, "hide")
	p.reset_turn()
	assert_true(Features.use(w, p, "divine_sense")["ok"])
	assert_true(undead.has_condition("divine_sensed") and not undead.has_condition("invisible"), "언데드가 드러난다")
	assert_false(orc.has_condition("divine_sensed"))
	assert_true(p.has_condition("divine_sense_active"), "신성 감지: 공격 유리(BG3)")
