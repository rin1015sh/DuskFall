extends RefCounted
## 저장·불러오기(룰북 9단계 악용 방지 '불러오기로 다시 굴리기'). 탐험 중에만 저장한다(전투 중 저장 없음).
##   snapshot(world) → 사전(JSON으로 쓸 수 있음), restore(world, snap) → 같은 맵·같은 생물(이름)로 만든 세계에 덮어쓴다.
##   world["options"]["seed_lock"] = true면 난수 상태도 저장해 불러와도 같은 굴림이 나온다(기본 끔, 고난도에서 켬).
##   지속 주문 인스턴스는 저장하지 않는다. 그 주문이 건 상태·수정치는 남기되 '긴 휴식까지'로 바꾼다 [확인 필요: changes.md].

const VERSION := 1
const SAVE_DIR := "user://saves"
## 세계에서 그대로 저장하는 값
const WORLD_KEYS := ["inventory", "inspiration", "short_rests_left", "party_resources", "dialogue_tags", "flags",
	"goals_done", "xp", "options", "map_id", "traps", "examines"]
const CREATURE_KEYS := ["hp", "hp_max", "temp_hp", "dead", "stable", "death_saves", "team", "sneaking", "level"]


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
		out["creatures"][str(c.name)] = e
	for cell in grid.all_cells():
		var obj: Dictionary = grid.object_at(cell)
		if not obj.is_empty():
			out["objects"].append({"cell": [cell.x, cell.y], "obj": _plain(obj)})
	if world.get("options", {}).get("seed_lock", false):
		out["dice_state"] = str(Dice.get_state())
	return out


static func restore(world: Dictionary, snap: Dictionary) -> bool:
	if int(snap.get("version", 0)) != VERSION:
		return false
	for k: String in snap["world"]:
		world[k] = snap["world"][k]
	var grid: Node = world["grid"]
	var by_name := {}
	for c: Node in grid.creatures():
		by_name[str(c.name)] = c
	for n: String in snap["creatures"]:
		var c: Node = by_name.get(n)
		if c == null:
			continue
		var e: Dictionary = snap["creatures"][n]
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
			x["turns_left"] = int(x["turns_left"])
			x["source"] = null  # 근원 생물 참조는 저장하지 않는다
			c.conditions.append(x)
		c.extra_modifiers.clear()
		for x: Dictionary in e.get("modifiers", []):
			if x.has("turns_left"):
				x["turns_left"] = int(x["turns_left"])
			c.extra_modifiers.append(x)
		c.concentration = {}
	for cell in grid.all_cells():
		if not grid.object_at(cell).is_empty():
			grid.remove_object(cell)
	for o: Dictionary in snap.get("objects", []):
		grid.place_object(Vector2i(int(o["cell"][0]), int(o["cell"][1])), o["obj"])
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
	if params.has("instance") or y.has("instance"):
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
