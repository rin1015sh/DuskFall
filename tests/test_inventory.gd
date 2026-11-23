extends "res://tests/test_case.gd"
## 캐릭터별 소지품(BG3식, 사용자 결정 2026-11-23): 넘기기, 파티 전체에서 빼기(고른 캐릭터 먼저), 받는 사람(world.active),
## 캠프 보관함(보내기는 어디서나·꺼내기는 캠프에서만), 전리품은 가져간 캐릭터에게, 무게, 옛 저장(공용 가방) 옮기기.

const Interact := preload("res://scripts/rules/interact.gd")
const SaveGame := preload("res://scripts/rules/save_game.gd")


func _party(n: int) -> Dictionary:
	var w := make_world(["......"])
	var ps: Array = []
	for i in n:
		var p := make_creature({"team": "party", "hp_max": 10, "abilities": {"str": 10}})
		p.name = "p%d" % i
		w["grid"].place(p, Vector2i(i, 0))
		ps.append(p)
	w["party"] = ps
	return w


func test_per_character_count_take_transfer() -> void:
	var w := _party(2)
	var a: Node = w["party"][0]
	var b: Node = w["party"][1]
	a.inventory = {"gold": 30}
	b.inventory = {"gold": 20, "rations": 1}
	assert_eq(Interact.count(w, "gold", a), 30)
	assert_eq(Interact.count(w, "gold"), 50, "파티 전체")
	w["active"] = b
	assert_true(Interact.take(w, "gold", 25), "파티 전체에서 — 고른 캐릭터 먼저")
	assert_eq(int(b.inventory.get("gold", 0)), 0)
	assert_eq(int(a.inventory["gold"]), 25)
	assert_false(Interact.take(w, "gold", 26, a), "그 캐릭터 것만으로 모자라면 실패")
	assert_eq(int(a.inventory["gold"]), 25, "실패하면 아무것도 빼지 않는다")
	assert_true(Interact.transfer(w, b, a, "rations"))
	assert_eq(int(a.inventory["rations"]), 1)
	assert_false(b.inventory.has("rations"), "0개는 지운다")
	Interact.give(w, "potion_of_healing")
	assert_eq(int(b.inventory["potion_of_healing"]), 1, "받는 사람을 안 정하면 고른 캐릭터")


func test_camp_stash_and_loot_goes_to_looter() -> void:
	var w := _party(2)
	var a: Node = w["party"][0]
	var b: Node = w["party"][1]
	a.inventory = {"rations": 3}
	assert_true(Interact.send_to_stash(w, a, "rations", 2), "캠프로 보내기는 어디서나")
	assert_eq(Interact.stash_count(w, "rations"), 2)
	assert_false(Interact.take_from_stash(w, b, "rations"), "꺼내기는 캠프에서만")
	w["at_camp"] = true
	assert_true(Interact.take_from_stash(w, b, "rations"))
	assert_eq(int(b.inventory["rations"]), 1)
	w["grid"].place_object(Vector2i(5, 0), {"id": "chest", "loot": {"gold": 7}})
	assert_true(Interact.take_loot(w, b, Vector2i(5, 0))["ok"])
	assert_eq(int(b.inventory["gold"]), 7, "가져간 캐릭터에게")
	assert_false(a.inventory.has("gold"))


func test_weight_and_old_save_migration() -> void:
	var w := _party(1)
	var a: Node = w["party"][0]
	a.inventory = {"rations": 2}
	assert_true(absf(Interact.carried_kg(a) - 1.8) < 0.01, "식량 2개 = 1.8kg")
	assert_true(absf(Interact.capacity_kg(a) - 68.0) < 0.01, "근력 10 × 6.8kg")
	var snap: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.snapshot(w)))
	snap["world"]["inventory"] = {"gold": 9}  # 옛 저장 형식
	a.inventory = {}
	assert_true(SaveGame.restore(w, snap))
	assert_eq(int(a.inventory.get("gold", 0)), 9, "옛 공용 가방은 캐릭터에게 옮긴다")
	assert_false(w.has("inventory"))
