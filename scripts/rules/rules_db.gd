extends Node
## 규칙 데이터 저장소(오토로드). 룰북 8단계 'Godot 구조', 결정 기록 2(JSON 직접 로드).
## 게임 시작 때 data/의 JSON을 읽어 스키마를 검사하고 종류·ID로 조회한다.

const DataLoader := preload("res://scripts/rules/data_loader.gd")
const DATA_DIR := "res://data"

## 마지막 로드의 오류. 비어 있으면 정상.
var load_errors := PackedStringArray()
## kind → { id → 항목 Dictionary }
var _entries: Dictionary = {}


func _ready() -> void:
	reload()


## data/ 전체를 다시 읽는다. 오류가 있으면 push_error로 알리고, 읽힌 항목은 그대로 쓴다.
func reload(data_dir: String = DATA_DIR) -> bool:
	var loader := DataLoader.new()
	var ok := loader.load_dir(data_dir)
	load_errors = loader.errors
	_entries.clear()
	for kind: String in loader.entries.keys():
		_entries[kind] = {}
		for id: String in loader.entries[kind].keys():
			_entries[kind][id] = loader.entries[kind][id]["entry"]
	for e in load_errors:
		push_error("RulesDB: " + e)
	return ok


## 항목 하나를 돌려준다. 없으면 빈 Dictionary.
func get_entry(kind: String, id: String) -> Dictionary:
	return _entries.get(kind, {}).get(id, {})


func has_entry(kind: String, id: String) -> bool:
	return _entries.get(kind, {}).has(id)


## 한 종류의 ID 목록(정렬).
## 한 종류의 항목 전부(불러온 순서).
func entries(kind: String) -> Array:
	return ids(kind).map(func(id: String) -> Dictionary: return get_entry(kind, id))


func ids(kind: String) -> Array:
	var out: Array = _entries.get(kind, {}).keys()
	out.sort()
	return out
