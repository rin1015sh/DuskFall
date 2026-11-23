extends RefCounted
## 장비 칸(BG3 배치, 사용자 결정 2026-11-23 — 조율 없음): 머리·망토·갑옷·장갑·신발·목걸이·반지 2·근접 주/보조·원거리 주/보조.
## 장비는 캐릭터 명세(meta spec)의 "equipment"에 두고, 생성기(character_builder.gd)가 여기서 AC·무기 묶음·능력치·착용 효과를 만든다.
## 장비를 바꾸면 명세를 고치고 생성기를 다시 적용한다(Builder.reapply — 잃은 HP·쓴 자원·턴 상태는 그대로).
##
## 아이템 데이터:
##   무기(weapons.json)·갑옷/방패(armor.json)는 그대로 칸에 들어간다.
##   마법 물품(items.json category "magic"): "slot"(head·cloak·hands·feet·amulet·ring 또는 weapon·armor·shield),
##     "base"(무기·갑옷·방패 변형이면 바탕 아이템 ID), "bonus"(무기 명중·피해 / 갑옷·방패 AC 보너스),
##     "equip"(착용 효과): {"ac", "saves", "ability_min": {능력: 값}, "caps": [...], "advantage": [효과 모델 advantage],
##                         "requires": {"no_armor", "no_shield"}}

const SLOTS := ["head", "cloak", "armor", "hands", "feet", "amulet", "ring1", "ring2",
	"melee_main", "melee_off", "ranged_main", "ranged_off"]
const ACCESSORY := {"head": ["head"], "cloak": ["cloak"], "hands": ["hands"], "feet": ["feet"], "amulet": ["amulet"],
	"ring": ["ring1", "ring2"]}


## 아이템 데이터(무기·갑옷·아이템 중 있는 것)와 종류.
static func entry(id: String) -> Dictionary:
	for kind: String in ["weapon", "armor", "item"]:
		var e := RulesDB.get_entry(kind, id)
		if not e.is_empty():
			return e
	return {}


## 마법 변형의 바탕 아이템(없으면 자신).
static func base_of(id: String) -> String:
	return str(RulesDB.get_entry("item", id).get("base", id)) if RulesDB.has_entry("item", id) else id


## weapon · armor · shield · accessory(마법 장신구, slot 값) · ""(장비가 아님)
static func kind_of(id: String) -> String:
	var b := base_of(id)
	if RulesDB.has_entry("weapon", b):
		return "weapon"
	if RulesDB.has_entry("armor", b):
		return "shield" if str(RulesDB.get_entry("armor", b)["category"]) == "shield" else "armor"
	var e := RulesDB.get_entry("item", id)
	if e.get("category", "") == "magic" and ACCESSORY.has(str(e.get("slot", ""))):
		return "accessory"
	return ""


## 이 아이템이 들어갈 수 있는 칸들.
static func slots_for(id: String) -> Array:
	match kind_of(id):
		"armor":
			return ["armor"]
		"shield":
			return ["melee_off"]
		"weapon":
			var w := RulesDB.get_entry("weapon", base_of(id))
			var ranged: bool = str(w.get("category", "")).ends_with("ranged")
			var two: bool = "two_handed" in w.get("properties", [])
			if ranged:
				return ["ranged_main"] if two else ["ranged_main", "ranged_off"]
			return ["melee_main"] if two else ["melee_main", "melee_off"]
		"accessory":
			return ACCESSORY[str(RulesDB.get_entry("item", id)["slot"])]
	return []


## 명세 → 칸(옛 명세의 armor·shield·weapons·클래스 시작 장비도 읽는다).
static func from_spec(spec: Dictionary, cls: Dictionary) -> Dictionary:
	var out := {}
	for s: String in SLOTS:
		out[s] = ""
	if spec.has("equipment"):
		for s: String in spec["equipment"]:
			if s in SLOTS:
				out[s] = str(spec["equipment"][s])
		return out
	var eq: Dictionary = cls.get("starting_equipment", {})
	out["armor"] = str(spec.get("armor", eq.get("armor", "")))
	var ws: Dictionary = spec.get("weapons", {"melee": eq.get("melee", {}), "ranged": eq.get("ranged", {})})
	out["melee_main"] = str(ws.get("melee", {}).get("main", ""))
	out["melee_off"] = str(ws.get("melee", {}).get("off", ""))
	out["ranged_main"] = str(ws.get("ranged", {}).get("main", ""))
	out["ranged_off"] = str(ws.get("ranged", {}).get("off", ""))
	if bool(spec.get("shield", eq.get("shield", false))) and out["melee_off"] == "":
		out["melee_off"] = "shield"
	return out


