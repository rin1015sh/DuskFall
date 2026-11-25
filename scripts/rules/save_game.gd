extends RefCounted
## 저장·불러오기(룰북 9단계 악용 방지 '불러오기로 다시 굴리기'). 탐험 중에만 저장한다(전투 중 저장 없음).
##   snapshot(world) → 사전(JSON으로 쓸 수 있음), restore(world, snap) → 같은 맵·같은 생물(이름)로 만든 세계에 덮어쓴다.
##   world["options"]["seed_lock"] = true면 난수 상태도 저장해 불러와도 같은 굴림이 나온다(기본 끔, 고난도에서 켬).
##   지속 주문 인스턴스는 저장하지 않는다. 그 주문이 건 상태·수정치는 남기되 '긴 휴식까지'로 바꾼다 [확인 필요: changes.md].

const VERSION := 1
const SAVE_DIR := "user://saves"
## 세계에서 그대로 저장하는 값
const WORLD_KEYS := ["stash", "inspiration", "short_rests_left", "party_resources", "dialogue_tags", "flags",
	"goals_done", "xp", "options", "map_id", "traps", "examines", "zones_cleared", "discovered"]
const CREATURE_KEYS := ["hp", "hp_max", "temp_hp", "dead", "stable", "death_saves", "team", "sneaking", "level", "faction",
	"spells", "spellbook", "prepared", "prep_swaps", "prep_base", "known_reactions", "inventory", "equipment"]
## 생물 메타 중 저장하는 것(대화를 이미 했는지, 경험치를 이미 줬는지, 레벨 업 명세)
const CREATURE_METAS := ["dialogue_done", "xp_given", "spec", "beast_form", "wild_shape_hp"]


static func can_save(world: Dictionary) -> bool:
	return world.get("turns") == null or not world["turns"].in_combat


static func snapshot(world: Dictionary) -> Dictionary:
	var out := {"version": VERSION, "world": {}, "creatures": {}, "objects": []}
	for k: String in WORLD_KEYS:
		if world.has(k):
			out["world"][k] = _plain(world[k])
	var grid: Node = world["grid"]
	for c: Node in grid.creatures():
		var e := {}
		for k: String in CREATURE_KEYS:
			e[k] = _plain(c.get(k))
		e["cell"] = [grid.cell_of(c).x, grid.cell_of(c).y]
		e["facing"] = [c.facing.x, c.facing.y]
		var res := {}
		for id: String in c.resources:
			res[id] = int(c.resources[id]["current"])
		e["resources"] = res
		e["conditions"] = c.conditions.map(func(x: Dictionary) -> Dictionary: return _plain_effect(x))
		e["modifiers"] = c.extra_modifiers.map(func(x: Dictionary) -> Dictionary: return _plain_effect(x))
		var metas := {}
		for m: String in CREATURE_METAS:
			if c.has_meta(m):
				metas[m] = _plain(c.get_meta(m))
		e["metas"] = metas
		var aw := {}
		for k in c.awareness:
			if k is Node and is_instance_valid(k):
				aw[str(k.name)] = {"state": c.awareness[k].get("state", ""), "last": _plain(c.awareness[k].get("last", Vector2i.ZERO))}
		e["awareness"] = aw
		out["creatures"][str(c.name)] = e
	out["party"] = world.get("party", []).map(func(c: Node) -> String: return str(c.name))
	out["roster"] = world.get("roster", []).map(func(c: Node) -> String: return str(c.name))
	for cell in grid.all_cells():
		var obj: Dictionary = grid.object_at(cell)
		if not obj.is_empty():
			out["objects"].append({"cell": [cell.x, cell.y], "obj": _plain(obj)})
	out["spells"] = _snapshot_spells(world)
	if world.get("options", {}).get("seed_lock", false):
		out["dice_state"] = str(Dice.get_state())
	return out


