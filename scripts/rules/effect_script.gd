extends RefCounted
## 스크립트 효과의 바탕. 효과 모델(훅 → 조건 → 대상·범위 → 효과 목록)로 표현할 수 없는 부분만
## 데이터에 "script": "<id>"를 달고 scripts/rules/effects/<id>.gd에 이 파일을 상속해 구현한다.
## 룰북 8단계 결정 기록 1. 데이터와 충돌하면 데이터가 이긴다.


## 구현을 마친 스크립트는 true를 돌려주도록 덮어쓴다. 데이터 검증이 미구현 개수를 센다.
func is_implemented() -> bool:
	return false


## 효과를 적용한다. ctx: {"world", "self"(기능을 가진 생물), "target", "opts", 훅이면 "res"(판정 결과)}
## 결과 Dictionary를 돌려준다({"ok": bool, ...}).
func apply(_ctx: Dictionary) -> Dictionary:
	push_error("미구현 스크립트 효과: %s" % get_script().resource_path)
	return {"ok": false, "reason": "미구현"}


## 다시 쓰기(주문 데이터 recast — 번개 부르기·마녀 화살 등): 살아 있는 인스턴스로 슬롯 없이 다시 발동한다. ctx는 apply와 같고 instance는 그 인스턴스.
func recast(_ctx: Dictionary) -> Dictionary:
	return {"ok": false, "reason": "다시 쓸 수 없는 주문"}
