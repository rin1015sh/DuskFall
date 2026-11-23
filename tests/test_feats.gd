extends "res://tests/test_case.gd"
## BG3 재주(수치형 묶음 A — 사용자 결정 2026-11-23). 재주는 능력치 향상 칸(asi)에서 고른다. 출신 재주 없음.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Rest := preload("res://scripts/rules/rest.gd")


## 전사 12레벨(능력치 향상 4·6·8·12)에 재주를 꽂는다
func _f(feats: Dictionary, extra: Dictionary = {}, cls: String = "fighter", lv: int = 12) -> Node:
	var spec := Builder.default_spec(cls, lv)
	spec["asi"] = feats
	spec.merge(extra, true)
	var r := Builder.build(spec)
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func _errors(feats: Dictionary, cls: String = "fighter", lv: int = 12) -> Array:
	var spec := Builder.default_spec(cls, lv)
	spec["asi"] = feats
	return Array(Builder.validate(spec))


func _foe(v: Dictionary = {}) -> Node:
	var d := {"team": "enemy", "ac_base": 5, "hp_max": 80, "abilities": {"dex": 10, "con": 10}}
	d.merge(v, true)
	return make_creature(d)


func test_no_origin_feats() -> void:
	var c: Node = Builder.build(Builder.default_spec("fighter", 1))["creature"]
	own(c)
	assert_eq(c.initiative_bonus, 0)
	assert_false(c.features.has("alert") or c.features.has("savage_attacker"), "배경이 재주를 주지 않는다")


func test_alert_tough_actor_resilient() -> void:
	var base: Node = Builder.build(Builder.default_spec("fighter", 12))["creature"]
	own(base)
	var c := _f({"4": {"feat": "alert"}, "6": {"feat": "tough"}, "8": {"feat": "actor"}, "12": {"feat": "resilient_wis"}})
	assert_eq(c.initiative_bonus, 5, "경계 +5")
	assert_true(c.has_cap("surprise_immune"))
	assert_eq(c.hp_max - base.hp_max, 24 - (base.ability_mod("con") - c.ability_mod("con")) * 12, "강골 +2 × 12")
	assert_eq(int(c.skill_bonuses["deception"]), c.proficiency_bonus * 2, "무대 체질: 기만 전문화")
	assert_eq(int(c.abilities["cha"]), int(base.abilities["cha"]) + 1, "매력 +1")
	assert_true("wis" in c.save_proficiencies, "단단한 의지: 지혜 내성")
	assert_eq(int(c.abilities["wis"]), int(base.abilities["wis"]) + 1)


func test_ability_choice_validation() -> void:
	assert_true(_errors({"4": {"feat": "lightly_armoured", "dex": 1}}).is_empty(), "근력·민첩 중 +1")
	assert_false(_errors({"4": {"feat": "lightly_armoured", "int": 1}}).is_empty(), "지능은 안 된다")
	assert_false(_errors({"4": {"feat": "lightly_armoured"}}).is_empty(), "+1을 골라야 한다")
	assert_false(_errors({"4": {"feat": "tough", "str": 1}}).is_empty(), "고르는 상승 없는 재주")
	assert_false(_errors({"4": {"feat": "archery"}}).is_empty(), "전투 방식은 능력치 향상 칸에서 못 고른다")
	assert_false(_errors({"4": {"feat": "tough"}, "6": {"feat": "tough"}}).is_empty(), "같은 재주 두 번")
	assert_false(_errors({"4": {"feat": "heavily_armoured"}}, "wizard", 4).is_empty(), "중형 갑옷 숙련이 필요")
	assert_true(_errors({"4": {"feat": "moderately_armoured", "str": 1}, "8": {"feat": "heavily_armoured"}}, "rogue", 8).is_empty(), "앞 재주가 준 숙련으로 조건 충족")


