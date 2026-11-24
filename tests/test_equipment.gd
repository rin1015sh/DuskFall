extends "res://tests/test_case.gd"
## 장비 칸(BG3 배치, equipment.gd): 옛 명세에서 칸 만들기, 장착·해제(소지품 ↔ 칸, 양손 무기와 방패),
## 마법 무기 +1(명중·피해), 마법 갑옷·방패(AC), 보호의 반지(AC·내성), 능력치 최소값(근력·건강 19 — HP도),
## 방어의 팔찌(갑옷·방패 없을 때만), 엘프의 장화(은신 유리), 등반 장갑(능력 태그), 전투 중 갑옷 잠금, 훈련 안 된 갑옷,
## 턴 상태·잃은 HP 유지, 저장·불러오기.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Equipment := preload("res://scripts/rules/equipment.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const SaveGame := preload("res://scripts/rules/save_game.gd")


func _pc(class_id: String, lv: int = 1, extra: Dictionary = {}) -> Node:
	var spec := Builder.default_spec(class_id, lv)
	spec.merge(extra, true)
	var r := Builder.build(spec)
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func test_slots_from_old_spec_and_shield_two_handed() -> void:
	var w := {}
	var f := _pc("fighter", 1, {"weapons": {"melee": {"main": "greatsword", "off": ""}, "ranged": {"main": "javelin"}}, "shield": false})
	assert_eq(f.equipment["armor"], "chain_mail")
	assert_eq(f.equipment["melee_main"], "greatsword")
	var ac0: int = f.ac()
	f.inventory = {"shield_plus_1": 1}
	var r := Equipment.equip(w, f, "shield_plus_1")
	assert_true(r["ok"], str(r))
	assert_eq(f.equipment["melee_off"], "shield_plus_1")
	assert_eq(f.equipment["melee_main"], "", "양손 무기는 내려 소지품으로")
	assert_eq(int(f.inventory.get("greatsword", 0)), 1)
	assert_eq(f.ac(), ac0 + 3, "방패 2 + 마법 1")
	assert_true(bool(f.get_meta("shield")))
	assert_true(Equipment.unequip(w, f, "melee_off")["ok"])
	assert_eq(f.ac(), ac0)
	assert_eq(int(f.inventory["shield_plus_1"]), 1)


func test_magic_weapon_bonus_and_ring() -> void:
	var w := {}
	var f := _pc("fighter")
	f.inventory = {"longsword": 1, "longsword_plus_1": 1, "ring_of_protection": 1}
	Equipment.equip(w, f, "longsword")
	var plain := Combat.build_weapon_attack(f, f.weapon_sets["melee"]["main"])
	Equipment.equip(w, f, "longsword_plus_1")
	var magic := Combat.build_weapon_attack(f, f.weapon_sets["melee"]["main"])
	assert_eq(int(magic["bonus"]), int(plain["bonus"]) + 1, "명중 +1")
	assert_eq(magic["damage"][0]["dice"], "1d8+%d" % (f.ability_mod("str") + 1), "피해 +1")
	assert_eq(magic["weapon_id"], "longsword", "숙련·마스터리는 바탕 무기로")
	var ac0: int = f.ac()
	var save0: int = f.save_bonus("wis")
	assert_true(Equipment.equip(w, f, "ring_of_protection")["ok"])
	assert_eq(f.equipment["ring1"], "ring_of_protection")
	assert_eq(f.ac(), ac0 + 1)
	assert_eq(f.save_bonus("wis"), save0 + 1, "내성 +1")


func test_ability_minimum_and_hp() -> void:
	var w := {}
	var f := _pc("fighter")
	f.inventory = {"gauntlets_of_ogre_power": 1, "amulet_of_health": 1}
	Equipment.equip(w, f, "gauntlets_of_ogre_power")
	assert_eq(int(f.abilities["str"]), 19, "근력 19")
	f.hp -= 3
	var hp_before: int = f.hp_max
	Equipment.equip(w, f, "amulet_of_health")
	assert_eq(int(f.abilities["con"]), 19)
	assert_true(f.hp_max > hp_before, "건강 19 → 최대 HP 증가")
	assert_eq(f.hp_max - f.hp, 3, "잃은 HP는 그대로")
	Equipment.unequip(w, f, "hands")
	assert_true(int(f.abilities["str"]) < 19, "벗으면 원래대로")


