extends "res://tests/test_case.gd"
## 모험 장비(SRD): 산·연금술사의 불·성수는 공격 하나 대신 던져 민첩 내성(8 + 민첩 + 숙련), 기름은 기름 표면,
## 마름쇠·쇠구슬은 행동으로 뿌려 표면(들어가면 내성).

const Builder := preload("res://scripts/rules/character_builder.gd")
const Actions := preload("res://scripts/rules/actions.gd")
const Combat := preload("res://scripts/rules/combat.gd")


func _rogue() -> Node:
	return own(Builder.build(Builder.default_spec("rogue", 5))["creature"])


func test_throw_replaces_attack() -> void:
	var w := make_world([".......", "......."])
	var r := _rogue()
	var foe := make_creature({"team": "enemy", "hp_max": 40, "abilities": {"dex": 1}})
	var zombie := make_creature({"team": "enemy", "hp_max": 40, "abilities": {"dex": 1}, "creature_type": "undead"})
	w["grid"].place(r, Vector2i(0, 0))
	w["grid"].place(foe, Vector2i(3, 0))
	w["grid"].place(zombie, Vector2i(3, 1))
	r.inventory = {"alchemists_fire": 1, "holy_water": 2}
	r.reset_turn()
	assert_true("throw_item:alchemists_fire" in Actions.list_for(w, r)["items"])
	Dice.force([1, 3])
	var res: Dictionary = Actions.execute(w, r, "throw_item:alchemists_fire", Vector2i(3, 0))
	assert_true(res.get("ok", false), str(res))
	assert_true(foe.hp < 40 and foe.has_condition("burning"), "화염 + 연소")
	assert_false(r.inventory.has("alchemists_fire"), "하나 썼다")
	assert_eq(int(r.turn["attacks_left"]), r.attacks_per_action - 1, "공격 하나를 썼다(남은 공격으로 계속)")
	r.reset_turn()
	Actions.execute(w, r, "throw_item:holy_water", Vector2i(3, 0))  # 언데드가 아니면 내성도 굴리지 않는다
	assert_true(foe.hp > 0 and r.inventory["holy_water"] == 1, "성수는 악마·언데드만(던지면 사라짐)")
	r.reset_turn()
	Dice.force([1, 8, 8])
	Actions.execute(w, r, "throw_item:holy_water", Vector2i(3, 1))
	assert_eq(zombie.hp, 40 - 16, "언데드 2d8 광휘")
	assert_eq(Combat.throw_gear(w, r, "acid_vial", Vector2i(3, 0))["ok"], false, "없는 것은 못 던진다")


func test_spread_and_oil() -> void:
	var w := make_world([".......", ".......", "......."])
	var r := _rogue()
	var foe := make_creature({"team": "enemy", "hp_max": 40, "abilities": {"dex": 1}})
	w["grid"].place(r, Vector2i(0, 0))
	r.inventory = {"caltrops": 1, "ball_bearings": 1, "oil_flask": 1}
	r.reset_turn()
	assert_true(Actions.execute(w, r, "spread_item:caltrops", Vector2i(1, 0)).get("ok", false))
	assert_eq(w["grid"].surface_id(Vector2i(1, 0)), "caltrops")
	r.reset_turn()
	assert_true(Actions.execute(w, r, "spread_item:ball_bearings", Vector2i(1, 1)).get("ok", false))
	assert_eq(w["grid"].surface_id(Vector2i(2, 2)), "ball_bearings", "2×2칸")
	r.reset_turn()
	assert_true(Actions.execute(w, r, "throw_item:oil_flask", Vector2i(4, 2)).get("ok", false))
	assert_eq(w["grid"].surface_id(Vector2i(4, 2)), "oil", "기름 표면")
	w["grid"].place(foe, Vector2i(1, 0))
	Dice.force([1])
	w["surfaces"].creature_entered(foe, Vector2i(1, 0))
	assert_eq(foe.hp, 39, "마름쇠: 관통 1")
	assert_true(foe.has_condition("hobbled") and foe.speed() == 0, "속도 0")
