extends "res://tests/test_case.gd"
## 레벨 상한 20 — 1구간(6~10레벨) 기능: 전사·로그·클레릭·위저드.

const Features := preload("res://scripts/rules/features.gd")
const Builder := preload("res://scripts/rules/character_builder.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Progression := preload("res://scripts/rules/progression.gd")


func _pc(cid: String, lv: int, extra: Dictionary = {}) -> Node:
	var spec := Builder.default_spec(cid, lv)
	spec.merge(extra, true)
	var r := Builder.build(spec)
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func test_indomitable() -> void:
	var f := _pc("fighter", 9)
	assert_eq(f.resource("indomitable"), 1)
	var bonus: int = f.save_bonus("wis")
	Dice.force([2, 12])  # 실패 → 불굴: 12 + 보너스 + 9
	var s := Resolver.saving_throw(f, "wis", 15 + bonus)
	assert_true(s["success"], "불굴로 성공")
	assert_eq(f.resource("indomitable"), 0)
	Dice.force([2])
	assert_false(Resolver.saving_throw(f, "wis", 15 + bonus)["success"], "횟수가 없으면 실패")


func test_champion_7_10() -> void:
	var f := _pc("fighter", 10)
	assert_true(f.has_cap("reroll_low_damage_two_handed") and f.ac() > 0, "10레벨 추가 전투 방식(대형 무기 전투 — BG3)")
	assert_false(_pc("fighter", 9).has_cap("reroll_low_damage_two_handed"), "9레벨에는 없다")
	var f7 := _pc("fighter", 7)
	assert_true(f7.has_cap("half_proficiency_physical"), "7레벨 뛰어난 운동선수")
	var plain: int = int(Resolver.ability_check(_pc("fighter", 6), "dex", 10, {"skill": "sleight_of_hand"})["bonus"])
	assert_eq(int(Resolver.ability_check(f7, "dex", 10, {"skill": "sleight_of_hand"})["bonus"]), plain + f7.proficiency_bonus / 2, "숙련 아닌 민첩 판정에 숙련 절반")


func test_rogue_expertise_evasion_reliable() -> void:
	var r := _pc("rogue", 7)
	assert_eq(int(r.skill_bonuses["acrobatics"]), r.proficiency_bonus * 2, "6레벨 전문화")
	assert_true(r.has_cap("evasion") and r.has_cap("reliable_talent"))
	Dice.force([3])
	var c := Resolver.ability_check(r, "dex", 10 + int(r.skill_bonuses["acrobatics"]) + r.ability_mod("dex"), {"skill": "acrobatics"})
	assert_eq(int(c["total"]), 10 + int(c["bonus"]), "믿음직한 재능: 3 → 10")
	var dmg := [{"type": "damage", "dice": "8d6", "damage_type": "fire"}]
	var half := [{"type": "damage", "dice": "8d6", "damage_type": "fire", "scale": 0.5}]
	var hp: int = r.hp
	Dice.force([20])
	Resolver.save_effect([r], {"ability": "dex", "dc": 10}, dmg, half)
	assert_eq(r.hp, hp, "회피: 성공하면 피해 없음")
	Dice.force([2, 4, 4, 4, 4, 4, 4, 4, 4])
	Resolver.save_effect([r], {"ability": "dex", "dc": 30}, dmg, half)
	assert_eq(r.hp, hp - 16, "회피: 실패해도 절반")


func test_supreme_sneak() -> void:
	var w := make_world(["....."])
	var r := _pc("rogue", 9)
	assert_eq(r.resource("supreme_sneak"), 1, "BG3 최상급 은신: 짧은 휴식 1회")
	w["grid"].place(r, Vector2i(0, 0))
	r.reset_turn()
	assert_true(Features.use(w, r, "supreme_sneak")["ok"])
	assert_true(r.has_condition("invisible"), "10턴 투명")
	assert_eq(r.resource("supreme_sneak"), 0)
	var foe := make_creature({"team": "enemy", "hp_max": 200, "ac_base": 1})
	w["grid"].place(foe, Vector2i(1, 0))
	Dice.force([15, 15])
	Resolver.attack(r, foe, Combat.build_weapon_attack(r, "shortsword"), w["grid"].attack_context(r, foe))
	assert_false(r.has_condition("invisible"), "공격하면 풀린다")


func test_divine_strike_and_potent() -> void:
	var w := make_world(["....."])
	var c := _pc("cleric", 7)
	var foe := make_creature({"team": "enemy", "hp_max": 200, "ac_base": 1, "damage_resistances": ["radiant"]})
	w["grid"].place(c, Vector2i(0, 0))
	w["grid"].place(foe, Vector2i(1, 0))
	c.reset_turn()
	var atk := Combat.build_weapon_attack(c, "mace")
	Dice.force([15])
	var res := Resolver.attack(c, foe, atk, w["grid"].attack_context(c, foe))
	var extra: Array = res["extra_damage"].filter(func(p: Dictionary) -> bool: return p["dice"] == "1d8")
	assert_eq(extra.size(), 1, "신성한 일격 1d8")
	assert_eq(extra[0]["damage_type"], "necrotic", "광휘 저항이면 사령")
	Dice.force([15])
	var res2 := Resolver.attack(c, foe, atk, w["grid"].attack_context(c, foe))
	assert_eq(res2["extra_damage"].filter(func(p: Dictionary) -> bool: return p["dice"] == "1d8").size(), 0, "턴당 1회")
	var p := _pc("cleric", 7, {"blessed_strikes": "potent_spellcasting"})
	var spell := RulesDB.get_entry("spell", "sacred_flame")
	assert_eq(Spellcasting.damage_bonus(p, spell), p.ability_mod("wis"), "강력한 주문 시전")
	assert_eq(Spellcasting.damage_bonus(c, spell), 0)


func test_blessed_healer() -> void:
	var w := make_world(["....."])
	var c := _pc("cleric", 6)
	var ally := make_creature({"team": "party", "hp_max": 40})
	w["grid"].place(c, Vector2i(0, 0))
	w["grid"].place(ally, Vector2i(1, 0))
	ally.hp = 5
	c.hp = c.hp_max - 10
	c.reset_turn()
	Dice.force([4])
	assert_true(Spellcasting.cast(w, c, "healing_word", Vector2i(1, 0), {"targets": [ally]}).get("ok", false))
	assert_eq(c.hp, c.hp_max - 10 + 3, "축복받은 치유자: 2 + 1")


func test_divine_intervention() -> void:
	var w := make_world(["....."])
	var c := _pc("cleric", 10)
	var ally := make_creature({"team": "party", "hp_max": 40})
	w["grid"].place(c, Vector2i(0, 0))
	w["grid"].place(ally, Vector2i(1, 0))
	ally.hp = 5
	c.reset_turn()
	c.options["divine_intervention"] = "on"
	var before: int = c.resource("spell_slot_1")
	assert_true(Spellcasting.cast(w, c, "healing_word", Vector2i(1, 0), {"targets": [ally]}).get("ok", false))
	assert_eq(c.resource("spell_slot_1"), before, "슬롯을 쓰지 않는다")
	assert_eq(c.resource("divine_intervention"), 0)
	assert_eq(str(c.options["divine_intervention"]), "off", "한 번 쓰면 꺼진다")


func test_sculpt_and_empowered_evocation() -> void:
	var w := make_world(["..........", "..........", ".........."])
	var wz := _pc("wizard", 10)
	var ally := make_creature({"team": "party", "hp_max": 100})
	var foe := make_creature({"team": "enemy", "hp_max": 200})
	w["grid"].place(wz, Vector2i(0, 1))
	w["grid"].place(ally, Vector2i(7, 1))
	w["grid"].place(foe, Vector2i(8, 1))
	wz.reset_turn()
	var spell := RulesDB.get_entry("spell", "fireball")
	assert_eq(Spellcasting.damage_bonus(wz, spell), wz.ability_mod("int"), "강화된 방출")
	var forced: Array = [1]  # 적 내성(아군은 조각으로 굴리지 않음)
	for i in 8:
		forced.append(3)
	Dice.force(forced)
	assert_true(Spellcasting.cast(w, wz, "fireball", Vector2i(8, 1)).get("ok", false))
	assert_eq(ally.hp, 100, "주문 조각: 아군 피해 없음")
	assert_eq(foe.hp, 200 - 24 - wz.ability_mod("int"), "화염구 + 지능")


func test_level_up_fills_choices() -> void:
	var w := make_world(["...."])
	var r := _pc("rogue", 5)
	var spec: Dictionary = r.get_meta("spec").duplicate(true)
	spec.erase("expertise_6")
	Builder.reapply(r, spec)
	w["xp"] = 999999
	assert_true(Progression.level_up(w, r))
	var got: Variant = r.get_meta("spec").get("expertise_6")
	assert_true(got is Array and (got as Array).size() == 2, "6레벨 전문화 2개 자동: %s" % str(got))
