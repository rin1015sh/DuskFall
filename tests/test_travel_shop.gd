extends "res://tests/test_case.gd"
## 맵 이동·캠프·상점(구현 어려운 것 묶음 3).

const WorldBuilder := preload("res://scripts/rules/world_builder.gd")
const Travel := preload("res://scripts/rules/travel.gd")
const Shop := preload("res://scripts/rules/shop.gd")
const Dialogue := preload("res://scripts/rules/dialogue.gd")


func _own_all(b: Dictionary) -> void:
	for n: Node in b["nodes"]:
		own(n)


func test_travel_to_camp_and_back_keeps_state() -> void:
	var b := WorldBuilder.build("fallen_watch")
	_own_all(b)
	var w: Dictionary = b["world"]
	var party: Array = b["party"]
	var gob: Node = b["foes"].filter(func(c: Node) -> bool: return c.name == "cave_gob_a")[0]
	gob.dead = true
	party[0].inventory["gold"] = 123
	w["stash"] = {"rations": 7}
	w["return_to"] = {"map": "fallen_watch", "cell": [6, 6]}
	var carry := Travel.leave(w)
	for c: Node in party:
		w["grid"].remove(c)
	var camp := Travel.enter("camp", party, carry, "camp_entry")
	_own_all(camp)
	assert_eq(camp["world"]["map_id"], "camp")
	assert_eq(int(party[0].inventory["gold"]), 123, "캐릭터가 소지품을 들고 간다")
	assert_eq(int(camp["world"]["stash"]["rations"]), 7, "캠프 보관함도 따라온다")
	assert_true(camp["world"]["grid"].creatures().has(party[0]))
	assert_eq(camp["foes"].size(), 1, "캠프지기")
	var back_carry := Travel.leave(camp["world"])
	for c: Node in party:
		camp["world"]["grid"].remove(c)
	var back := Travel.enter("fallen_watch", party, back_carry, "return")
	_own_all(back)
	var g2: Node = back["world"]["grid"]
	assert_eq(g2.cell_of(party[0]), Vector2i(6, 6), "떠난 자리로 돌아온다")
	var gob2: Node = back["foes"].filter(func(c: Node) -> bool: return c.name == "cave_gob_a")[0]
	assert_true(gob2.dead, "쓰러뜨린 적은 그대로")
	load("res://scripts/rules/spellcasting.gd").instances.clear()


func test_shop_buy_sell_stock_limit() -> void:
	var buyer := make_creature({"team": "party"})
	buyer.inventory = {"gold": 120}
	var w := {"party": [buyer]}
	var rows: Array = Shop.stock(w, "camp_quartermaster")
	assert_true(rows.size() >= 4)
	assert_eq(Shop.buy_price("camp_quartermaster", "rations"), 1, "식량 0.5gp × 2 = 1(올림)")
	assert_true(Shop.buy(w, "camp_quartermaster", "potion_of_healing")["ok"])
	assert_eq(int(buyer.inventory["gold"]), 70, "사는 캐릭터의 금화")
	assert_eq(int(buyer.inventory["potion_of_healing"]), 1)
	assert_true(Shop.sell(w, "camp_quartermaster", "potion_of_healing")["ok"])
	assert_eq(int(buyer.inventory["gold"]), 95, "되팔기 절반")
	for i in 4:
		Shop.buy(w, "camp_quartermaster", "rations")
	assert_false(Shop.buy(w, "camp_quartermaster", "rations")["ok"], "재고 제한")


func test_camp_keeper_dialogue_revive_and_shop() -> void:
	var w := make_world(["....."])
	var c := make_creature({"team": "party", "is_player_character": true, "hp_max": 10})
	var dead := make_creature({"team": "party", "is_player_character": true, "hp_max": 10})
	dead.dead = true
	w["grid"].place(c, Vector2i(0, 0))
	w["party"] = [c, dead]
	c.inventory = {"gold": 250}
	var d: RefCounted = Dialogue.start(w, "camp_keeper", c)
	d.choose(0)
	assert_false(dead.dead, "부활(200gp)")
	assert_eq(int(c.inventory["gold"]), 50)
	d.choose(0)
	d.choose(1)
	assert_eq(w["pending_ui"], {"shop": "camp_quartermaster"})
