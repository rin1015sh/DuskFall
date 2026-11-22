extends RefCounted
## 행동 목록(룰북 3단계 행동 경제 — BG3 단축 막대 구조 참고). 화면은 이 목록을 그리기만 한다.
##   공용 행동: data/rules/actions.json(이름·설명·비용·대상), 실행은 여기서 Combat·Physics·Interact로.
##   클래스 행동: 생물의 기능 중 스크립트가 있고 직접 쓰는 것(Features.use).
##   아이템: 소지품의 물약 → 마시기·먹이기·던지기.
##   주문: 생물의 주문(Spellcasting).
## 행동 키: 공용 = 행동 ID, 기능 = "feature:<id>", 아이템 = "<행동>:<아이템 ID>"(drink:potion_of_healing), 주문 = "spell:<id>".
## 탐험 중(explore)에는 행동 비용이 없다(5단계 '탐험 중 주문·소모품'): 실행 전에 턴 자원을 채운다.
## 탐험 중 적대 행동은 먼저 처리하고 전투를 시작한다(숨은 채 하면 알아채지 못한 적은 기습 — 5단계).

const Combat := preload("res://scripts/rules/combat.gd")
const Physics := preload("res://scripts/rules/physics.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Features := preload("res://scripts/rules/features.gd")
const Interact := preload("res://scripts/rules/interact.gd")

## 직접 쓰는 기능의 대상(없으면 자신)
const FEATURE_TARGET := {"divine_spark": "creature"}
## 아이콘(상태 그림 재사용)
const FEATURE_ICON := {"second_wind": "statuses/refreshed.webp", "action_surge": "statuses/orc_fervor.webp",
	"steady_aim": "statuses/marked.webp", "divine_spark": "statuses/buff.webp", "turn_undead": "statuses/fear.webp",
	"preserve_life": "statuses/vitality_drain.webp", "arcane_recovery": "statuses/riddle_empowered.webp"}
const COST_NAME := {"action_": "action", "bonus_action": "bonus", "action": "action", "free": "free", "reaction": "reaction"}


static func defs() -> Dictionary:
	var out := {}
	for a: Dictionary in RulesDB.entries("action"):
		out[a["id"]] = a
	return out


static func def_of(key: String) -> Dictionary:
	if key.begins_with("spell:"):
		var sp := RulesDB.get_entry("spell", key.trim_prefix("spell:"))
		return {"id": key, "name": sp.get("name", {}), "desc": {"ko": sp.get("notes_ko", ""), "en": ""},
			"cost": Spellcasting._cost(sp) if not sp.is_empty() else "action", "target": "cell", "tab": "spells", "spell": sp}
	if key.begins_with("feature:"):
		var fid := key.trim_prefix("feature:")
		var f: Dictionary = {}
		for cls_f: Dictionary in _all_features():
			if cls_f["id"] == fid:
				f = cls_f
		return {"id": key, "name": f.get("name", {"ko": fid, "en": fid}), "desc": f.get("desc", f.get("summary", {"ko": f.get("notes_ko", ""), "en": ""})),
			"cost": COST_NAME.get(str(f.get("kind", "free")), "free"), "target": FEATURE_TARGET.get(fid, "self"), "tab": "class",
			"icon": "res://assets/" + FEATURE_ICON.get(fid, "statuses/buff.webp"), "explore": fid in ["arcane_recovery", "second_wind"],
			"resource": f.get("resource", "")}
	var parts := key.split(":")
	var base: Dictionary = defs().get(parts[0], {})
	if parts.size() > 1 and not base.is_empty():
		base = base.duplicate(true)
		base["item"] = parts[1]
		var item := RulesDB.get_entry("item", parts[1])
		base["name"] = {"ko": "%s: %s" % [base["name"]["ko"], item.get("name", {}).get("ko", parts[1])],
			"en": "%s: %s" % [base["name"]["en"], item.get("name", {}).get("en", parts[1])]}
	return base


static func _all_features() -> Array:
	var out: Array = []
	for cls: Dictionary in RulesDB.entries("class"):
		out.append_array(cls.get("features", []))
		for s: Dictionary in cls.get("subclasses", []):
			out.append_array(s.get("features", []))
	return out


## 탭별 행동 키 목록: {"common": [...], "class": [...], "items": [...], "spells": [...]}
static func list_for(world: Dictionary, c: Node, explore: bool = false) -> Dictionary:
	var out := {"common": [], "class": [], "items": [], "spells": []}
	for id: String in defs():
		var d: Dictionary = defs()[id]
		if d["tab"] == "items":
			continue
		if id.begins_with("cunning_") and not c.has_feature("cunning_action"):
			continue
		if id == "offhand_attack" and c.weapon("off") == "":
			continue
		if explore and not d["explore"]:
			continue
		out[d["tab"]].append(id)
	for fid: String in c.feature_data:
		var f: Dictionary = c.feature_data[fid]
		if f.has("script") and (str(f.get("kind", "")) in ["action", "bonus_action", "free"] or fid == "arcane_recovery"):
			if explore and not def_of("feature:" + fid)["explore"]:
				continue
			out["class"].append("feature:" + fid)
	for item: String in world.get("inventory", {}):
		var e := RulesDB.get_entry("item", item) if item != "gold" else {}
		if e.get("category", "") == "potion" and Interact.count(world, item) > 0:
			for verb: String in ["drink", "feed", "throw_potion"]:
				out["items"].append("%s:%s" % [verb, item])
	for sid: String in c.spells:
		if not RulesDB.get_entry("spell", sid).is_empty():
			out["spells"].append("spell:" + sid)
	return out


## 지금 쓸 수 없는 이유("" = 가능). 대상과 상관없는 검사만.
static func unavailable(world: Dictionary, c: Node, key: String, explore: bool = false) -> String:
	var d := def_of(key)
	if d.is_empty():
		return "모르는 행동"
	if c.dead or c.is_down():
		return "쓰러졌다"
	if not explore:
		var cost: String = d.get("cost", "action")
		if key in ["attack", "ranged_attack"] and int(c.turn.get("attacks_left", 0)) > 0:
			cost = "free"
		if cost != "free" and not Combat.can_spend(c, cost):
			return {"action": "행동이 없다", "bonus": "보너스 행동이 없다", "reaction": "반응이 없다"}.get(cost, "비용이 없다")
	if d.get("resource", "") != "" and c.resource(d["resource"]) <= 0:
		return "남은 횟수가 없다"
	if key.begins_with("spell:"):
		var sp: Dictionary = d["spell"]
		if int(sp.get("level", 0)) > 0:
			var any := false
			for l in range(int(sp["level"]), 10):
				any = any or c.resource("spell_slot_%d" % l) > 0
			if not any:
				return "주문 슬롯이 없다"
	match key:
		"stand_up":
			if not c.has_condition("prone"):
				return "넘어지지 않았다"
		"jump":
			if not explore and int(c.turn.get("movement", 0)) < 2:
				return "이동력이 모자란다"
		"dip":
			if _dip_kind(world, c) == "":
				return "담글 표면이 없다"
		"throw":
			if _throwable(world, c).is_empty():
				return "옆에 던질 물체가 없다"
		"offhand_attack":
			if not c.turn.get("light_attack_done", false) and not explore:
				return "먼저 가벼운 무기로 공격해야 한다"
	return ""


## 대상 칸에 대한 미리보기: {"valid", "lines": [..], "path", "area"}
static func preview(world: Dictionary, c: Node, key: String, cell: Vector2i, explore: bool = false) -> Dictionary:
	var grid: Node = world["grid"]
	var d := def_of(key)
	var why := unavailable(world, c, key, explore)
	if why != "":
		return {"valid": false, "lines": [why]}
	var t: Node = grid.creature_at(cell)
	var out := {"valid": true, "lines": []}
	match d.get("target", "self"):
		"enemy":
			if t == null or not c.is_hostile_to(t) or t.dead:
				return {"valid": false, "lines": ["적을 골라야 한다"]}
		"ally", "ally_down":
			if t == null or c.is_hostile_to(t) or t.dead:
				return {"valid": false, "lines": ["아군을 골라야 한다"]}
			if d["target"] == "ally_down" and not t.is_down():
				return {"valid": false, "lines": ["쓰러진 아군에게만"]}
			if grid.distance_between(c, t) > 1 and key != "spell":
				return {"valid": false, "lines": ["인접해야 한다"]}
		"creature":
			if t == null or t.dead:
				return {"valid": false, "lines": ["생물을 골라야 한다"]}
	match key:
		"attack", "ranged_attack", "offhand_attack":
			var opts := {}
			if key == "ranged_attack":
				opts["weapon"] = c.weapon_sets.get("ranged", {}).get("main", "")
			elif key == "offhand_attack":
				opts["weapon"] = c.weapon("off")
			var p := Combat.preview_attack(world, c, t, opts)
			if not p.get("valid", false):
				return {"valid": false, "lines": [p.get("reason", "")]}
			out["lines"].append("명중 %d%%" % roundi(p["hit_chance"] * 100))
			out["lines"].append("피해 %d~%d" % [p["damage"]["min"], p["damage"]["max"]])
			out["chance"] = p["hit_chance"]
		"jump":
			var reach := Combat.jump_distance(c)
			var ok: bool = grid.distance(grid.cell_of(c), cell) <= reach and not grid.blocks_movement(cell) \
				and grid.creature_at(cell) == null and grid.height(cell) - grid.height(grid.cell_of(c)) <= 1
			out["valid"] = ok
			out["path"] = [cell]
			out["lines"].append("도약 %d칸까지" % reach)
			var drop: int = grid.height(grid.cell_of(c)) - grid.height(cell)
			if drop >= 2:
				out["lines"].append("낙하 %d단계" % drop)
		"shove":
			if grid.distance_between(c, t) > 1:
				return {"valid": false, "lines": ["인접한 대상만"]}
			var p := Physics.preview_shove(grid, c, t, not c.is_hostile_to(t))
			if not p["valid"]:
				return {"valid": false, "lines": [p.get("reason", "")]}
			out["path"] = p["path"]
			out["lines"].append("성공 %d%% · %d칸" % [roundi(p["chance"] * 100), p["distance"]])
			if p["fall_levels"] > 0:
				out["lines"].append("낙하 %d단계" % p["fall_levels"])
		"throw":
			var obj := _throwable(world, c)
			var w := float(obj.get("weight_kg", 10))
			if w > Physics.max_throw_kg(c):
				return {"valid": false, "lines": ["너무 무겁다"]}
			out["lines"].append("%s 던지기 · 피해 %s" % [obj.get("id", ""), Physics.throw_damage_dice(w)])
		"throw_potion":
			var cells: Array = [cell]
			for dd: Vector2i in grid.DIRS_4:
				cells.append(cell + dd)
			out["area"] = cells
		_:
			if key.begins_with("spell:"):
				var p := Spellcasting.preview(world, c, key.trim_prefix("spell:"), cell)
				out["valid"] = p["valid"]
				out["area"] = p["cells"]
				if not p["valid"]:
					out["lines"].append(p["reason"])
				for row: Dictionary in p["targets"]:
					if row.has("chance"):
						out["lines"].append("%s %d%%" % [row["creature"].label(), roundi(row["chance"] * 100)])
	return out


## 실행. 결과: {"ok", "reason"?, "hostile": 적대 행동이었나}
static func execute(world: Dictionary, c: Node, key: String, cell: Vector2i, explore: bool = false) -> Dictionary:
	var grid: Node = world["grid"]
	if explore:
		c.reset_turn()  # 탐험 중에는 행동 비용이 없다
	var why := unavailable(world, c, key, explore)
	if why != "":
		return {"ok": false, "reason": why}
	var t: Node = grid.creature_at(cell)
	var hostile: bool = t != null and c.is_hostile_to(t) and key in ["attack", "ranged_attack", "offhand_attack", "shove", "throw"]
	if key.begins_with("spell:"):
		var sp := RulesDB.get_entry("spell", key.trim_prefix("spell:"))
		hostile = sp.get("effects", {}).has("check") and grid.creatures().any(func(o: Node) -> bool:
			return c.is_hostile_to(o) and grid.cell_of(o) == cell)
	# 탐험 중 숨은 채 하는 적대 행동: 알아채지 못한 적에게는 숨은 상태의 공격(유리 — 5단계 은신 공격)
	if explore and hostile and c.sneaking and t != null and t.awareness.get(c, {}).get("state", "") != "alerted":
		c.apply_condition("invisible", -1, "hide", {"stealth_total": int(c.get_meta("stealth_total", 10))})
	var r: Dictionary = _run(world, c, key, cell, t)
	r["hostile"] = hostile
	if explore and hostile and world.get("explore") != null and t != null:
		world["explore"].hostile_action(c, t)
	return r


static func _run(world: Dictionary, c: Node, key: String, cell: Vector2i, t: Node) -> Dictionary:
	var grid: Node = world["grid"]
	if key.begins_with("spell:"):
		return Spellcasting.cast(world, c, key.trim_prefix("spell:"), cell)
	if key.begins_with("feature:"):
		return Features.use(world, c, key.trim_prefix("feature:"), t)
	var parts := key.split(":")
	match parts[0]:
		"attack":
			if c.active_set != "melee":
				Combat.switch_weapon_set(c)
			return Combat.attack(world, c, t)
		"ranged_attack":
			if c.active_set != "ranged":
				Combat.switch_weapon_set(c)
			return Combat.attack(world, c, t)
		"offhand_attack":
			return Combat.offhand_attack(world, c, t)
		"jump":
			if world.get("explore") != null and not world["turns"].in_combat:
				return {"ok": world["explore"].jump(c, cell)}
			return Combat.jump(world, c, cell)
		"shove":
			return Combat.shove(world, c, t)
		"throw":
			var obj := _throwable(world, c)
			var r := Combat.throw_object(world, c, t, float(obj.get("weight_kg", 10)))
			if r.get("ok", false):
				var at: Vector2i = obj["_cell"]
				grid.remove_object(at)
				if world.get("surfaces") != null and not obj.get("contents", {}).is_empty():
					grid.place_object(grid.cell_of(t), obj)
					world["surfaces"].break_object(grid.cell_of(t))  # 기름통 등은 맞은 자리에서 깨진다
			return r
		"dash":
			return Combat.dash(c)
		"disengage":
			return Combat.disengage(c)
		"hide":
			return Combat.hide(world, c)
		"cunning_dash", "cunning_disengage", "cunning_hide":
			return Combat.cunning_action(world, c, parts[0].trim_prefix("cunning_"))
		"help":
			return Combat.help(world, c, t)
		"dip":
			return Combat.dip(world, c)
		"stand_up":
			return Combat.stand_up(c)
		"switch_weapons":
			Combat.switch_weapon_set(c)
			return {"ok": true}
		"drink", "feed":
			var item := RulesDB.get_entry("item", parts[1])
			var who: Node = c if parts[0] == "drink" else t
			var r := Combat.drink_potion(c, item.get("effects", []), who, world)
			if r.get("ok", false):
				Interact.take(world, parts[1])
			return r
		"throw_potion":
			var item := RulesDB.get_entry("item", parts[1])
			if not Combat.spend(c, "action"):
				return {"ok": false, "reason": "행동이 없다"}
			Interact.take(world, parts[1])
			Physics.throw_potion(grid, cell, item.get("effects", []), t)
			return {"ok": true}
	return {"ok": false, "reason": "모르는 행동"}


static func _dip_kind(world: Dictionary, c: Node) -> String:
	var grid: Node = world["grid"]
	for cell in preload("res://scripts/rules/area.gd").circle(null, grid.cell_of(c), 1):
		var sid: String = grid.surface_id(cell)
		if sid == "fire" or (sid != "" and RulesDB.get_entry("surface", sid).get("coats", "") != ""):
			return sid
	return ""


## 옆 칸(또는 자기 칸)에 있는 던질 수 있는 물체(무게가 있는 것). 결과에 "_cell"을 붙인다.
static func _throwable(world: Dictionary, c: Node) -> Dictionary:
	var grid: Node = world["grid"]
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var cell: Vector2i = grid.cell_of(c) + Vector2i(dx, dy)
			var obj: Dictionary = grid.object_at(cell)
			if not obj.is_empty() and obj.has("weight_kg") and float(obj["weight_kg"]) <= Physics.max_throw_kg(c):
				var o := obj.duplicate(true)
				o["_cell"] = cell
				return o
	return {}