func test_bracers_boots_gloves_and_training() -> void:
	var w := {}
	var wz := _pc("wizard")
	wz.inventory = {"bracers_of_defense": 1, "boots_of_elvenkind": 1, "gloves_of_swimming_and_climbing": 1, "chain_mail": 1}
	var ac0: int = wz.ac()
	Equipment.equip(w, wz, "bracers_of_defense")
	assert_eq(wz.ac(), ac0 + 2, "갑옷·방패가 없으면 +2")
	# 숙련 없는 갑옷(BG3식): 입을 수 있지만 공격·판정·내성 불리, 주문 불가
	assert_true(Equipment.equip(w, wz, "chain_mail")["ok"], "숙련 없어도 입는다")
	assert_true(wz.has_condition("armor_unproficient"))
	assert_eq(load("res://scripts/rules/spellcasting.gd").can_cast({"grid": null}, wz, "magic_missile", Vector2i.ZERO), "지금은 주문을 쓸 수 없다(숙련 없는 갑옷·분노·야생 변신)")
	Dice.force([5, 15])
	assert_eq(int(Resolver.saving_throw(wz, "wis", 10)["mode"]), -1, "내성 불리")
	Equipment.unequip(w, wz, "armor")
	assert_false(wz.has_condition("armor_unproficient"), "벗으면 풀린다")
	Equipment.equip(w, wz, "boots_of_elvenkind")
	Dice.force([5, 15])
	var r := Resolver.ability_check(wz, "dex", 10, {"skill": "stealth"})
	assert_eq(int(r["mode"]), 1, "엘프의 장화: 은신 유리")
	Dice.force([5])
	assert_eq(int(Resolver.ability_check(wz, "dex", 10, {"skill": "athletics"})["mode"]), 0, "다른 기능은 그대로")
	Equipment.unequip(w, wz, "hands")
	Equipment.equip(w, wz, "gloves_of_swimming_and_climbing")
	assert_true(wz.is_climber(), "등반 장갑: 오르기 지점 없이 오른다")
	var f := _pc("fighter")
	f.inventory = {"bracers_of_defense": 1}
	var fac: int = f.ac()
	Equipment.equip(w, f, "bracers_of_defense")
	assert_eq(f.ac(), fac, "갑옷을 입으면 팔찌 효과 없음")


func test_combat_armor_lock_keeps_turn() -> void:
	var w := make_world(["...."])
	var f := _pc("fighter")
	w["grid"].place(f, Vector2i(0, 0))
	w["turns"].start_manual([f])
	f.inventory = {"chain_mail_plus_1": 1, "longsword": 1}
	assert_eq(Equipment.equip(w, f, "chain_mail_plus_1")["reason"], "전투 중에는 갑옷을 바꿀 수 없다")
	assert_false(Equipment.unequip(w, f, "armor")["ok"])
	f.turn["action"] = 0
	assert_true(Equipment.equip(w, f, "longsword")["ok"], "무기는 전투 중에도")
	assert_eq(int(f.turn["action"]), 0, "장비를 바꿔도 턴 상태는 그대로")


func test_save_restore_keeps_equipment() -> void:
	var w := make_world(["...."])
	var f := _pc("fighter")
	f.name = "f"
	w["grid"].place(f, Vector2i(0, 0))
	f.inventory = {"cloak_of_protection": 1}
	Equipment.equip(w, f, "cloak_of_protection")
	var ac: int = f.ac()
	var text := JSON.stringify(SaveGame.snapshot(w))
	Equipment.unequip(w, f, "cloak")
	assert_true(SaveGame.restore(w, JSON.parse_string(text)))
	assert_eq(f.equipment["cloak"], "cloak_of_protection")
	assert_eq(f.ac(), ac, "착용 효과도 복원")
	assert_false(f.inventory.has("cloak_of_protection"))


## 자동 점검(새 마법 물품 자동 포함): 모든 마법 물품을 장착할 수 있는 클래스가 있고, 장착·해제가 오류 없이 된다.
func test_every_magic_item_equips() -> void:
	var w := {}
	var bad: Array = []
	var pcs: Array = []
	for cid: String in RulesDB.ids("class"):
		pcs.append(_pc(cid))
	for e: Dictionary in RulesDB.entries("item"):
		if e.get("category", "") != "magic":
			continue
		var done := false
		for c: Node in pcs:
			c.inventory[e["id"]] = 1
			var r := Equipment.equip(w, c, e["id"])
			if r.get("ok", false):
				assert_eq(c.equipment[r["slot"]], e["id"])
				assert_true(Equipment.unequip(w, c, r["slot"])["ok"])
				done = true
				break
			c.inventory.erase(e["id"])
		if not done:
			bad.append(e["id"])
	assert_eq(bad, [], "장착할 수 있는 클래스가 없는 마법 물품")


