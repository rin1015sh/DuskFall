---
name: verify
description: 데이터 검증, 금지어 검사, 헤드리스 테스트를 돌린다. 데이터나 규칙 코드를 바꾼 뒤, 그리고 커밋 직전에 쓴다.
---

# 검증

1. 데이터 검증: `godot --headless --path . -s res://tools/validate_data.gd`
   - 모든 JSON이 `data/schema/`의 스키마를 통과하는지, ID가 겹치지 않는지, 다른 파일을 가리키는 ID(상태·표면·주문·아이템·스크립트)가 실제로 있는지 본다.
   - `"script"`가 달린 항목은 `res://scripts/rules/effects/<id>.gd`가 있어야 한다.
2. 금지어 검사: `data/`, `scenes/`, `scripts/`에서 `tools/banned_names.txt`의 단어를 대소문자 무시·단어 단위로 찾는다. 하나라도 나오면 실패.
3. 테스트: `godot --headless --path . -s res://tests/run_all.gd`
4. 결과를 표로 보고한다(검사, 통과 여부, 실패 위치). 실패가 있으면 고친 뒤 다시 돌린다. 원인이 룰북 해석 문제면 고치기 전에 사용자에게 묻는다.

도구 파일이 아직 없으면 만들고, 만든 사실을 보고한다.