func test_armour_feats() -> void:
	var w := _f({"4": {"feat": "lightly_armoured", "dex": 1}, "8": {"feat": "moderately_armoured", "dex": 1}, "12": {"feat": "heavily_armoured"}},
		{"armor": "", "shield": false, "weapons": {"melee": {"main": "quarterstaff", "off": ""}, "ranged": {"main": ""}}}, "wizard", 12)
	var tr: Array = w.get_meta("armor_training")
	assert_true("light" in tr and "medium" in tr and "shield" in tr and "heavy" in tr)
	var m := _f({"4": {"feat": "medium_armour_master"}}, {"armor": "half_plate_armor", "shield": false,
		"scores": {"str": 10, "dex": 15, "con": 14, "int": 8, "wis": 12, "cha": 10}, "bonus": {"dex": 2, "con": 1}})
	assert_eq(m.ac(), 15 + 3 + 1, "반판갑 15 + 민첩 3(숙달) + 방어 1")
	assert_eq(int(Resolver.ability_check(m, "dex", 10, {"skill": "stealth"})["mode"]), 0, "은신 불리 없음")


func test_heavy_armour_master() -> void:
	var t := _f({"4": {"feat": "heavy_armour_master"}}, {"armor": "plate_armor"})
	var a := _foe({"team": "enemy"})
	var w := make_world(["....."])
	w["grid"].place(a, Vector2i(0, 0))
	w["grid"].place(t, Vector2i(1, 0))
	var atk := {"name": "몽둥이", "bonus": 30, "kind": "melee", "weapon": false, "damage": [{"dice": "5", "damage_type": "bludgeoning"}]}
	Dice.force([15])
	var hp: int = t.hp
	Resolver.attack(a, t, atk, w["grid"].attack_context(a, t))
	assert_eq(hp - t.hp, 2, "5 − 3")


func test_savage_dueling_twf() -> void:
	var d := _f({}, {"fighting_style": "dueling", "shield": true}, "fighter", 1)
	var atk: Dictionary = Combat.build_weapon_attack(d, "longsword")
	assert_eq(str(atk["damage"][0]["dice"]), "1d8+%d" % (d.ability_mod("str") + 2), "결투: 한 손 롱소드(방패는 괜찮다) + 2")
	d.set_meta("shield", false)
	assert_eq(str(Combat.build_weapon_attack(d, "longsword")["damage"][0]["dice"]), "1d10+%d" % d.ability_mod("str"), "다른 손이 비면 두 손 잡이(다용도) — 결투 없음")


func test_mobile_and_athlete() -> void:
	var base: Node = Builder.build(Builder.default_spec("fighter", 4))["creature"]
	own(base)
	var c := _f({"4": {"feat": "mobile"}}, {}, "fighter", 4)
	assert_eq(c.speed_tiles, base.speed_tiles + 2, "날랜 발 +2칸")
	var a := _f({"4": {"feat": "athlete", "str": 1}}, {}, "fighter", 4)
	a.reset_turn()
	a.apply_condition("prone", -1)
	var mv: int = a.turn["movement"]
	assert_true(Combat.stand_up(a)["ok"])
	assert_eq(int(a.turn["movement"]), mv - 1, "일어서기 1칸")
	assert_eq(Combat.jump_distance(a), floori(Combat.jump_distance(base) * 1.5))
	# 치고 빠지기: 근접 공격한 대상은 기회 공격을 못 한다
	var w := make_world([".....", "....."])
	var e := _foe({"abilities": {"dex": 10, "con": 10, "str": 10}})
	e.weapon_sets = {"melee": {"main": "club", "off": ""}}
	w["grid"].place(c, Vector2i(1, 0))
	w["grid"].place(e, Vector2i(2, 0))
	c.reset_turn()
	e.refresh_reaction()
	Dice.force([2])
	Combat.attack(w, c, e)
	Combat.move(w, c, Vector2i(0, 1))
	assert_true(e.can_react(), "기회 공격을 쓰지 않았다")


