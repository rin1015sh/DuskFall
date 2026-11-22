extends "res://tests/test_case.gd"
## 몬스터 데이터와 행동(/add-monster 변환 규칙, SRD 5.2.1 원문 수치).

const MF := preload("res://scripts/rules/monster_factory.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Physics := preload("res://scripts/rules/physics.gd")
const Builder := preload("res://scripts/rules/character_builder.gd")


func _m(id: String) -> Node:
	return own(MF.spawn(id))


func _pc(class_id: String, level: int = 1) -> Node:
	return own(Builder.build(Builder.default_spec(class_id, level))["creature"])


func _world() -> Dictionary:
	return make_world(["..........", "..........", "..........", ".........."])


func test_all_monsters_spawn() -> void:
	var ids: Array = RulesDB.ids("monster")
	assert_true(ids.size() >= 15 and ids.size() <= 22, "1차 몬스터 15~20종 + 소환 형태(%d)" % ids.size())
	for id: String in ids:
		var m := _m(id)
		assert_true(m.hp_max > 0 and m.ac() > 0, id)
		assert_true(RulesDB.get_entry("monster", id)["cr"] <= 5, "%s CR 5 이하" % id)
		assert_false(MF.actions(m).is_empty(), "%s 행동" % id)


func test_stats_from_srd() -> void:
	var o := _m("ogre")
	assert_eq([o.ac(), o.hp_max, o.speed_tiles, o.size], [11, 68, 8, "large"], "오우거 AC 11, HP 68, 40피트 = 8칸, 큼")
	assert_eq(o.get_meta("cells"), 2, "큼 = 2×2칸")
	var s := _m("skeleton")
	assert_true(s.vulnerable_to("bludgeoning") and s.immune_to("poison"))
	assert_false(s.apply_condition("poisoned"), "중독 면역")
	assert_eq(_m("bandit_captain").save_bonus("dex"), 5, "원문 내성 값")


func test_multiattack() -> void:
	var w := _world()
	var boss := _m("goblin_boss")
	var f := _pc("fighter")
	w["grid"].place(boss, Vector2i(0, 0))
	w["grid"].place(f, Vector2i(1, 0))
	Dice.force([15, 3, 15, 3])
	assert_true(Combat.monster_action(w, boss, "scimitar", f)["ok"])
	assert_true(Combat.monster_action(w, boss, "scimitar", f)["ok"], "다중 공격 2회")
	assert_false(Combat.monster_action(w, boss, "scimitar", f)["ok"], "세 번째는 없다")


func test_pack_tactics() -> void:
	var w := _world()
	var a := _m("wolf")
	var b := _m("wolf")
	var f := _pc("fighter")
	w["grid"].place(a, Vector2i(0, 0))
	w["grid"].place(f, Vector2i(1, 0))
	var atk := MF.to_attack(MF.action(a, "bite"))
	assert_eq(Combat.attack_context(w, a, f, atk)["advantage"].size(), 0)
	w["grid"].place(b, Vector2i(2, 0))
	assert_eq(Combat.attack_context(w, a, f, atk)["advantage"], ["무리 전술"], "대상 옆에 아군이 있으면 유리")


func test_wolf_bite_prones_medium() -> void:
	var w := _world()
	var wolf := _m("wolf")
	var f := _pc("fighter")
	var ogre := _m("ogre")
	w["grid"].place(wolf, Vector2i(0, 0))
	w["grid"].place(f, Vector2i(1, 0))
	w["grid"].place(ogre, Vector2i(0, 2))
	Dice.force([18, 2])
	Combat.monster_action(w, wolf, "bite", f)
	assert_true(f.has_condition("prone"))
	wolf.reset_turn()
	Dice.force([18, 2])
	Combat.monster_action(w, wolf, "bite", ogre)
	assert_false(ogre.has_condition("prone"), "큰 생물은 넘어지지 않는다")


func test_ghoul_claw_paralysis_except_elves() -> void:
	var w := _world()
	var g := _m("ghoul")
	var f := _pc("fighter")
	var wiz := _pc("wizard")
	w["grid"].place(g, Vector2i(0, 0))
	w["grid"].place(f, Vector2i(1, 0))
	w["grid"].place(wiz, Vector2i(0, 1))
	Dice.force([15, 2, 3])
	Combat.monster_action(w, g, "claw", f)
	assert_true(f.has_condition("paralyzed"), "건강 DC 10 실패 → 마비")
	g.reset_turn()
	Dice.force([15, 2])
	Combat.monster_action(w, g, "claw", wiz)
	assert_false(wiz.has_condition("paralyzed"), "엘프는 면함")


func test_zombie_undead_fortitude() -> void:
	var z := _m("zombie")
	Dice.force([20])
	Resolver.apply_damage(z, [{"amount": 16, "damage_type": "slashing"}])
	assert_eq(z.hp, 1, "건강 DC 21 성공(20 + 3) → HP 1")
	Resolver.apply_damage(z, [{"amount": 5, "damage_type": "radiant"}])
	assert_true(z.dead, "광휘 피해는 끈기 없음")


func test_troll_regeneration_and_fire() -> void:
	var t := _m("troll")
	Resolver.apply_damage(t, [{"amount": 94, "damage_type": "slashing"}])
	assert_false(t.dead, "0 HP여도 재생할 수 있으면 죽지 않는다")
	Resolver.start_turn(t)
	assert_eq(t.hp, 15, "턴 시작에 15 회복")
	Resolver.apply_damage(t, [{"amount": 15, "damage_type": "fire"}])
	Resolver.start_turn(t)
	assert_true(t.dead, "화염을 받으면 다음 턴 재생하지 못하고 0 HP → 죽음")


func test_spider_web_recharge_and_escape() -> void:
	var w := _world()
	var sp := _m("giant_spider")
	var f := _pc("fighter")
	w["grid"].place(sp, Vector2i(0, 0))
	w["grid"].place(f, Vector2i(6, 0))
	Dice.force([3])
	assert_true(Combat.monster_action(w, sp, "web", f)["ok"])
	assert_true(f.has_condition("restrained"))
	assert_eq(sp.cooldowns["web"], 3, "재충전 5~6 → 3턴 쿨다운")
	sp.reset_turn()
	assert_false(Combat.monster_action(w, sp, "web", f)["ok"], "쿨다운 중")
	Dice.force([15])
	var r := Combat.escape(w, f)
	assert_true(r["success"] and not f.has_condition("restrained"), "근력 판정으로 빠져나오기")


func test_wight_life_drain() -> void:
	var w := _world()
	var wight := _m("wight")
	var f := _pc("fighter", 5)
	w["grid"].place(wight, Vector2i(0, 0))
	w["grid"].place(f, Vector2i(1, 0))
	Dice.force([2, 5])
	Combat.monster_action(w, wight, "life_drain", f)
	assert_eq(f.hp_max, 44 - 7, "최대 HP가 받은 피해만큼 준다")


func test_worg_bite_grants_advantage() -> void:
	var w := _world()
	var worg := _m("worg")
	var f := _pc("fighter")
	var rogue := _pc("rogue")
	rogue.team = "enemy"
	w["grid"].place(worg, Vector2i(0, 0), 2)
	w["grid"].place(f, Vector2i(2, 0))
	w["grid"].place(rogue, Vector2i(3, 0))
	Dice.force([18, 2])
	Combat.monster_action(w, worg, "bite", f)
	assert_eq(Resolver.preview_attack(rogue, f, {"bonus": 0, "damage": []})["mode"], 1, "다음 공격 유리")


func test_ogre_too_heavy_to_shove() -> void:
	var w := _world()
	var ogre := _m("ogre")
	var f := _pc("fighter", 5)
	w["grid"].place(f, Vector2i(0, 0))
	w["grid"].place(ogre, Vector2i(1, 0), 2)
	assert_false(Physics.plan_shove(w["grid"], f, ogre)["valid"], "300kg > 근력 19 × 12 = 228kg")


func test_monster_ai_fights() -> void:
	var w := _world()
	var boss := _m("goblin_boss")
	var f := _pc("fighter")
	w["grid"].place(boss, Vector2i(0, 0))
	w["grid"].place(f, Vector2i(5, 0))
	boss.reset_turn()
	preload("res://scripts/ai/simple_ai.gd").take_turn(w, boss)
	assert_eq(boss.turn["attacks_left"], 0, "멀리 있으면 단궁 2회")