## 착용 효과 목록(조건이 맞는 것만): [[칸, equip 데이터, 아이템]]
static func active_effects(slots: Dictionary) -> Array:
	var armor_on := str(slots.get("armor", "")) != ""
	var shield_on := kind_of(str(slots.get("melee_off", ""))) == "shield"
	var out: Array = []
	for s: String in SLOTS:
		var id := str(slots.get(s, ""))
		if id == "":
			continue
		var e := RulesDB.get_entry("item", id)
		var eq: Dictionary = e.get("equip", {})
		var req: Dictionary = eq.get("requires", {})
		if req.get("no_armor", false) and armor_on or req.get("no_shield", false) and shield_on:
			continue  # 방어의 팔찌: 갑옷·방패가 없을 때만
		if not eq.is_empty() or e.has("bonus"):
			out.append([s, eq, e])
	return out


## 착용 능력치 최소값(오우거 힘의 건틀릿 근력 19 등).
static func ability_mins(slots: Dictionary) -> Dictionary:
	var out := {}
	for row: Array in active_effects(slots):
		var mins: Dictionary = row[1].get("ability_min", {})
		for a: String in mins:
			out[a] = maxi(int(out.get(a, 0)), int(mins[a]))
	return out


## 생성기가 부른다: 칸에서 갑옷·방패·무기 묶음을 정하고 착용 효과를 생물에 단다(수정치 source "item:<칸>").
static func apply_to(c: Node, slots: Dictionary) -> void:
	c.equipment = slots.duplicate()
	var armor := str(slots.get("armor", ""))
	var off := str(slots.get("melee_off", ""))
	c.set_meta("armor", base_of(armor) if armor != "" else "")
	c.set_meta("shield", kind_of(off) == "shield")
	c.weapon_sets = {"melee": {"main": str(slots.get("melee_main", "")), "off": "" if kind_of(off) == "shield" else off},
		"ranged": {"main": str(slots.get("ranged_main", "")), "off": str(slots.get("ranged_off", ""))}}
	for row: Array in active_effects(slots):
		var src := "item:" + str(row[0])
		var eq: Dictionary = row[1]
		var item: Dictionary = row[2]
		var k := kind_of(str(slots[row[0]]))
		var ac_add := int(eq.get("ac", 0)) + (int(item.get("bonus", 0)) if k in ["armor", "shield"] else 0)
		if ac_add != 0:
			c.extra_modifiers.append({"effect": {"type": "modify", "stat": "ac", "add": ac_add}, "source": src, "builder": true})
		if int(eq.get("saves", 0)) != 0:
			c.extra_modifiers.append({"effect": {"type": "modify", "stat": "saving_throw_flat", "add": int(eq["saves"])}, "source": src, "builder": true})
		for adv: Dictionary in eq.get("advantage", []):
			c.extra_modifiers.append({"effect": adv.duplicate(true), "source": src, "builder": true})
		c.caps.append_array(eq.get("caps", []))


static func in_combat(world: Dictionary) -> bool:
	return world.get("turns") != null and world["turns"].in_combat


## 장착할 수 없는 이유("" = 가능). slot을 비우면 알맞은 칸을 고른다.
static func equip_blocked(world: Dictionary, c: Node, id: String, slot: String = "") -> String:
	if not c.has_meta("spec"):
		return "장비를 바꿀 수 없는 생물"
	if c.has_meta("beast_form"):
		return "야생 변신 중에는 장비를 바꿀 수 없다"
	if int(c.inventory.get(id, 0)) <= 0:
		return "소지품에 없다"
	var ok := slots_for(id)
	if ok.is_empty():
		return "장비가 아니다"
	if slot != "" and not slot in ok:
		return "그 칸에 넣을 수 없다"
	var s := slot if slot != "" else pick_slot(c, id)
	if s == "armor" and in_combat(world):
		return "전투 중에는 갑옷을 바꿀 수 없다"
	return ""  # 숙련 없는 갑옷·방패도 입는다(BG3식 — 벌칙은 상태 armor_unproficient)


