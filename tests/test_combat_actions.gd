extends "res://tests/test_case.gd"
## 행동 경제와 공통 행동(룰북 3단계 '턴 자원', '행동 목록', 근접 위협).

const Combat := preload("res://scripts/rules/combat.gd")


func _fighter(values: Dictionary = {}) -> Node:
	var f := make_creature({"team": "party", "abilities": {"str": 16, "dex": 14}, "hp_max": 30,
		"weapon_proficiencies": ["simple", "martial"], "weapon_sets": {"melee": {"main": "longsword", "off": ""},
		"ranged": {"main": "shortbow"}}})
	f.setup(values)
	return f


func _goblin(values: Dictionary = {}) -> Node:
	var g := make_creature({"team": "enemy", "abilities": {"str": 8, "dex": 15}, "ac_base": 15, "hp_max": 50,
		"weapon_proficiencies": ["simple", "martial"], "weapon_sets": {"melee": {"main": "scimitar", "off": ""},
		"ranged": {"main": "shortbow"}}})
	g.setup(values)
	return g


func test_weapon_attack_building() -> void:
	var f := _fighter()
	var atk := Combat.build_weapon_attack(f, "longsword")
	assert_eq(atk["bonus"], 5, "근력 +3 + 숙련 2")
	assert_eq(atk["damage"][0]["dice"], "1d10+3", "다용도: 보조 손이 비면 두 손(1d10)")
	assert_eq(Combat.build_weapon_attack(f, "longsword", {"two_handed": true})["damage"][0]["dice"], "1d10+3", "다용도 양손")
	assert_eq(Combat.build_weapon_attack(f, "shortbow")["ability"], "dex", "원거리 무기는 민첩")
	var rogue := make_creature({"abilities": {"str": 10, "dex": 16}, "weapon_proficiencies": ["simple", "martial"]})
	assert_eq(Combat.build_weapon_attack(rogue, "rapier")["ability"], "dex", "교묘: 큰 쪽")
	var weak := make_creature({"abilities": {"str": 10}, "weapon_proficiencies": ["martial"]})
	assert_eq(Combat.build_weapon_attack(weak, "greatsword")["extra_disadvantage"].size(), 0, "BG3: 무거운 무기 능력치 불리 없음")
	var untrained := make_creature({"abilities": {"str": 16}, "weapon_proficiencies": ["simple"]})
	assert_eq(Combat.build_weapon_attack(untrained, "longsword")["bonus"], 3, "숙련이 없으면 숙련 보너스 없음")


func test_attack_action_and_extra_attack() -> void:
	var w := make_world(["....."])
	var f := _fighter({"attacks_per_action": 2})
	var g := _goblin()
	w["grid"].place(f, Vector2i(0, 0))
	w["grid"].place(g, Vector2i(1, 0))
	Dice.force([15, 4, 15, 4])
	assert_true(Combat.attack(w, f, g)["ok"])
	assert_eq(f.turn["action"], 0, "첫 공격이 행동을 쓴다")
	assert_eq(f.turn["attacks_left"], 1)
	assert_true(Combat.attack(w, f, g)["ok"], "추가 공격은 같은 행동")
	assert_false(Combat.attack(w, f, g)["ok"], "공격이 더 없다")


func test_extra_attack_allows_moving_between() -> void:
	var w := make_world(["......"])
	var f := _fighter({"attacks_per_action": 2})
	var a := _goblin()
	var b := _goblin()
	w["grid"].place(f, Vector2i(0, 0))
	w["grid"].place(a, Vector2i(1, 0))
	w["grid"].place(b, Vector2i(4, 0))
	Dice.force([15, 4])
	Combat.attack(w, f, a)
	a.dead = true
	w["grid"].remove(a)
	assert_true(Combat.move(w, f, Vector2i(3, 0))["ok"], "공격 사이에 이동")
	Dice.force([15, 4])
	assert_true(Combat.attack(w, f, b)["ok"])


func test_range_and_long_range() -> void:
	var w := make_world(["......................................................................"])
	var f := _fighter()
	var g := _goblin()
	w["grid"].place(f, Vector2i(0, 0))
	w["grid"].place(g, Vector2i(10, 0))
	Combat.switch_weapon_set(f)
	assert_eq(Combat.preview_attack(w, f, g)["mode"], 0, "단궁 12칸 안")
	w["grid"].move_creature(g, Vector2i(12, 0))
	assert_eq(Combat.preview_attack(w, f, g)["mode"], 0, "12칸(18m)까지 불리 없음 — BG3식, 먼 사거리 없음")
	w["grid"].move_creature(g, Vector2i(13, 0))
	assert_false(Combat.preview_attack(w, f, g)["valid"], "12칸 밖")


func test_threatened_ranged_disadvantage() -> void:
	var w := make_world([".........."])
	var archer := _fighter()
	var g := _goblin()
	var far := _goblin()
	w["grid"].place(archer, Vector2i(0, 0))
	w["grid"].place(g, Vector2i(1, 0))
	w["grid"].place(far, Vector2i(8, 0))
	Combat.switch_weapon_set(archer)
	var p := Combat.preview_attack(w, archer, far)
	assert_eq(p["mode"], -1, "인접한 적이 보고 있으면 원거리 공격 불리")
	g.apply_condition("stunned", 1)
	assert_eq(Combat.preview_attack(w, archer, far)["mode"], 0, "무력화된 적은 위협하지 않는다")


