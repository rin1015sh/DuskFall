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
	assert_eq(Equipment.equip(w, wz, "chain_mail")["reason"], "훈련하지 않은 갑옷")
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
