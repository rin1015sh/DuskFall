extends "res://tests/test_case.gd"
## 레벨 상한 20 — 1구간(6~10레벨) 기능: 바바리안·바드·드루이드·몽크·팔라딘·레인저·소서러·워락.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Features := preload("res://scripts/rules/features.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const SpellPrep := preload("res://scripts/rules/spell_prep.gd")


func _pc(cid: String, lv: int, extra: Dictionary = {}) -> Node:
	var spec := Builder.default_spec(cid, lv)
	spec.merge(extra, true)
	var r := Builder.build(spec)
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func test_barbarian_6_10() -> void:
	var w := make_world(["......"])
	var b := _pc("barbarian", 10)
	var foe := make_creature({"team": "enemy", "hp_max": 300, "ac_base": 1})
	w["grid"].place(b, Vector2i(1, 0))
	w["grid"].place(foe, Vector2i(2, 0))
	b.reset_turn()
	b.apply_condition("frightened", 10, foe)
	var mv: int = int(b.turn["movement"])
	assert_true(Features.use(w, b, "rage")["ok"])
	assert_false(b.has_condition("frightened"), "광기 없는 분노: 공포가 끝난다")
	assert_false(b.apply_condition("charmed", 10, foe), "분노 중 매혹 면역")
	assert_true(b.has_cap("brutal_critical"), "잔혹한 치명타(BG3 — 잔혹한 일격·본능적 도약 대신)")
	Dice.force([20, 5, 5, 5, 5])
	var res := Resolver.attack(b, foe, Combat.build_weapon_attack(b, b.weapon("main")), w["grid"].attack_context(b, foe))
	assert_true(res["crit"] and res["extra_damage"].size() >= 1, "치명타 주사위 하나 더")
	assert_true(b.feature_data.has("intimidating_presence"), "광전사 10레벨: 위협적인 존재감(BG3 — 보복 대신)")


func test_bard_6_10() -> void:
	var bd := _pc("bard", 10)
	assert_true(bd.spells.has("spirit_guardians") and bd.spells.has("counterspell"), "마법의 발견 항상 준비")
	assert_true(bd.spells.has("fireball") and bd.spells.has("haste"), "마법의 비밀: 고른 2개 항상 준비(BG3)")
	assert_eq(int(bd.skill_bonuses["insight"]), bd.proficiency_bonus * 2, "10레벨 전문화")
	# 대항 매혹
	var w := make_world(["......"])
	var ally := make_creature({"team": "party", "hp_max": 30})
	w["grid"].place(bd, Vector2i(0, 0))
	w["grid"].place(ally, Vector2i(3, 0))
	bd.refresh_reaction()
	Dice.force([2, 18, 18])
	var s := Resolver.saving_throw(ally, "wis", 15, {"against_conditions": ["frightened"]})
	assert_true(s["success"], "대항 매혹: 유리하게 다시")
	assert_false(bd.can_react(), "반응을 쓴다")


func test_druid_6_10() -> void:
	var d := _pc("druid", 10)
	assert_true(d.has_cap("improved_wild_strike"), "향상된 야생의 일격(BG3 — 원소의 격노 대신)")
	assert_true("poison" in d.damage_immunities and "poisoned" in d.condition_immunities, "자연의 수호(BG3): 독 면역")
	var w := make_world(["......"])
	w["grid"].place(d, Vector2i(0, 0))
	for i in range(1, 4):
		d.resources["spell_slot_%d" % i]["current"] = 0
	assert_true(Features.use(w, d, "natural_recovery")["ok"], "자연 회복: 슬롯 회복")
	var sum := 0
	for i in range(1, 4):
		sum += d.resource("spell_slot_%d" % i) * i
	assert_eq(sum, 5, "드루이드 10레벨 절반 = 5레벨어치")


func test_monk_6_10() -> void:
	var w := make_world(["......"])
	var m := _pc("monk", 10)
	var foe := make_creature({"team": "enemy", "hp_max": 300, "ac_base": 1})
	w["grid"].place(m, Vector2i(0, 0))
	w["grid"].place(foe, Vector2i(1, 0))
	assert_eq(Combat.build_weapon_attack(m, "unarmed")["damage"][0]["damage_type"], "force", "강화된 타격")
	assert_true(m.has_cap("evasion") and m.has_cap("climber"))
	m.reset_turn()
	var r := Features.use(w, m, "flurry_of_blows", foe)
	assert_true(r["ok"])
	m.reset_turn()
	m.temp_hp = 0
	assert_true(Features.use(w, m, "patient_defense")["ok"])
	assert_true(m.temp_hp >= 2, "고양된 집중: 임시 HP")
	m.apply_condition("poisoned", 10, foe)
	w["turns"].end_turn(m)
	assert_false(m.has_condition("poisoned"), "자기 회복")
	m.hp = 10
	m.reset_turn()
	assert_true(Features.use(w, m, "wholeness_of_body")["ok"])
	assert_true(m.hp > 10, "몸의 완전함")


