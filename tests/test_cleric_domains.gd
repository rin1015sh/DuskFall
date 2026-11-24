extends "res://tests/test_case.gd"
## 클레릭 BG3 영역(4단계, 1레벨에 고름): 생명·새벽(빛)·앎(지식)·숲(자연)·뇌우(폭풍)·속임(기만)·전장(전쟁)·종말(죽음).

const Builder := preload("res://scripts/rules/character_builder.gd")
const Actions := preload("res://scripts/rules/actions.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Features := preload("res://scripts/rules/features.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")


func _cl(lv: int, sub: String, extra: Dictionary = {}) -> Node:
	var spec := Builder.default_spec("cleric", lv)
	spec["subclass"] = sub
	spec.merge(extra, true)
	var r := Builder.build(spec)
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func _foe(v: Dictionary = {}) -> Node:
	var d := {"team": "enemy", "ac_base": 10, "hp_max": 100, "abilities": {"str": 10, "dex": 10, "con": 10, "wis": 1, "cha": 1}}
	d.merge(v, true)
	return make_creature(d)


const CLUB := {"name": "몽둥이", "bonus": 5, "kind": "melee", "weapon": false, "damage": [{"dice": "5", "damage_type": "bludgeoning"}]}


func test_domain_spells_and_armor() -> void:
	var t := _cl(1, "tempest")
	assert_true(t.spells.has("thunderwave") and t.spells.has("fog_cloud"), "영역 주문 항상 준비")
	assert_true("heavy" in t.get_meta("armor_training") and t.weapon_proficiencies.has("martial"))
	var k := _cl(1, "knowledge", {"blessings_of_knowledge": ["arcana", "history"]})
	assert_eq(int(k.skill_bonuses["arcana"]), k.proficiency_bonus * 2, "앎의 축복: 숙련 + 전문화")


func test_warding_flare() -> void:
	var c := _cl(6, "light")
	var ally := make_creature({"team": "party", "hp_max": 30, "ac_base": 5})
	var e := _foe()
	var w := make_world([".....", "....."])
	w["grid"].place(c, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(1, 0))
	w["grid"].place(ally, Vector2i(2, 0))
	c.refresh_reaction()
	var n: int = c.resource("warding_flare")
	Dice.force([15, 15])
	var r := Resolver.attack(e, c, CLUB, w["grid"].attack_context(e, c))
	assert_true("섬광" in r["disadvantage"], "나를 노린 공격 불리")
	assert_eq(c.resource("warding_flare"), n - 1)
	c.refresh_reaction()
	Dice.force([15, 15])
	var r2 := Resolver.attack(e, ally, CLUB, w["grid"].attack_context(e, ally))
	assert_true("섬광" in r2["disadvantage"], "6레벨: 아군을 노린 공격도")


func test_radiance_preserve_charm() -> void:
	var c := _cl(2, "light")
	var e := _foe()
	var w := make_world(["......"])
	w["grid"].place(c, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(3, 0))
	c.reset_turn()
	Dice.force([1, 5, 5])
	assert_true(Features.use(w, c, "radiance_of_the_dawn")["ok"])
	assert_eq(e.hp, 100 - 10 - c.level, "2d10 + 레벨")
	var n := _cl(2, "nature")
	var beast := _foe({"creature_type": "beast"})
	var w2 := make_world(["......"])
	w2["grid"].place(n, Vector2i(0, 0))
	w2["grid"].place(beast, Vector2i(2, 0))
	n.reset_turn()
	Dice.force([1])
	assert_true(Features.use(w2, n, "charm_animals_and_plants")["ok"])
	assert_true(beast.has_condition("charmed"))


func test_tempest() -> void:
	var c := _cl(6, "tempest")
	var e := _foe()
	var w := make_world(["......"])
	w["grid"].place(c, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(1, 0))
	c.refresh_reaction()
	c.options["destructive_wrath"] = "off"
	Dice.force([15, 1, 4, 4])  # 적 명중, 민첩 내성 1, 2d8
	Combat._do_attack(w, e, c, CLUB)
	assert_eq(e.hp, 100 - 8, "폭풍의 분노 2d8")
	assert_eq(w["grid"].cell_of(e), Vector2i(3, 0), "벼락 일격: 2칸 밀림")
	# 파괴의 분노: 번개 피해 최대
	var e2 := _foe()
	w["grid"].place(e2, Vector2i(1, 0))
	c.options["destructive_wrath"] = "on"
	var cd: int = c.resource("channel_divinity")
	Dice.force([1, 1, 1])
	var res := Resolver.save_effect([e2], {"ability": "dex", "dc": 30}, [{"type": "damage", "dice": "2d8", "damage_type": "lightning"}], [], {"source": c})
	assert_eq(int(res[0]["damage"]["total"]), 16, "최대 16")
	assert_eq(c.resource("channel_divinity"), cd - 1)


func test_war() -> void:
	var c := _cl(6, "war")
	var e := _foe({"ac_base": 20})
	var w := make_world(["......"])
	w["grid"].place(c, Vector2i(0, 0))
	w["grid"].place(e, Vector2i(1, 0))
	c.reset_turn()
	var cd: int = c.resource("channel_divinity")
	var need: int = 20 - int(Combat.build_weapon_attack(c, c.weapon("main"))["bonus"]) - 5
	Dice.force([need, 3])
	var r := Combat.attack(w, c, e)
	assert_true(r["hit"], "인도된 일격 +10")
	assert_eq(c.resource("channel_divinity"), cd - 1)
	assert_eq(Actions.unavailable(w, c, "war_priest_attack"), "", "전쟁 사제 보너스 공격")


func test_death_and_trickery() -> void:
	var d := _cl(6, "death")  # 추천 빌드 갑옷은 숙련에 맞춰 바뀐다(fit_armor)
	var e := _foe({"damage_resistances": ["necrotic"]})
	var out := Resolver.apply_damage(e, [{"amount": 10, "damage_type": "necrotic"}], {"attacker": d})
	assert_eq(int(out["total"]), 10, "피할 수 없는 파괴: 사령 저항 무시")
	assert_true(d.spells.has("chill_touch"))
	var a := _foe()
	var b := _foe()
	var w := make_world(["....", "...."])
	w["grid"].place(d, Vector2i(0, 0))
	w["grid"].place(a, Vector2i(1, 0))
	w["grid"].place(b, Vector2i(0, 1))
	d.reset_turn()
	Dice.force([15, 4, 4, 15, 4, 4])
	Spellcasting.cast(w, d, "chill_touch", Vector2i(1, 0))
	assert_true(a.hp < 100 and b.hp < 100, "수확자: 한 생물 더")
	var t := _cl(6, "trickery")
	var w2 := make_world(["......"])
	w2["grid"].place(t, Vector2i(0, 0))
	t.reset_turn()
	assert_true(Features.use(w2, t, "cloak_of_shadows")["ok"])
	assert_true(t.has_condition("invisible"))
