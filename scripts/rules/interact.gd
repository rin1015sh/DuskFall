extends RefCounted
## 함정·자물쇠·살펴보기(룰북 5단계 '함정·자물쇠·살펴보기', 2단계 보이는 굴림). 상태 없음 — 상태는 world에.
##   world["traps"]: [{"id","cell","dc_find","dc_disarm","save":{"ability","dc"},"effects":[...],"radius","state":"armed|disarmed|spent",
##                     "found": bool, "checked": {생물: true}, "retry_blocked": bool}]
##   world["examines"]: [{"id","cell","ability","skill","dc","success":{...},"fail":{...},"done": bool}]
##   world["inventory"]: {아이템 ID: 개수, "gold": n}
## 자물쇠는 물체의 "lock": {"dc", "key", "locked"}.
## 도구 숙련은 없다 — 자물쇠·함정은 손재주(민첩)로 통일(5단계 결정 1).

const Resolver := preload("res://scripts/rules/resolver.gd")
const Area := preload("res://scripts/rules/area.gd")
const Stealth := preload("res://scripts/rules/stealth.gd")
const Goals := preload("res://scripts/rules/goals.gd")

## 함정 자동 지각 반경(5단계: 3칸, 함정마다 캐릭터별 1회)
const PERCEIVE_TILES := 3
const THIEVES_TOOLS := "thieves_tools"
const DISARM_KIT := "trap_disarm_kit"


# ---------- 소지품 ----------

static func count(world: Dictionary, item: String) -> int:
	return int(world.get("inventory", {}).get(item, 0))


static func give(world: Dictionary, item: String, n: int = 1) -> void:
	if not world.has("inventory"):
		world["inventory"] = {}
	world["inventory"][item] = count(world, item) + n


static func take(world: Dictionary, item: String, n: int = 1) -> bool:
	if count(world, item) < n:
		return false
	world["inventory"][item] = count(world, item) - n
	return true


# ---------- 함정 ----------

## 파티원이 칸에 들어가면: 3칸 안 함정 자동 지각(캐릭터마다 1회), 무장된 함정 칸이면 발동.
static func on_party_enter(world: Dictionary, c: Node) -> void:
	var grid: Node = world["grid"]
	for t: Dictionary in world.get("traps", []):
		if t["state"] != "armed":
			continue
		var cell := Vector2i(int(t["cell"][0]), int(t["cell"][1]))
		if not t.get("found", false) and grid.distance(grid.cell_of(c), cell) <= PERCEIVE_TILES:
			if not t.has("checked"):
				t["checked"] = {}
			if not t["checked"].has(c.name):
				t["checked"][c.name] = true
				var r := Resolver.ability_check(c, "wis", int(t["dc_find"]), {"skill": "perception"})
				if r["success"]:
					t["found"] = true
					Dice.log_text("%s가 함정을 찾았다: %s" % [c.label(), t.get("id", "")])
		if cell in grid.occupied_cells(c):
			trigger(world, t, c)


## 함정 발동: 내성 효과를 범위(반경) 안 생물에게. 물건을 던지거나 공격으로 일부러 발동시킬 수도 있다.
static func trigger(world: Dictionary, t: Dictionary, by: Node = null) -> void:
	if t["state"] != "armed":
		return
	t["state"] = "spent"
	var grid: Node = world["grid"]
	var cell := Vector2i(int(t["cell"][0]), int(t["cell"][1]))
	var cells := Area.circle(grid, cell, int(t.get("radius", 0)))
	var targets := Area.creatures_in(grid, cells)
	Dice.log_text("함정 발동: %s" % t.get("id", ""))
	var save: Dictionary = t.get("save", {})
	var fail: Array = t.get("effects", [])
	var success: Array = []
	for e: Dictionary in fail:
		if e["type"] == "damage" and t.get("half_on_save", true):
			var h := e.duplicate()
			h["scale"] = 0.5
			success.append(h)
	if save.is_empty():
		Resolver.save_effect(targets, {}, fail, [], {"in_combat": not EventBus.realtime})
	else:
		Resolver.save_effect(targets, {"ability": save["ability"], "dc": int(save["dc"])}, fail, success, {"in_combat": not EventBus.realtime})
	for e: Dictionary in fail:
		if e["type"] == "create_surface" and world.get("surfaces") != null:
			world["surfaces"].place_surface(cells, e["id"])


## 함정 해제(보이는 굴림, 손재주): 함정 해체 도구가 필요. 성공하면 도구가 남고, 실패하면 도구 소모 + 함정 발동.
## 같은 함정은 새 도구로 다시 시도할 수 없다 — 재시도는 영감으로만(실패 직후, opts.inspiration).
## opts: {"assist": [주사위 식], "inspiration": bool}
static func disarm(world: Dictionary, c: Node, t: Dictionary, opts: Dictionary = {}) -> Dictionary:
	if t["state"] != "armed" or not t.get("found", false):
		return {"ok": false, "reason": "해제할 함정이 없다"}
	if t.get("retry_blocked", false):
		return {"ok": false, "reason": "이 함정은 다시 시도할 수 없다"}
	if count(world, DISARM_KIT) <= 0:
		return {"ok": false, "reason": "함정 해체 도구가 없다"}
	var r := visible_check(world, c, "dex", "sleight_of_hand", int(t["dc_disarm"]), opts)
	if r["success"]:
		t["state"] = "disarmed"
	else:
		take(world, DISARM_KIT)
		t["retry_blocked"] = true
		trigger(world, t, c)
	return {"ok": true, "success": r["success"], "check": r}


# ---------- 자물쇠 ----------

