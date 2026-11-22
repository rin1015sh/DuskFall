extends RefCounted
## 맵 데이터(data/maps/<id>.json)를 GridWorld·SurfaceSystem에 채운다(룰북 8단계 '무기와 맵 칸').
## 글자 지도 + 범례 판. 생물 배치(spawns)는 돌려주기만 하고, 생물을 만드는 쪽이 놓는다.

const LIGHT := {"bright": 2, "dim": 1, "dark": 0}


## 결과: {"spawns": {spawn id: Vector2i}, "spawn_info": {spawn id: {"facing", "dialogue", "team"}},
##        "traps": [...], "examines": [...]} — 함정·살펴보기는 world["traps"]·world["examines"]에 넣는다(Interact).
static func load_into(grid: Node, surfaces: Node, map: Dictionary) -> Dictionary:
	var rows: Array = map["rows"]
	var w: int = rows[0].length()
	grid.setup(w, rows.size(), "stone", LIGHT.get(map.get("light", "bright"), 2))
	var legend: Dictionary = map["legend"]
	var water: Array = []
	for y in rows.size():
		for x in w:
			var key: String = rows[y][x]
			var cell := Vector2i(x, y)
			var l: Dictionary = legend.get(key, {})
			if l.has("material"):
				grid.set_material(cell, l["material"])
			if l.has("height"):
				grid.set_height(cell, l["height"])
			for f: String in l.get("flags", []):
				grid.set_flag(cell, f)
			if l.has("surface"):
				water.append([cell, l["surface"]])
	for item: Array in water:
		# 맵에 배치한 표면은 영구(4단계 물: 맵 배치는 영구)
		surfaces.place_surface([item[0]], item[1], {"turns": -1})
	for f: Dictionary in map.get("flags", []):
		for flag: String in f["flags"]:
			grid.set_flag(_cell(f["cell"]), flag)
	for z: Dictionary in map.get("zones", []):
		var r: Array = z["rect"]
		for y in range(r[1], r[1] + r[3]):
			for x in range(r[0], r[0] + r[2]):
				grid.add_zone(Vector2i(x, y), z["id"])
	for ls: Dictionary in map.get("light_sources", []):
		grid.light_sources.append({"id": ls["id"], "cell": _cell(ls["cell"]), "bright": ls["bright"], "dim": ls.get("dim", 0)})
	for o: Dictionary in map.get("objects", []):
		var obj := o.duplicate(true)
		obj.erase("cell")
		grid.place_object(_cell(o["cell"]), obj)
	var spawns := {}
	var info := {}
	for s: Dictionary in map.get("spawns", []):
		spawns[s["id"]] = _cell(s["cell"])
		var i := {}
		if s.has("facing"):
			i["facing"] = _cell(s["facing"])
		for k: String in ["dialogue", "team"]:
			if s.has(k):
				i[k] = s[k]
		info[s["id"]] = i
	var traps: Array = []
	for t: Dictionary in map.get("traps", []):
		var tt := t.duplicate(true)
		tt["state"] = "armed"
		traps.append(tt)
	return {"spawns": spawns, "spawn_info": info, "traps": traps, "examines": map.get("examines", []).duplicate(true)}


static func load_map(id: String) -> Dictionary:
	return RulesDB.get_entry("map", id)


static func _cell(a: Array) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))