func test_durable_short_rest() -> void:
	var c := _f({"4": {"feat": "durable"}}, {}, "fighter", 4)
	c.hp = 1
	var world := make_world(["..."])
	world["grid"].place(c, Vector2i(0, 0))
	world["party"] = [c]
	Rest.short_rest(world, [c])
	assert_eq(c.hp, c.hp_max, "짧은 휴식에 전부")


func test_elemental_adept() -> void:
	var c := _f({"4": {"feat": "elemental_adept_fire"}, "8": {"feat": "magic_initiate_sorcerer"}}, {"magic_initiate_sorcerer": {"cantrips": ["fire_bolt", "light"], "spells": ["burning_hands"]}}, "fighter", 8)
	var e := _foe({"damage_resistances": ["fire"]})
	var out := Resolver.apply_damage(e, [{"amount": 10, "damage_type": "fire"}], {"attacker": c})
	assert_eq(int(out["total"]), 10, "화염 저항 무시")
	var w := make_world(["......"])
	w["grid"].place(c, Vector2i(0, 0))
	var e2 := _foe()
	w["grid"].place(e2, Vector2i(3, 0))
	c.reset_turn()
	Dice.force([15, 1, 1])
	Spellcasting.cast(w, c, "fire_bolt", Vector2i(3, 0))
	assert_eq(e2.hp, 80 - 4, "주사위 1은 2로(8레벨 화염탄 2d10)")
	assert_eq(Spellcasting.ability_for(c, "fire_bolt"), "cha", "마법 입문(소서러): 매력")


func test_trap_sense() -> void:
	var c := _f({"4": {"feat": "dungeon_delver"}}, {}, "fighter", 4)
	var res := Resolver.save_effect([c], {"ability": "dex", "dc": 30}, [{"type": "damage", "dice": "10", "damage_type": "piercing"}], [], {"trap": true})
	assert_eq(int(res[0]["save"]["mode"]), 1, "함정 내성 유리")
	assert_eq(int(res[0]["damage"]["total"]), 5, "함정 피해 저항")


func test_spell_sniper_ritual_weapon_master_skilled() -> void:
	var c := _f({"4": {"feat": "spell_sniper"}, "6": {"feat": "ritual_caster"}, "8": {"feat": "weapon_master", "str": 1}, "12": {"feat": "skilled"}},
		{"spell_sniper": ["fire_bolt"], "ritual_caster": ["longstrider", "jump"], "weapon_master": ["blowgun"], "skilled": ["arcana", "history", "religion"]})
	assert_true(c.spells.has("fire_bolt"))
	assert_true(c.spells.has("longstrider") and "longstrider" in c.get_meta("at_will"), "의식 주문가: 슬롯 없이")
	assert_true(c.skill_bonuses.has("arcana") and c.skill_bonuses.has("religion"), "숙련 3개")
	var w := make_world(["......"])
	var e := _foe({"ac_base": 30})
	w["grid"].place(c, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(3, 0))
	c.reset_turn()
	Dice.force([19, 5])
	var r: Dictionary = Spellcasting.cast(w, c, "fire_bolt", Vector2i(3, 0))
	assert_true(e.hp < 80, "19에서 치명타(주문 저격) %s" % str(r))


func test_brawler_and_crossbow() -> void:
	var c := _f({"4": {"feat": "tavern_brawler", "str": 1}, "8": {"feat": "crossbow_expert"}}, {}, "fighter", 8)
	var un: Dictionary = Combat.build_weapon_attack(c, "unarmed")
	var s: int = c.ability_mod("str")
	assert_eq(int(un["bonus"]), s + c.proficiency_bonus + s, "맨손 명중에 근력 한 번 더")
	assert_eq(str(un["damage"][0]["dice"]), str(1 + 2 * s), "맨손 피해 1 + 근력 × 2")
	var w := make_world(["....."])
	var e := _foe()
	w["grid"].place(c, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(1, 0))
	var atk := Combat.build_weapon_attack(c, "light_crossbow")
	assert_false("근접 위협" in Combat.attack_context(w, c, e, atk)["disadvantage"], "석궁 명수")