## 다시 걸 수 있는 지속 주문: 내성·공격 판정이 없는(이로운) 주문. 시전자·조준 칸·슬롯·남은 집중 시간.
## 이런 주문이 건 상태·수정치는 따로 저장하지 않고(불러올 때 다시 걸림), 나머지는 '긴 휴식까지'로 남긴다.
static func _snapshot_spells(world: Dictionary) -> Array:
	var Sp: Variant = load("res://scripts/rules/spellcasting.gd")
	var grid: Node = world["grid"]
	var out: Array = []
	for inst: Dictionary in Sp.instances.values():
		if inst["world"] != world or not recastable(inst["spell"]) or not is_instance_valid(inst["caster"]):
			continue
		var c: Node = inst["caster"]
		var aim: Vector2i = inst.get("entity", {}).get("cell", grid.cell_of(c) if grid.creatures().has(c) else Vector2i.ZERO)
		if not inst["targets"].is_empty() and is_instance_valid(inst["targets"][0]) and grid.creatures().has(inst["targets"][0]):
			aim = grid.cell_of(inst["targets"][0])
		out.append({"spell": inst["spell"], "caster": str(c.name), "aim": [aim.x, aim.y], "slot": int(inst.get("slot", 0)),
			"conc": int(c.concentration.get("turns_left", -1)) if c.concentration.get("instance") == inst["id"] else -2})
	return out


static func recastable(spell_id: String) -> bool:
	var sp := RulesDB.get_entry("spell", spell_id)
	return not sp.is_empty() and not sp.get("effects", {}).has("check") and not spell_id in ["find_familiar", "animate_dead", "glyph_of_warding"]


## opts.skip: 되살리지 않을 생물 이름(맵 이동 때 데리고 다니는 파티)
static func restore(world: Dictionary, snap: Dictionary, opts: Dictionary = {}) -> bool:
	if int(snap.get("version", 0)) != VERSION:
		return false
	for k: String in snap["world"]:
		if opts.get("skip", []).is_empty() or k in ["traps", "examines", "zones_cleared", "discovered", "map_id"]:
			world[k] = snap["world"][k]  # 맵 이동이면 맵 고유 값만(소지품 등은 들고 온 값)
	var grid: Node = world["grid"]
	var by_name := {}
	for c: Node in grid.creatures():
		by_name[str(c.name)] = c
	for n: String in snap["creatures"]:
		var c: Node = by_name.get(n)
		if c == null or n in opts.get("skip", []):
			continue
		var e: Dictionary = snap["creatures"][n]
		# 저장된 명세로 캐릭터를 다시 만든다(레벨·장비 — 파생 값: AC·무기 묶음·착용 효과)
		var spec: Variant = e.get("metas", {}).get("spec")
		if spec is Dictionary:
			load("res://scripts/rules/character_builder.gd").apply(c, spec)  # 레벨·장비 등 명세로 다시 만든다
		for k: String in CREATURE_KEYS:
			if e.has(k):
				c.set(k, _typed(c.get(k), e[k]))
		grid.move_creature(c, Vector2i(int(e["cell"][0]), int(e["cell"][1])))
		c.facing = Vector2i(int(e["facing"][0]), int(e["facing"][1]))
		for id: String in e.get("resources", {}):
			if c.resources.has(id):
				c.resources[id]["current"] = int(e["resources"][id])
		c.conditions.clear()
		for x: Dictionary in e.get("conditions", []):
			if x.get("recast", false):
				continue
			x["turns_left"] = int(x["turns_left"])
			x["source"] = null  # 근원 생물 참조는 저장하지 않는다
			c.conditions.append(x)
		c.extra_modifiers.clear()
		for x: Dictionary in e.get("modifiers", []):
			if x.get("recast", false):
				continue
			if x.has("turns_left"):
				x["turns_left"] = int(x["turns_left"])
			c.extra_modifiers.append(x)
		c.concentration = {}
		for m: String in e.get("metas", {}):
			c.set_meta(m, e["metas"][m])
		if c.has_meta("beast_form"):
			load("res://scripts/rules/effects/wild_shape.gd").shape_stats(c, str(c.get_meta("beast_form")), true)  # 야생 변신 중 저장(HP는 저장값)
		elif c.has_condition("wild_shaped"):
			c.remove_condition("wild_shaped")
		c.awareness.clear()
		for n2: String in e.get("awareness", {}):
			if by_name.has(n2):
				var a: Dictionary = e["awareness"][n2]
				c.awareness[by_name[n2]] = {"state": a["state"], "last": Vector2i(int(a["last"][0]), int(a["last"][1]))}
	if snap.has("party") and opts.get("skip", []).is_empty():
		world["party"] = snap["party"].filter(func(n3: String) -> bool: return by_name.has(n3)).map(func(n3: String) -> Node: return by_name[n3])
		world["roster"] = snap.get("roster", []).filter(func(n3: String) -> bool: return by_name.has(n3)).map(func(n3: String) -> Node: return by_name[n3])
		if world.get("explore") != null:
			world["explore"].party = world["party"].duplicate()
	# 옛 저장(공용 가방 world.inventory) → 고른 캐릭터 소지품으로 옮긴다(캐릭터별 소지품 2026-11-23)
	if world.has("inventory"):
		var old_bag: Dictionary = world["inventory"]
		world.erase("inventory")
		for item: String in old_bag:
			load("res://scripts/rules/interact.gd").give(world, item, int(old_bag[item]))
	for cell in grid.all_cells():
		if not grid.object_at(cell).is_empty():
			grid.remove_object(cell)
	for o: Dictionary in snap.get("objects", []):
		grid.place_object(Vector2i(int(o["cell"][0]), int(o["cell"][1])), o["obj"])
	# 지속 주문 다시 걸기(비용 없이, 남은 집중 시간 이어서)
	var Sp: Variant = load("res://scripts/rules/spellcasting.gd")
	for id: Variant in Sp.instances.keys():
		if Sp.instances[id]["world"] == world:
			Sp.end_instance(id)
	for sp: Dictionary in snap.get("spells", []):
		var caster: Node = by_name.get(sp["caster"])
		if caster == null or caster.dead:
			continue
		var r: Dictionary = Sp.cast(world, caster, sp["spell"], Vector2i(int(sp["aim"][0]), int(sp["aim"][1])), {"free": true, "slot": int(sp["slot"])})
		if r.get("ok", false) and int(sp["conc"]) > 0 and not caster.concentration.is_empty():
			caster.concentration["turns_left"] = int(sp["conc"])
	if snap.has("dice_state"):
		Dice.set_state(int(snap["dice_state"]))
	return true