## 화면(캐릭터 창): 끌어다 놓기로 장착·벗기·넘기기, 메뉴 항목.
func test_character_sheet_drop_and_menu() -> void:
	var Sheet := preload("res://scenes/ui/character_sheet.gd")
	var a := _pc("fighter")
	var b := _pc("rogue")
	var w := {"party": [a, b]}
	a.inventory = {"ring_of_protection": 1, "rations": 2}
	var sheet: Control = Sheet.new()
	tree.root.add_child(sheet)
	own(sheet)
	sheet.show_for(w, a)
	var slot: Control = Sheet.ItemSlot.new()
	slot.kind = "slot"
	slot.slot = "ring1"
	own(slot)
	assert_true(slot.sheet == null)
	slot.sheet = sheet
	assert_true(slot._can_drop_data(Vector2.ZERO, {"kind": "inv", "item": "ring_of_protection", "slot": ""}), "반지 칸에 반지")
	assert_false(slot._can_drop_data(Vector2.ZERO, {"kind": "inv", "item": "rations", "slot": ""}), "식량은 안 들어간다")
	sheet.drop({"kind": "inv", "item": "ring_of_protection", "slot": ""}, slot)
	assert_eq(a.equipment["ring1"], "ring_of_protection", "끌어다 놓아 장착")
	var bag: Control = Sheet.ItemSlot.new()
	bag.kind = "inventory"
	bag.sheet = sheet
	own(bag)
	sheet.drop({"kind": "slot", "item": "ring_of_protection", "slot": "ring1"}, bag)
	assert_eq(a.equipment["ring1"], "", "소지품에 놓으면 벗기")
	var tab: Control = Sheet.ItemSlot.new()
	tab.kind = "member"
	tab.member = b
	tab.sheet = sheet
	own(tab)
	sheet.drop({"kind": "inv", "item": "rations", "slot": ""}, tab)
	assert_eq(int(b.inventory.get("rations", 0)), 1, "파티 탭에 놓으면 넘기기")
	var src: Control = Sheet.ItemSlot.new()
	src.kind = "inv"
	src.item = "ring_of_protection"
	src.sheet = sheet
	own(src)
	sheet.open_menu(src)
	var labels: Array = []
	for i in sheet.menu.item_count:
		labels.append(sheet.menu.get_item_text(i))
	assert_true(labels.size() >= 3, "장착·넘기기·캠프로 보내기 %s" % str(labels))
	sheet.menu.hide()


## 다용도 무기(보조 손이 비면 두 손 주사위), 갑옷 은신 불리, 근력 요구치 미달 속도 −2칸.
func test_versatile_stealth_strength() -> void:
	var w := {}
	var f := _pc("fighter", 1, {"weapons": {"melee": {"main": "longsword", "off": ""}, "ranged": {"main": "javelin"}}, "shield": false})
	assert_eq(Combat.build_weapon_attack(f, "longsword")["damage"][0]["dice"].get_slice("+", 0).get_slice("-", 0), "1d10", "두 손 롱소드 1d10")
	f.inventory = {"shield": 1}
	Equipment.equip(w, f, "shield")
	assert_eq(Combat.build_weapon_attack(f, "longsword")["damage"][0]["dice"].get_slice("+", 0).get_slice("-", 0), "1d8", "방패를 들면 1d8")
	Dice.force([10, 10])
	assert_eq(int(Resolver.ability_check(f, "dex", 10, {"skill": "stealth"})["mode"]), -1, "사슬 갑옷: 은신 불리")
	var wz := _pc("wizard")
	wz.inventory = {"plate_armor": 1}
	var sp: int = wz.speed_tiles
	Equipment.equip(w, wz, "plate_armor")
	assert_eq(wz.speed_tiles, sp - 2, "판금 근력 15 미달: −2칸")


## 화면(BG3 소지품): 검색·정렬, 파티 보기에서 다른 사람 칸으로 끌어 넘기기.
func test_inventory_search_sort_and_party_view_transfer() -> void:
	var Sheet := preload("res://scenes/ui/character_sheet.gd")
	var a := _pc("fighter")
	var b := _pc("rogue")
	var w := {"party": [a, b]}
	a.inventory = {"rations": 2, "potion_of_healing": 1, "ring_of_protection": 1}
	var sheet: Control = Sheet.new()
	tree.root.add_child(sheet)
	own(sheet)
	sheet.show_for(w, a)
	assert_eq(sheet._sorted_items(a.inventory, true)[0], "ring_of_protection", "최신(나중에 얻은 것이 앞)")
	sheet.sort_key = "value"
	assert_eq(sheet._sorted_items(a.inventory, true)[0], "ring_of_protection", "가치순")
	sheet.search = "potion"
	assert_eq(sheet._sorted_items(a.inventory, true), ["potion_of_healing"], "이름(id)로 찾기")
	sheet.search = ""
	sheet.view_mode = "party"
	sheet.show_for(w, a)
	assert_eq(sheet.body.get_child_count() - sheet.body.get_children().filter(func(n: Node) -> bool: return n.is_queued_for_deletion()).size(), 2, "파티원마다 열")
	var dst: Control = Sheet.ItemSlot.new()
	dst.kind = "inventory"
	dst.member = b
	dst.sheet = sheet
	own(dst)
	assert_true(dst._can_drop_data(Vector2.ZERO, {"kind": "inv", "item": "rations", "owner": a}), "다른 사람 칸에 놓을 수 있다")
	sheet.drop({"kind": "inv", "item": "rations", "slot": "", "owner": a}, dst)
	assert_eq(int(b.inventory.get("rations", 0)), 1, "넘기기")
	assert_eq(int(a.inventory.get("rations", 0)), 1)