# ---------- 묶음 B: 켜고 끄는·반응 재주 ----------

const Actions := preload("res://scripts/rules/actions.gd")


func _arena(rows: Array = [".......", ".......", "......."]) -> Dictionary:
	return make_world(rows)


func _brute(v: Dictionary = {}) -> Node:
	var d := {"team": "enemy", "ac_base": 10, "hp_max": 100, "abilities": {"str": 14, "dex": 10, "con": 10},
		"proficiency_bonus": 2, "weapon_proficiencies": ["simple", "martial"], "weapon_sets": {"melee": {"main": "club", "off": ""}}}
	d.merge(v, true)
	return make_creature(d)


func test_great_weapon_master() -> void:
	var c := _f({"4": {"feat": "great_weapon_master"}}, {"shield": false, "weapons": {"melee": {"main": "greatsword", "off": ""}, "ranged": {"main": ""}}}, "fighter", 4)
	var off: Dictionary = Combat.build_weapon_attack(c, "greatsword")
	c.options["great_weapon_master"] = "on"
	var on: Dictionary = Combat.build_weapon_attack(c, "greatsword")
	assert_eq(int(on["bonus"]), int(off["bonus"]) - 5, "명중 −5")
	assert_eq(int(on["flat_damage"]), 10, "피해 +10")
	assert_true(Actions.passives(c).any(func(p: Dictionary) -> bool: return p["id"] == "great_weapon_master"), "상시 설정")
	var w := _arena()
	var e := _brute()
	w["grid"].place(c, Vector2i(1, 1))
	w["grid"].place(e, Vector2i(2, 1))
	c.reset_turn()
	assert_eq(Actions.unavailable(w, c, "bonus_weapon_attack"), "지금은 쓸 수 없다")
	Dice.force([20, 1, 1, 1, 1])
	Combat.attack(w, c, e)
	assert_true(c.turn.get("bonus_attack_ready", false), "치명타 → 추가 공격")
	assert_eq(Actions.unavailable(w, c, "bonus_weapon_attack"), "")
	Dice.force([15, 3, 3])
	assert_true(Actions.execute(w, c, "bonus_weapon_attack", Vector2i(2, 1))["ok"])
	assert_eq(int(c.turn["bonus"]), 0)


func test_sharpshooter_low_ground() -> void:
	var c := _f({"4": {"feat": "sharpshooter"}}, {"weapons": {"melee": {"main": "longsword", "off": ""}, "ranged": {"main": "longbow"}}}, "fighter", 4)
	c.options["sharpshooter"] = "on"
	var atk: Dictionary = Combat.build_weapon_attack(c, "longbow")
	assert_eq(int(atk["flat_damage"]), 10)
	var w := make_world(["0000000", "0002000"])
	var e := _brute()
	w["grid"].place(c, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(3, 1))
	c.active_set = "ranged"
	var p: Dictionary = Combat.preview_attack(w, c, e, {"weapon": "longbow"})
	assert_false(p.get("high_ground", 0) < 0, "낮은 곳 −2 없음")


func test_polearm_master() -> void:
	var c := _f({"4": {"feat": "polearm_master"}}, {"shield": false, "weapons": {"melee": {"main": "spear", "off": ""}, "ranged": {"main": ""}}}, "fighter", 4)
	var w := make_world([".......", "......."])
	var e := _brute()
	w["grid"].place(c, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(1, 0))
	c.reset_turn()
	Dice.force([15, 3])
	Combat.attack(w, c, e)
	assert_true(c.turn.get("haft_ready", false))
	Dice.force([15, 2])
	var hp: int = e.hp
	var r: Dictionary = Actions.execute(w, c, "haft_strike", Vector2i(1, 0))
	assert_true(r["ok"])
	assert_eq(hp - e.hp, 2 + maxi(c.ability_mod("str"), c.ability_mod("dex")), "1d4 타격 + 수정치")
	# 도달 안으로 들어오면 기회 공격
	var w2 := make_world([".......", "......."])
	var m := _brute()
	w2["grid"].place(c, Vector2i(0, 0))
	w2["grid"].place(m, Vector2i(4, 0))
	c.refresh_reaction()
	m.reset_turn()
	Dice.force([15, 3])
	Combat.move(w2, m, Vector2i(1, 0))
	assert_false(c.can_react(), "들어오는 적에게 반응 기회 공격")


