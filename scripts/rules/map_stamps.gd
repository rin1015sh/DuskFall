extends RefCounted
## 지형 도장(맵 데이터 "stamps"): 지형 프리셋(data/content/terrain_presets.json, 종류 terrain_preset)을 맵에 찍는다.
## 맵 글자 지도(rows)를 읽은 뒤에 덮어쓴다 — 높이·재질·플래그(오르기 지점 등)·기본 빛은 규칙 데이터(GridWorld)로,
## 바닥 그림(floor)·소품(props)은 표현 계층(map_view)이 같은 계산을 써서 그린다.
##
## 도장 한 개: {"preset": id, "at": [x, y](돌린 뒤 왼위 칸), "rot": 0|90|180|270(시계 방향), "flip": 좌우 뒤집기(돌리기 전),
##             "base": 높이 올림(프리셋 높이에 더함, 기본 0)}
## 프리셋: {"id", "name", "grid": [글자 줄], "legend": {글자: {"h", "material", "floor", "flags", "light"}}, "props": [{"id", "v", "at"}]}
## 글자 "." 와 " " 는 건드리지 않는 칸.

const LIGHT := {"bright": 2, "dim": 1, "dark": 0}


## 도장이 덮는 칸: {Vector2i: {"h": int, "material": String, "floor": String, "flags": Array, "light": String}}.
## 뒤에 찍은 도장이 앞을 덮는다. presets: id → 프리셋(없으면 RulesDB에서 찾는다).
static func cells(map: Dictionary, presets: Dictionary = {}) -> Dictionary:
	var out := {}
	for st: Dictionary in map.get("stamps", []):
		var pre := _preset(str(st.get("preset", "")), presets)
		if pre.is_empty():
			continue
		var base := int(st.get("base", 0))
		var legend: Dictionary = pre.get("legend", {})
		var rows: Array = pre.get("grid", [])
		for y in rows.size():
			var row := String(rows[y])
			for x in row.length():
				var ch := row[x]
				if ch == "." or ch == " " or not legend.has(ch):
					continue
				var l: Dictionary = legend[ch]
				var cell := place(st, pre, Vector2i(x, y))
				var rec := {"h": base + int(l.get("h", 0)), "flags": l.get("flags", []).duplicate()}
				for k: String in ["material", "floor", "light"]:
					if l.has(k):
						rec[k] = l[k]
				out[cell] = rec
	return out


## 도장의 소품(맵 좌표로 옮긴 art.props 꼴): [{"id", "v", "at": [x, y]}]
static func props(map: Dictionary, presets: Dictionary = {}) -> Array:
	var out: Array = []
	for st: Dictionary in map.get("stamps", []):
		var pre := _preset(str(st.get("preset", "")), presets)
		for p: Dictionary in pre.get("props", []):
			var cell := place(st, pre, Vector2i(int(p["at"][0]), int(p["at"][1])))
			var q := p.duplicate(true)
			q["at"] = [cell.x, cell.y]
			out.append(q)
	return out


## 프리셋 크기(돌리기 전): Vector2i(너비, 높이)
static func size_of(pre: Dictionary) -> Vector2i:
	var rows: Array = pre.get("grid", [])
	var w := 0
	for r: Variant in rows:
		w = maxi(w, String(r).length())
	return Vector2i(w, rows.size())


## 프리셋 칸(local) → 맵 칸. 뒤집기(좌우) → 시계 방향 돌리기 → at만큼 옮기기.
static func place(st: Dictionary, pre: Dictionary, local: Vector2i) -> Vector2i:
	var sz := size_of(pre)
	var p := local
	if bool(st.get("flip", false)):
		p.x = sz.x - 1 - p.x
	match posmod(int(st.get("rot", 0)), 360):
		90:
			p = Vector2i(sz.y - 1 - p.y, p.x)
		180:
			p = Vector2i(sz.x - 1 - p.x, sz.y - 1 - p.y)
		270:
			p = Vector2i(p.y, sz.x - 1 - p.x)
	return p + Vector2i(int(st["at"][0]), int(st["at"][1]))


## 격자에 규칙 데이터를 덮어쓴다(map_loader가 글자 지도 다음에 부른다).
static func apply(grid: Node, map: Dictionary, presets: Dictionary = {}) -> void:
	var cs := cells(map, presets)
	for cell: Vector2i in cs:
		if not grid.in_bounds(cell):
			continue
		var rec: Dictionary = cs[cell]
		grid.set_height(cell, int(rec["h"]))
		if rec.has("material"):
			grid.set_material(cell, rec["material"])
		for f: String in rec["flags"]:
			grid.set_flag(cell, f)
		if rec.has("light"):
			grid.set_base_light(cell, LIGHT[rec["light"]])


## 검사(데이터 검증 도구): 없는 프리셋·지도 밖으로 나가는 도장·잘못된 돌리기 각
static func check(map: Dictionary, presets: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var rows: Array = map.get("rows", [])
	var w: int = String(rows[0]).length() if not rows.is_empty() else 0
	for i in map.get("stamps", []).size():
		var st: Dictionary = map["stamps"][i]
		var pid := str(st.get("preset", ""))
		if not presets.has(pid):
			errs.append("stamps[%d]: 지형 프리셋 '%s'가 없다" % [i, pid])
			continue
		if not int(st.get("rot", 0)) in [0, 90, 180, 270]:
			errs.append("stamps[%d]: rot는 0·90·180·270 중 하나" % i)
		var pre: Dictionary = presets[pid]
		var sz := size_of(pre)
		for corner: Vector2i in [Vector2i.ZERO, Vector2i(sz.x - 1, 0), Vector2i(0, sz.y - 1), sz - Vector2i.ONE]:
			var c := place(st, pre, corner)
			if c.x < 0 or c.y < 0 or c.x >= w or c.y >= rows.size():
				errs.append("stamps[%d]: 프리셋 '%s'가 지도 밖으로 나간다(%d, %d)" % [i, pid, c.x, c.y])
				break
	return errs


static func _preset(id: String, presets: Dictionary) -> Dictionary:
	if presets.has(id):
		return presets[id]
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root.has_node("RulesDB"):
		return tree.root.get_node("RulesDB").get_entry("terrain_preset", id)
	return {}