## 숙련 없는 갑옷·방패를 입었나(BG3식 벌칙 대상).
static func unproficient(c: Node) -> bool:
	var training: Array = c.get_meta("armor_training", [])
	for s: String in ["armor", "melee_off"]:
		var id := str(c.equipment.get(s, ""))
		var k := kind_of(id)
		if k in ["armor", "shield"] and not str(RulesDB.get_entry("armor", base_of(id))["category"]) in training:
			return true
	return false


## 장비에 따른 상태를 맞춘다: 숙련 없는 갑옷(armor_unproficient), 무게(interact.update_load).
static func sync_conditions(c: Node) -> void:
	var bad := unproficient(c)
	if bad and not c.has_condition("armor_unproficient"):
		c.apply_condition("armor_unproficient", -1, "equipment")
	elif not bad and c.has_condition("armor_unproficient"):
		c.remove_condition("armor_unproficient")
	load("res://scripts/rules/interact.gd").update_load(c)


## 알맞은 칸: 비어 있는 첫 칸, 다 차 있으면 첫 칸.
static func pick_slot(c: Node, id: String) -> String:
	var ok := slots_for(id)
	for s: String in ok:
		if str(c.equipment.get(s, "")) == "":
			return s
	return ok[0] if not ok.is_empty() else ""


## 장착: 소지품 → 칸. 칸에 있던 것과 양손 무기에 막히는 것은 소지품으로.
static func equip(world: Dictionary, c: Node, id: String, slot: String = "") -> Dictionary:
	var why := equip_blocked(world, c, id, slot)
	if why != "":
		return {"ok": false, "reason": why}
	var s := slot if slot != "" else pick_slot(c, id)
	var slots: Dictionary = c.equipment.duplicate()
	var back: Array = [str(slots.get(s, ""))]
	slots[s] = id
	var w := RulesDB.get_entry("weapon", base_of(id))
	if s in ["melee_main", "ranged_main"] and "two_handed" in w.get("properties", []):
		var other := "melee_off" if s == "melee_main" else "ranged_off"
		back.append(str(slots.get(other, "")))
		slots[other] = ""
	if s in ["melee_off", "ranged_off"]:
		var main_s := "melee_main" if s == "melee_off" else "ranged_main"
		var main := str(slots.get(main_s, ""))
		if main != "" and "two_handed" in RulesDB.get_entry("weapon", base_of(main)).get("properties", []):
			back.append(main)
			slots[main_s] = ""
	c.inventory[id] = int(c.inventory[id]) - 1
	if int(c.inventory[id]) <= 0:
		c.inventory.erase(id)
	for b: String in back:
		if b != "":
			c.inventory[b] = int(c.inventory.get(b, 0)) + 1
	_commit(c, slots)
	return {"ok": true, "slot": s}


static func unequip(world: Dictionary, c: Node, slot: String) -> Dictionary:
	if not c.has_meta("spec"):
		return {"ok": false, "reason": "장비를 바꿀 수 없는 생물"}
	var id := str(c.equipment.get(slot, ""))
	if id == "":
		return {"ok": false, "reason": "빈 칸"}
	if slot == "armor" and in_combat(world):
		return {"ok": false, "reason": "전투 중에는 갑옷을 바꿀 수 없다"}
	var slots: Dictionary = c.equipment.duplicate()
	slots[slot] = ""
	c.inventory[id] = int(c.inventory.get(id, 0)) + 1
	_commit(c, slots)
	return {"ok": true}


## 명세에 쓰고 생성기를 다시 적용한다.
static func _commit(c: Node, slots: Dictionary) -> void:
	var spec: Dictionary = c.get_meta("spec").duplicate(true)
	spec["equipment"] = slots.duplicate()
	for k: String in ["armor", "shield", "weapons"]:
		spec.erase(k)  # 옛 명세 키는 equipment로 대신한다
	load("res://scripts/rules/character_builder.gd").reapply(c, spec)