func test_sentinel() -> void:
	var c := _f({"4": {"feat": "sentinel"}}, {}, "fighter", 4)
	var ally := make_creature({"team": "party", "hp_max": 30, "ac_base": 5})
	var e := _brute()
	var w := _arena()
	w["grid"].place(c, Vector2i(1, 1))
	w["grid"].place(e, Vector2i(2, 1))
	w["grid"].place(ally, Vector2i(3, 1))
	c.refresh_reaction()
	e.reset_turn()
	Dice.force([15, 3, 15, 4])  # 적이 아군을 침, 파수 반격
	var hp: int = e.hp
	Combat.attack(w, e, ally)
	assert_false(c.can_react(), "파수: 반응으로 반격")
	assert_true(e.hp < hp)
	# 기회 공격: 유리, 맞히면 이동 멈춤
	c.refresh_reaction()
	e.reset_turn()
	Dice.force([2, 15, 3])
	Combat.move(w, e, Vector2i(5, 1))
	assert_eq(w["grid"].cell_of(e), Vector2i(2, 1), "파수 기회 공격(유리 2·15 → 15)이 맞아 그 자리에 멈췄다")
	assert_false(c.can_react())


func test_war_caster_and_mage_slayer() -> void:
	var c := _f({"4": {"feat": "war_caster"}, "6": {"feat": "mage_slayer"}}, {}, "fighter", 6)
	assert_true(c.has_cap("concentration_advantage"))
	c.concentration = {"spell": "bless"}
	var cres := Resolver.concentration_check(c, 10)
	assert_eq(int(cres["mode"]), 1, "집중 유지 유리")
	var foe := _brute()
	foe.concentration = {"spell": "bless"}
	assert_eq(int(Resolver.concentration_check(foe, 10, c)["mode"]), -1, "마법사 사냥꾼이 맞힌 적: 집중 불리")
	# 곁에서 주문을 쓰면 반응 공격
	var w := _arena()
	var mage := _brute({"spellcasting_ability": "int", "spells": ["fire_bolt"], "abilities": {"str": 10, "dex": 10, "con": 10, "int": 16}})
	w["grid"].place(c, Vector2i(1, 1))
	w["grid"].place(mage, Vector2i(2, 1))
	c.refresh_reaction()
	mage.reset_turn()
	Dice.force([15, 3, 1, 1])
	Spellcasting.cast(w, mage, "fire_bolt", Vector2i(1, 1))
	assert_false(c.can_react(), "마법사 사냥꾼: 시전자에게 반응 공격")
	# 전투 시전자: 기회 공격 대신 전격 손길
	var w2 := _arena()
	var runner := _brute()
	w2["grid"].place(c, Vector2i(1, 1))
	w2["grid"].place(runner, Vector2i(2, 1))
	c.options["war_caster"] = "on"
	c.refresh_reaction()
	runner.reset_turn()
	Dice.force([15, 4])
	Combat.move(w2, runner, Vector2i(5, 1))
	assert_false(c.can_react())
	assert_true(Dice.roll_log.any(func(l: Dictionary) -> bool: return "Shocking Grasp" in str(l.get("text", ""))), "전격 손길")


