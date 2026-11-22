extends Node
## 규칙 데이터 저장소(오토로드). 룰북 8단계 'Godot 구조'.
## 게임 시작 때 data/의 JSON을 읽어 종류·ID로 조회하고 스키마를 검사한다.
## 0단계: 빈 골격. 로드·조회는 1단계에서 구현한다.

## kind(예: "spell") → { id → 항목 Dictionary }
var _entries: Dictionary = {}


## 항목 하나를 돌려준다. 없으면 빈 Dictionary.
func get_entry(kind: String, id: String) -> Dictionary:
	return _entries.get(kind, {}).get(id, {})


## 한 종류의 ID 목록.
func ids(kind: String) -> Array:
	return _entries.get(kind, {}).keys()