static func write(slot: String, world: Dictionary) -> int:
	if not can_save(world):
		return ERR_BUSY
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var f := FileAccess.open("%s/%s.json" % [SAVE_DIR, slot], FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(snapshot(world), "\t"))
	return OK


static func read(slot: String) -> Dictionary:
	var p := "%s/%s.json" % [SAVE_DIR, slot]
	if not FileAccess.file_exists(p):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if typeof(d) == TYPE_DICTIONARY else {}


## JSON 숫자는 실수로 돌아오므로 원래 형에 맞춘다.
static func _typed(old: Variant, v: Variant) -> Variant:
	if typeof(old) == TYPE_INT:
		return int(v)
	if typeof(old) == TYPE_DICTIONARY:
		var d := {}
		for k in v:
			d[k] = _typed(old.get(k, 0), v[k])
		return d
	return v


## 상태·수정치: 생물·노드 참조는 이름으로, 주문 인스턴스 연결은 끊고 '긴 휴식까지'로 표시한다.
static func _plain_effect(x: Dictionary) -> Dictionary:
	var y: Dictionary = _plain(x)
	var params: Dictionary = y.get("params", {})
	var inst_id: Variant = params.get("instance", y.get("instance"))
	var Sp: Variant = load("res://scripts/rules/spellcasting.gd")
	if inst_id != null and Sp.instances.has(inst_id) and recastable(Sp.instances[inst_id]["spell"]):
		y["recast"] = true  # 불러올 때 주문을 다시 거므로 이 항목은 버린다
		params.erase("instance")
		y.erase("instance")
		y["until_long_rest"] = true
	return y


## JSON으로 쓸 수 있는 값으로 바꾼다(노드 → 이름, Vector2i → [x, y]).
static func _plain(v: Variant) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[str(k.name) if k is Node else str(k)] = _plain(v[k])
			return d
		TYPE_ARRAY:
			return v.map(func(x: Variant) -> Variant: return _plain(x))
		TYPE_OBJECT:
			return str(v.name) if v is Node else null
		TYPE_VECTOR2I:
			return [v.x, v.y]
	return v
