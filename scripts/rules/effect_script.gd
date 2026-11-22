extends RefCounted
## 스크립트 효과의 바탕. 효과 모델(훅 → 조건 → 대상·범위 → 효과 목록)로 표현할 수 없는 부분만
## 데이터에 "script": "<id>"를 달고 scripts/rules/effects/<id>.gd에 이 파일을 상속해 구현한다.
## 룰북 8단계 결정 기록 1. 데이터와 충돌하면 데이터가 이긴다.


## 구현을 마친 스크립트는 true를 돌려주도록 덮어쓴다. 데이터 검증이 미구현 개수를 센다.
func is_implemented() -> bool:
	return false


## 효과를 적용한다. ctx 모양은 판정 엔진(1단계 이후)과 함께 정한다.
func apply(_ctx: Dictionary) -> void:
	push_error("미구현 스크립트 효과: %s" % get_script().resource_path)