func test_dash_disengage_cost() -> void:
	var f := _fighter()
	assert_eq(f.turn["movement"], 6)
	Combat.dash(f)
	assert_eq(f.turn["movement"], 12)
	assert_false(Combat.disengage(f)["ok"], "행동이 하나뿐")


func test_help_raises_downed_ally() -> void:
	var w := make_world(["..."])
	var f := _fighter()
	var wiz := make_creature({"team": "party", "is_player_character": true, "hp_max": 7})
	w["grid"].place(f, Vector2i(0, 0))
	w["grid"].place(wiz, Vector2i(1, 0))
	Resolver_drop(wiz)
	assert_true(Combat.help(w, f, wiz)["ok"])
	assert_eq(wiz.hp, 1, "돕기 → HP 1")
	assert_false(wiz.has_condition("unconscious"))


func Resolver_drop(c: Node) -> void:
	preload("res://scripts/rules/resolver.gd").apply_damage(c, [{"amount": c.hp, "damage_type": "slashing"}])


func test_hide_requires_unseen() -> void:
	var w := make_world(["..#.."])
	var rogue := _fighter({"abilities": {"dex": 16}})
	var g := _goblin()
	w["grid"].place(rogue, Vector2i(0, 0))
	w["grid"].place(g, Vector2i(1, 0))
	assert_false(Combat.hide(w, rogue)["ok"], "적이 보고 있으면 숨을 수 없다")
	w["grid"].move_creature(g, Vector2i(4, 0))
	Dice.force([14])
	var r := Combat.hide(w, rogue)
	assert_true(r["success"], "14 + 3 = 17 ≥ 15")
	assert_eq(rogue.condition_instance("invisible")["source"], "hide")


func test_shove_is_bonus_and_free_when_blocked() -> void:
	var w := make_world(["....."])
	var f := _fighter()
	var ogre := _goblin({"weight_kg": 300.0})
	w["grid"].place(f, Vector2i(0, 0))
	w["grid"].place(ogre, Vector2i(1, 0))
	assert_false(Combat.shove(w, f, ogre)["ok"])
	assert_eq(f.turn["bonus"], 1, "밀 수 없으면 비용을 쓰지 않는다")


func test_jump() -> void:
	var w := make_world(["3300000"])
	var f := _fighter()
	var g := _goblin()
	w["grid"].place(f, Vector2i(0, 0))
	w["grid"].place(g, Vector2i(1, 0))
	assert_eq(Combat.jump_distance(f), 4, "3칸 + 근력 +3 → +1")
	Dice.force([3])
	var r := Combat.jump(w, f, Vector2i(4, 0))
	assert_true(r["ok"])
	assert_eq(f.turn["bonus"], 0)
	assert_eq(f.turn["movement"], 4, "이동 2칸 소모")
	assert_eq(r["fall"]["dice"], 1, "3단계 아래로 착지 → 1d6")
	assert_eq(g.turn["reaction"], 1, "점프는 기회 공격을 유발하지 않는다")


func test_dip_coats_weapon() -> void:
	var w := make_world(["..."])
	var f := _fighter()
	w["grid"].place(f, Vector2i(0, 0))
	assert_false(Combat.dip(w, f)["ok"])
	w["surfaces"].place_surface([Vector2i(1, 0)], "poison")
	var r := Combat.dip(w, f)
	assert_eq(r["damage_type"], "poison")
	assert_true(f.has_condition("coated_weapon"))


func test_drink_and_feed_potion() -> void:
	var w := make_world(["..."])
	var f := _fighter({"hp": 10})
	var ally := _fighter({"hp": 10})
	w["grid"].place(f, Vector2i(0, 0))
	w["grid"].place(ally, Vector2i(1, 0))
	Dice.force([2, 2])
	Combat.drink_potion(f, [{"type": "heal", "dice": "2d4+2"}])
	assert_eq(f.turn["bonus"], 0, "마시기는 보너스 행동")
	assert_eq(f.hp, 16)
	Dice.force([1, 1])
	Combat.drink_potion(f, [{"type": "heal", "dice": "2d4+2"}], ally, w)
	assert_eq(f.turn["action"], 0, "먹이기는 행동")
	assert_eq(ally.hp, 14)


func test_free_interaction_once() -> void:
	var f := _fighter()
	assert_eq(Combat.interact(f)["cost"], "free")
	assert_eq(Combat.interact(f)["cost"], "action", "두 번째부터 행동")
	assert_false(Combat.interact(f)["ok"])


func test_throw_object() -> void:
	var w := make_world(["....."])
	var f := _fighter()
	var g := _goblin({"weight_kg": 20.0})
	w["grid"].place(f, Vector2i(0, 0))
	w["grid"].place(g, Vector2i(2, 0))
	Dice.force([18, 3])
	var r := Combat.throw_object(w, f, g, 12.0)
	assert_true(r["hit"])
	assert_eq(g.hp, g.hp_max - 3, "10~50kg → 1d4(공격 한 번으로 — 치명타 두 배)")
	assert_true(r["throw"]["pushed"], "대상 무게 절반 초과 → 1칸")


func test_stand_up_costs_half_speed() -> void:
	var f := _fighter()
	f.apply_condition("prone", -1)
	assert_true(Combat.stand_up(f)["ok"])
	assert_eq(f.turn["movement"], 3, "속도 6의 절반")
	assert_false(f.has_condition("prone"))
