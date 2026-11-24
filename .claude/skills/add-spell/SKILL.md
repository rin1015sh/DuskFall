---
name: add-spell
description: 주문을 spells.json에 추가하거나 고친다. 4레벨 이상 주문 추가, 기존 주문 효과 수정, 스크립트 주문 구현에 쓴다.
---

# 주문 추가·수정

요청: $ARGUMENTS

## 먼저 읽을 것

- 룰북 6단계 공통 변환 규칙과 주문 변환표(`docs/rules/spells_table.md`), 4단계 범위 템플릿·반응표·상태이상, 8단계 스키마, 9단계 충돌 처리(A~F).
- 원문은 `docs/srd/07_Spells.md`.

## 변환 규칙 요약

- 수치는 BG3 우선(2026-11-24): bg3.wiki 주문 틀의 미터 ÷ 1.5 내림 = 칸('ranged' 12칸, 'melee' 접촉), 지속·집중·비용도 BG3. BG3에 없는 주문만 아래 SRD 변환.
- 거리: 피트 ÷ 5 = 칸. 접촉 = 인접 8칸.
- 지속: 1라운드 = 1턴, 1분 = 10턴, 10분 = 100턴, 1시간 이상 = 긴 휴식까지.
- 시전 시간 1분 이상 = 탐험 전용. 의식 = 탐험 중에만 슬롯 없이.
- 범위: 매끄러운 도형(Area.cov_* — 룰북 4단계, changes.md 2026-11-22): 원 = 반지름 N + 0.5칸, 원뿔 = 길이 N + 0.5칸·반각 atan(1/2), 선 = 너비 1칸, 칸 덮인 비율 25% 이상이면 포함. 정육면체는 S/5 × S/5.
- 칸 반응(`tiles`)은 범위 효과이거나 원문에 적힌 경우만(9단계 A).
- 상태이상은 4단계 목록만. 붙잡힘 → 속박, 귀먹음 → 효과 없음, 탈진 → 중독 10턴.
- 값이 정해진 재료만 `components.material_cost_gp`(소모면 `consumed: true`).
- 언어 관련 효과는 `dialogue_unlock`.

## 데이터에서 자동으로 되는 것

- `classes`: 이 주문을 고를 수 있는 클래스 주문 목록 id(클래스 `spellcasting.list`). 생성기가 목록 밖 주문을 오류로 막는다.
- `cast.cost: "reaction"` + `cast.trigger`: 반응 주문 — 아는 반응 목록에 자동으로 들어간다. **반응의 실제 동작은 `scripts/rules/reaction_queue.gd`에 주문별로 있다** — 새 반응 주문은 거기에 처리를 더하고 테스트한다.
- AI 사용: 효과로 자동 분류(`scripts/ai/spell_roles.gd`: 회복·공격 소마법·범위·자신 중심 지속 범위·빛). 바꾸려면 `"ai": {"role", "priority"}`.
- 아이콘: `"icon": {"glyph", "family"}`(문양은 `scenes/ui/action_icons.gd`의 그리기 목록, 색 계열은 피해 종류·heal·학파). 없으면 학파 색 별.
- 이름: `name.ko`·`name.en` 둘 다(검증기가 빈 이름을 오류로 본다). 기존 번역어와 겹치지 않게.

## 순서

1. 원문 주문을 찾아 위 규칙대로 변환한다. 기존 항목과 같은 모양(`spells.json`의 다른 주문 참고)으로 쓴다.
2. 효과 모델로 안 되면 `script` 이름을 정하고 `scripts/rules/effects/<id>.gd`를 구현한다.
3. 테스트: 판정 종류, 피해·회복 주사위, 범위 칸 수, 지속 턴, 상위 슬롯 효과를 확인하는 테스트를 하나 이상 추가한다.
4. 1차 범위 밖이면 `game_status`를 맞게 둔다(included / excluded_v1 / candidate_exclusion).
5. `/verify` — `tests/test_content_smoke.gd`가 포함(included) 주문을 모두 시험 장면에서 시전해 스크립트 오류를 찾는다.
6. `godot --headless --path . -s res://tools/content_report.gd`로 현황표(미구현 스크립트·아이콘 없는 주문)를, `res://tools/spells_table.gd`로 주문 변환표(`docs/rules/spells_table.md`)를 새로 만든다. 게임 메모 열은 주문 `notes_ko`다.

## 보고

주문별로 변환 결과 한 줄(시전·사거리·범위·지속·판정), 새 스크립트, 원문과 다르게 처리한 점과 이유.
