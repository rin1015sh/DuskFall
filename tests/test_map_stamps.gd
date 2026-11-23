extends "res://tests/test_case.gd"
## 지형 도장(맵 stamps → 지형 프리셋, scripts/rules/map_stamps.gd): 돌리기·뒤집기·높이 올림, 규칙 데이터(높이·재질·플래그·빛) 덮어쓰기, 검사.

const MapStamps := preload("res://scripts/rules/map_stamps.gd")
const MapLoader := preload("res://scripts/rules/map_loader.gd")
const WorldBuilder := preload("res://scripts/rules/world_builder.gd")

## 2×3 시험 프리셋: 왼위 '2', 오른아래 오르기 지점
const PRE := {"id": "t", "grid": ["2a", ".b", "cL"], "legend": {
	"2": {"h": 2, "material": "grass", "floor": "ground_grass"}, "a": {"h": 1}, "b": {"h": 3, "material": "stone"},
	"c": {"h": 0, "light": "dark"}, "L": {"h": 0, "flags": ["climb"]}},
	"props": [{"id": "rock", "v": "small_a", "at": [0, 0]}]}


func _presets() -> Dictionary:
	return {"t": PRE}


func test_place_rotations_and_flip() -> void:
	var st := {"preset": "t", "at": [10, 20]}
	assert_eq(MapStamps.place(st, PRE, Vector2i(0, 0)), Vector2i(10, 20), "돌리지 않으면 그대로")
	st["rot"] = 90
	# 크기 2×3 → 시계 90°: (x, y) → (높이−1−y, x), 새 크기 3×2
	assert_eq(MapStamps.place(st, PRE, Vector2i(0, 0)), Vector2i(12, 20), "90°: 왼위 → 오른위")
	assert_eq(MapStamps.place(st, PRE, Vector2i(1, 2)), Vector2i(10, 21), "90°: 오른아래 → 왼아래")
	st["rot"] = 180
	assert_eq(MapStamps.place(st, PRE, Vector2i(0, 0)), Vector2i(11, 22))
	st["rot"] = 270
	assert_eq(MapStamps.place(st, PRE, Vector2i(0, 0)), Vector2i(10, 21))
	st = {"preset": "t", "at": [0, 0], "flip": true}
	assert_eq(MapStamps.place(st, PRE, Vector2i(0, 0)), Vector2i(1, 0), "좌우 뒤집기")


func test_cells_and_apply_rules_data() -> void:
	var map := {"stamps": [{"preset": "t", "at": [1, 0], "base": 1}]}
	var cs := MapStamps.cells(map, _presets())
	assert_false(cs.has(Vector2i(1, 1)), "'.'은 건드리지 않는다")
	assert_eq(int(cs[Vector2i(1, 0)]["h"]), 3, "프리셋 높이 + base")
	var g := make_grid(["....", "....", "...."])
	MapStamps.apply(g, map, _presets())
	assert_eq(g.height(Vector2i(1, 0)), 3)
	assert_eq(g.height(Vector2i(2, 1)), 4, "b(3) + base 1")
	assert_eq(g.material(Vector2i(2, 1)), "stone")
	assert_true(g.has_flag(Vector2i(2, 2), "climb"), "오르기 지점 플래그")
	assert_eq(g.light_at(Vector2i(1, 2)), 0, "어두운 칸")
	assert_eq(g.height(Vector2i(0, 0)), 0, "도장 밖은 그대로")
	var props := MapStamps.props(map, _presets())
	assert_eq(props[0]["at"], [1, 0], "소품도 맵 좌표로")


func test_check_reports_bad_stamps() -> void:
	var map := {"rows": ["....", "....", "...."], "stamps": [{"preset": "t", "at": [3, 0]}, {"preset": "none", "at": [0, 0]}]}
	var errs := MapStamps.check(map, _presets())
	assert_eq(errs.size(), 2, "지도 밖 + 없는 프리셋")


func test_all_presets_and_maps_valid() -> void:
	var db: Node = tree.root.get_node("RulesDB")
	var ids: Array = db.ids("terrain_preset")
	assert_true(ids.size() >= 10, "프리셋 모음 %d개" % ids.size())
	var presets := {}
	for id: String in ids:
		presets[id] = db.get_entry("terrain_preset", id)
	for mid: String in ["hill_path", "terrain_presets_demo"]:
		assert_eq(MapStamps.check(db.get_entry("map", mid), presets).size(), 0, "%s 도장 검사" % mid)


## 맵을 불러오면 도장 높이가 규칙 격자에 들어가고, 비탈길로 고원까지 걸어 오를 수 있다(높이 차 1씩).
func test_hill_path_stamps_reach_plateau() -> void:
	var b := WorldBuilder.build("hill_path")
	for n: Node in b["nodes"]:
		own(n)
	var g: Node = b["world"]["grid"]
	assert_eq(g.height(Vector2i(3, 2)), 3, "절벽 띠 고원")
	assert_eq(g.height(Vector2i(3, 7)), 2, "긴 비탈길 가운데")
	assert_eq(g.height(Vector2i(18, 11)), 3, "큰 둔덕 꼭대기")
	assert_true(g.has_flag(Vector2i(19, 5), "climb"))
	var fighter: Node = b["party"].filter(func(c: Node) -> bool: return c.name == "fighter")[0]
	var path: Dictionary = g.find_path(fighter, Vector2i(3, 3), -1, [])
	assert_false(path.is_empty(), "비탈길로 고원까지 간다")