func test_defensive_duellist_and_protection() -> void:
	var c := _f({"4": {"feat": "defensive_duellist"}}, {"shield": false, "weapons": {"melee": {"main": "rapier", "off": ""}, "ranged": {"main": ""}}}, "fighter", 4)
	var e := _brute()
	var w := _arena()
	w["grid"].place(c, Vector2i(1, 1))
	w["grid"].place(e, Vector2i(2, 1))
	c.refresh_reaction()
	var atk := {"name": "몽둥이", "bonus": 0, "kind": "melee", "weapon": false, "damage": [{"dice": "5", "damage_type": "bludgeoning"}]}
	Dice.force([c.ac()])  # 딱 맞는 명중
	var r := Resolver.attack(e, c, atk, w["grid"].attack_context(e, c))
	assert_false(r["hit"], "막아내기 검술: AC + 숙련으로 빗나감")
	assert_false(c.can_react())
	# 보호: 방패를 든 전사 곁의 아군을 노린 공격이 불리
	var p := _f({}, {"fighting_style": "protection", "shield": true}, "fighter", 1)
	var ally := make_creature({"team": "party", "hp_max": 30, "ac_base": 5})
	var e2 := _brute()
	var w2 := _arena()
	w2["grid"].place(p, Vector2i(1, 1))
	w2["grid"].place(ally, Vector2i(2, 1))
	w2["grid"].place(e2, Vector2i(3, 1))
	p.refresh_reaction()
	Dice.force([15, 3, 3])
	var r2 := Resolver.attack(e2, ally, atk, w2["grid"].attack_context(e2, ally))
	assert_true("보호" in r2["disadvantage"], "보호: 불리")


func test_shield_master_and_lucky() -> void:
	var c := _f({"4": {"feat": "shield_master"}, "6": {"feat": "lucky"}}, {"shield": true}, "fighter", 6)
	var base := Resolver.preview_save_fail(c, "dex", 15)
	assert_true(c.resource("luck_points") == 3, "행운 점수 3")
	var w := _arena()
	w["grid"].place(c, Vector2i(1, 1))
	c.refresh_reaction()
	c.options["lucky"] = "off"
	var res := Resolver.save_effect([c], {"ability": "dex", "dc": 40}, [{"type": "damage", "dice": "10", "damage_type": "fire"}], [], {"magic": true})
	assert_eq(int(res[0]["damage"]["total"]), 5, "방패 달인: 실패해도 절반")
	assert_false(c.can_react())
	assert_true(base < 1.0)
	c.options["lucky"] = "on"
	Dice.force([2, 18])
	var s := Resolver.saving_throw(c, "wis", 15)
	assert_true(s["success"], "행운의 별: 다시 굴려 좋은 쪽")
	assert_eq(c.resource("luck_points"), 2)
	# 적의 명중을 다시 굴리게 한다
	var e := _brute()
	w["grid"].place(e, Vector2i(2, 1))
	var atk := {"name": "몽둥이", "bonus": 0, "kind": "melee", "weapon": false, "damage": [{"dice": "5", "damage_type": "bludgeoning"}]}
	Dice.force([19, 1])
	var r := Resolver.attack(e, c, atk, w["grid"].attack_context(e, c))
	assert_false(r["hit"], "다시 굴린 1")
	assert_eq(c.resource("luck_points"), 1)


func test_charger() -> void:
	var c := _f({"4": {"feat": "charger"}}, {}, "fighter", 4)
	var e := _brute()
	var w := make_world([".........", "........."])
	w["grid"].place(c, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(5, 0))
	c.reset_turn()
	var mv: int = c.turn["movement"]
	Dice.force([15, 4])
	var hp: int = e.hp
	var r: Dictionary = Actions.execute(w, c, "charger_attack", Vector2i(5, 0))
	assert_true(r.get("hit", false), str(r))
	assert_eq(w["grid"].cell_of(c), Vector2i(4, 0), "곧게 달려가 붙었다")
	assert_eq(hp - e.hp, 4 + c.ability_mod("str") + 5, "피해 +5")
	assert_eq(int(c.turn["movement"]), mv, "이동력은 쓰지 않는다")
	assert_eq(int(c.turn["bonus"]), 0, "보너스 행동도 쓴다")