func test_paladin_6_10() -> void:
	var w := make_world(["........"])
	var pd := _pc("paladin", 10)
	var ally := make_creature({"team": "party", "hp_max": 30})
	var far := make_creature({"team": "party", "hp_max": 30})
	var foe := make_creature({"team": "enemy", "hp_max": 30})
	w["grid"].place(pd, Vector2i(0, 0))
	w["grid"].place(ally, Vector2i(2, 0))
	w["grid"].place(far, Vector2i(5, 0))
	w["grid"].place(foe, Vector2i(1, 0))
	var cha := maxi(1, pd.ability_mod("cha"))
	assert_eq(Resolver.Auras.save_bonus(ally), cha, "보호의 오라 2칸")
	assert_eq(Resolver.Auras.save_bonus(far), 0, "오라 밖")
	assert_eq(Resolver.Auras.save_bonus(foe), 0, "적은 없음")
	assert_false(ally.apply_condition("frightened", 10, foe), "용기의 오라")
	assert_false(ally.apply_condition("charmed", 10, foe), "헌신의 오라")
	assert_true(far.apply_condition("frightened", 10, foe))
	pd.apply_condition("incapacitated", 2)
	assert_eq(Resolver.Auras.save_bonus(ally), 0, "무력화되면 꺼진다")
	pd.remove_condition("incapacitated")
	pd.reset_turn()
	var cd: int = pd.resource("channel_divinity")
	Dice.force([1])
	assert_true(Features.use(w, pd, "abjure_foes", foe)["ok"])
	assert_eq(pd.resource("channel_divinity"), cd - 1)
	assert_true(foe.has_condition("frightened"), "적 퇴치: 공포")
	Resolver.apply_damage(foe, [{"amount": 1, "damage_type": "fire"}])
	assert_false(foe.has_condition("frightened"), "피해를 받으면 끝")


func test_ranger_6_10() -> void:
	var w := make_world(["......"])
	var r := _pc("ranger", 10)
	assert_eq(r.speed_tiles, _pc("ranger", 5).speed_tiles + 2, "방랑 +10피트")
	assert_true(r.has_cap("climber"))
	r.reset_turn()
	assert_true(Features.use(w, r, "tireless")["ok"])
	assert_true(r.temp_hp >= 1, "지치지 않음")
	# 다중 공격 방어(BG3 −4 — 자세한 것은 test_ranger_conclaves)
	var foe := make_creature({"team": "enemy", "hp_max": 30})
	w["grid"].place(r, Vector2i(0, 0))
	w["grid"].place(foe, Vector2i(1, 0))
	load("res://scripts/rules/combat.gd").attack_context(w, foe, r, {"kind": "melee"})
	assert_eq(int(load("res://scripts/rules/combat.gd").attack_context(w, foe, r, {"kind": "melee"}).get("attack_add", 0)), -4, "다중 공격 방어: 이후 공격 −4")


func test_sorcerer_warlock_6_10() -> void:
	var s := _pc("sorcerer", 10)
	assert_true("fire" in s.damage_resistances, "원소 친화 저항")
	assert_eq(Spellcasting.damage_bonus(s, RulesDB.get_entry("spell", "fire_bolt"), "fire"), s.ability_mod("cha"))
	assert_true(s.has_cap("metamagic_careful") and s.has_cap("metamagic_heightened"), "10레벨 변형 2개 더")
	var w := make_world(["...."])
	w["grid"].place(s, Vector2i(0, 0))
	s.resources["innate_sorcery"]["current"] = 0
	var sp: int = s.resource("sorcery_points")
	s.reset_turn()
	assert_true(Features.use(w, s, "innate_sorcery")["ok"], "마법의 화신: 점수 2로")
	assert_eq(s.resource("sorcery_points"), sp - 2)
	var wl := _pc("warlock", 10)
	assert_true("fire" in wl.damage_resistances, "악마의 회복력")
	var n: int = wl.resource("dark_ones_own_luck")
	assert_true(n >= 1)
	var bonus: int = wl.save_bonus("wis")
	Dice.force([5, 8])
	assert_true(Resolver.saving_throw(wl, "wis", 5 + bonus + 6)["success"], "어둠의 자의 행운 +d10")
	assert_eq(wl.resource("dark_ones_own_luck"), n - 1)