## 자물쇠 따기(보이는 굴림, 손재주): 도둑 도구 필요. 실패하면 도구가 부서진다. 다른 도구로 다시 시도 가능.
## 열쇠가 있으면 굴림 없이 연다. DC는 자물쇠 등급별 10·15·20·25.
static func open_lock(world: Dictionary, c: Node, cell: Vector2i, opts: Dictionary = {}) -> Dictionary:
	var obj: Dictionary = world["grid"].object_at(cell)
	var lock: Dictionary = obj.get("lock", {})
	if lock.is_empty() or not lock.get("locked", false):
		return {"ok": false, "reason": "잠겨 있지 않다"}
	if lock.get("key", "") != "" and count(world, lock["key"]) > 0:
		lock["locked"] = false
		return {"ok": true, "success": true, "key": true}
	if count(world, THIEVES_TOOLS) <= 0:
		return {"ok": false, "reason": "도둑 도구가 없다"}
	var r := visible_check(world, c, "dex", "sleight_of_hand", int(lock["dc"]), opts)
	if r["success"]:
		lock["locked"] = false
		Goals.complete(world, "pick_lock")
	else:
		take(world, THIEVES_TOOLS)
	return {"ok": true, "success": r["success"], "check": r}


# ---------- 절도·목격 ----------

## 물체의 물건을 가져간다. 물체에 "owner"(세력 ID)가 있으면 소유물 — 그 세력 NPC의 시야 원뿔 안에서
## (어둠이 아닌 곳에서) 가져가면 들킨다. 들키면 world["pending_dialogue"]에 소유자 대화를 남긴다(5단계 결정 3).
## 물체: {"loot": {아이템: 개수}, "owner": 세력, "owner_dialogue": 대화 ID}
static func take_loot(world: Dictionary, c: Node, cell: Vector2i) -> Dictionary:
	var grid: Node = world["grid"]
	var obj: Dictionary = grid.object_at(cell)
	if obj.get("loot", {}).is_empty():
		return {"ok": false, "reason": "가져갈 것이 없다"}
	if obj.get("lock", {}).get("locked", false):
		return {"ok": false, "reason": "잠겨 있다"}
	var witness: Node = null
	var owner: String = obj.get("owner", "")
	if owner != "":
		for o: Node in grid.creatures():
			if o == c or o.dead or o.is_incapacitated() or o.faction != owner:
				continue
			if Stealth.sight_of(grid, o, c) in ["bright", "dim"]:
				witness = o
				break
	for item: String in obj["loot"]:
		give(world, item, int(obj["loot"][item]))
	obj["loot"] = {}
	if witness != null:
		Dice.log_text("%s가 절도를 목격했다" % witness.label())
		world["pending_dialogue"] = {"id": obj.get("owner_dialogue", ""), "npc": witness, "reason": "theft"}
		return {"ok": true, "stolen": true, "witness": witness}
	if owner != "":
		Goals.complete(world, "steal_unseen")
	return {"ok": true, "stolen": owner != ""}


# ---------- 살펴보기 ----------

## 살펴보기(보이는 굴림 — 연구 행동). 실패해도 진행이 막히지 않게 실패 결과를 데이터가 정한다.
static func examine(world: Dictionary, c: Node, ex: Dictionary, opts: Dictionary = {}) -> Dictionary:
	if ex.get("done", false):
		return {"ok": false, "reason": "이미 살펴봤다"}
	var r := visible_check(world, c, ex.get("ability", "int"), ex.get("skill", "investigation"), int(ex["dc"]), opts)
	ex["done"] = true
	var out: Dictionary = ex.get("success" if r["success"] else "fail", {})
	for tag: String in out.get("unlock", []):
		if not world.has("dialogue_tags"):
			world["dialogue_tags"] = {}
		world["dialogue_tags"][tag] = true
	for item: String in out.get("items", []):
		give(world, item)
	if out.has("goal"):
		Goals.complete(world, out["goal"])
	return {"ok": true, "success": r["success"], "check": r, "result": out}


# ---------- 보이는 굴림 ----------

## 보이는 굴림(2단계): DC와 보너스를 먼저 보여 주고, 굴리기 전 보조 주사위(Guidance 등), 실패하면 영감으로 재굴림.
## 능력 판정이라 자연 20 자동 성공·자연 1 자동 실패.
static func visible_check(world: Dictionary, c: Node, ability: String, skill: String, dc: int, opts: Dictionary = {}) -> Dictionary:
	var assist := 0
	for dice: String in opts.get("assist", []):
		assist += Dice.roll(dice, "보조 주사위")["total"]
	var r := Resolver.ability_check(c, ability, dc, {"skill": skill, "bonus": assist})
	r["assist"] = assist
	if not r["success"] and opts.get("inspiration", false) and int(world.get("inspiration", 0)) > 0:
		world["inspiration"] = int(world["inspiration"]) - 1
		Dice.log_text("영감으로 다시 굴림")
		var again := Resolver.ability_check(c, ability, dc, {"skill": skill, "bonus": assist})
		again["assist"] = assist
		again["rerolled"] = true
		return again
	return r


## 보이는 굴림 미리보기: 성공 확률(자연 20·1 반영)과 보너스.
static func preview_check(c: Node, ability: String, skill: String, dc: int, assist_avg: float = 0.0) -> Dictionary:
	var bonus: float = c.ability_mod(ability) + int(c.skill_bonuses.get(skill, 0)) + assist_avg
	var p := clampf((21.0 - (dc - bonus)) / 20.0, 0.05, 0.95)
	return {"dc": dc, "bonus": bonus, "chance": p}
