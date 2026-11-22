# 프로젝트: SRD 5.2 쿼터뷰 파티 RPG (Godot 4)

BG3류 CRPG. 타일 격자 + 2D 일러스트 3/4 탑뷰(위에서 살짝 비스듬히 내려다보는 시점, 카메라 회전 없음), 실시간 탐험 + 4인 파티 턴제 전투.
규칙은 SRD 5.2.1을 BG3식으로 개편한 룰북을 따른다.

## 규칙의 원천 (가장 중요)

- 모든 게임 규칙은 `docs/rules/rulebook.md`가 정한다. 코드와 룰북이 다르면 룰북이 맞다.
- 주문 변환표는 `docs/rules/spells_table.md`, 주문 데이터는 `data/content/spells.json`.
- SRD 원문 수치는 `docs/srd/`(SRD 5.2.1 마크다운)에서 확인한다. 기억에 의존하지 않는다.
- 룰북에 없는 규칙이 필요하면 지어내지 말고 사용자에게 묻는다. 결정되면 `docs/rules/changes.md`에 날짜·내용·이유를 남긴다.
- 우선순위: 구체 규칙 > 일반 규칙, 룰북 결정 기록 > SRD 원문, 데이터 > 스크립트.
- 룰북은 길다. 필요한 단계만 찾아 읽는다.
  1 설정 · 2 판정 분류 · 3 전투·행동 경제 · 4 환경·상태이상·범위 · 5 탐험 · 6 캐릭터·주문 변환 · 7 휴식·사망 · 8 구현 사양 · 9 검증·악용 방지

## 자주 쓰는 수치

- 1칸 = 5피트 = 1.5m. 거리 = max(|dx|, |dy|). 대각선 1칸, 벽 모서리 대각선 통과 불가.
- 1턴 = 6초. 1분 = 10턴, 10분 = 100턴, 1시간 이상 = 긴 휴식까지.
- 주문 범위·시야 원뿔은 매끄러운 도형(Area.cov_*): 원 반지름 N + 0.5칸, 원뿔 반각 atan(1/2)(시야는 45°), 칸 덮인 비율 25%↑면 포함(걸친 칸도 그냥 맞고, 시야에서도 보인다 — 보너스 없음), 미만 제외.
  옛 칸 마스크(원 dx² + dy² ≤ N² + N)는 함정·오라 등에 남아 있다. 큰 생물(2×2)은 점유 칸 중 가장 많이 덮인 칸으로.
- 높이 1단계 = 5피트. 2단계 이상 높으면 명중 +2, 낮으면 −2.
- 표면 연쇄 상한: 깊이 3, 한 번에 64칸.

## 아키텍처 (룰북 8단계)

- 오토로드: `RulesDB`(JSON 로드·스키마 검사), `Dice`(시드 난수·굴림 로그), `EventBus`(훅 시그널).
- 노드·스크립트: `GridWorld`(칸 데이터만), `TurnManager`, `SurfaceSystem`, `Creature`, `Resolver`(상태 없음), `ReactionQueue`.
- 규칙 엔진은 화면 좌표를 모른다. 표현 계층(`scenes/`)은 판정 결과만 구독한다.
- 모든 규칙 데이터는 효과 모델로 쓴다: 훅 → 조건 → 대상·범위 → 효과 목록.
  효과 종류는 룰북 8단계 목록 안에서만 쓴다. 새 종류가 필요하면 엔진에 먼저 추가하고 `changes.md`에 기록한다.
- 효과 모델로 표현이 안 되는 것만 데이터에 `"script": "<id>"`를 달고 `res://scripts/rules/effects/<id>.gd`에 구현한다.

## 폴더

```text
res://
  data/rules/     conditions.json surfaces.json reactions.json materials.json actions.json weapon_actions.json
  data/content/   spells.json weapons.json armor.json items.json feats.json backgrounds.json species.json shops.json
  data/classes/   <class>.json
  data/monsters/  <monster>.json
  data/maps/      <map>.json
  data/dialogues/ <dialogue>.json (대화 노드·판정·효과)
  data/schema/    <kind>.schema.json
  scripts/rules/  엔진 코드, effects/ 스크립트 효과
  scenes/         표현(맵 씬, UI, 캐릭터). scenes/kit = 에셋 키트 창구(dungeon_kit.gd)
  assets/         그림·소리·글꼴(던전 앤 스톤에서 옮김). assets/dungeon_kit = 던전 에셋 키트(바닥·벽·소품 583종)
  tests/          헤드리스 테스트
  tools/          검증·변환 도구
  docs/           rules/ 룰북, srd/ 원문
```

## 작업 규칙

- 코드·데이터 키·ID는 영어 snake_case. 주석·문서·커밋 메시지는 한국어.
- 화면에 보이는 텍스트는 `{"ko": ..., "en": ...}` 둘 다 둔다.
- 콘텐츠 추가는 스킬로 한다: `/add-item` `/add-spell` `/add-class` `/add-origin` `/add-monster` `/add-surface` `/add-map`.
  점검은 `/rules-check`, 밸런스는 `/balance-check`, 검증은 `/verify`(커밋 직전에 자동 실행).
- 규칙 코드를 바꾸면 `tests/`에 테스트를 더한다.
- 한 번에 한 기능. 큰 작업은 계획을 먼저 보여 주고 확인받는다.
- 작업이 끝나면 바꾼 것, 관련 룰북 항목, 남은 일을 짧게 보고한다.

## 라이선스

- SRD 콘텐츠는 `"source": "SRD 5.2.1"`, 자체 콘텐츠는 `"source": "original"`.
- BG3 고유 이름·캐릭터·지명·설명 문구는 쓰지 않는다(규칙 구조만 참고). 금지어는 `tools/banned_names.txt`.
- 크레딧에 SRD 저작자 표시 문장을 그대로 넣는다(`spells.json`의 `attribution`).

## 그래픽·입력 (데이터와 맞물리는 부분)

- 시점: 3/4 탑뷰(scenes/battle/view3q.gd — 칸 64px 정사각형, 높이 1단계 = 화면 위로 40px, 벽 112px). 맵 그림은 던전 에셋 키트로 그린다:
  맵 데이터 `art`(wall·wall_top·cliff·floors[범례 글자 → 키트 바닥]·props[키트 물건 at/id/v]). 키트 목록은 `docs/from_dungeon_and_stone/DUNGEON_KIT.md`·`asset_library/`.
- 캐릭터 그림(지금): assets/actors 걷기 시트 4방향(아래·왼·오른·위). 최종은 2D 일러스트 컷아웃(Skeleton2D) — 룰북 1단계.
- 체형 틀: 보통(인간·엘프·티플링·오크), 작은(하플링·노움), 드워프는 작은 체형 변형. 드래곤본·골리앗은 없다.
- 장비는 `sprite_parts`로 부위를 바꿔 끼우고, 재질·등급은 색 바꾸기 셰이더로 표현한다.
- 화면 UI는 BG3 배치를 참고한다: 하단 단축 막대(scenes/ui/hotbar.gd), 왼쪽 세로 파티 초상, 위 이니셔티브 초상 줄, 오른쪽 위 원형 미니맵, 캐릭터·소지품 창(I).
  색·틀은 scenes/ui/ui_style.gd 하나로(어두운 갈색 바탕, 청동·금 테두리, 둥근 모서리, 채도 낮춘 색, 제목 명조체). 새 화면도 이 스타일을 쓴다.
- 입력은 '미리보기 → 확정' 상태기계 하나로 처리한다. 마우스는 올리기 = 미리보기, 클릭 = 실행. 터치는 첫 탭 = 미리보기, 같은 곳 두 번째 탭 = 실행, 길게 누르기 = 정보, 드래그 = 화면 이동, 핀치 = 확대.

## Godot

- Godot 4.7(GL Compatibility). 실행 파일: `godot` (다르면 여기를 고친다)
- 데이터 검증: `godot --headless --path . -s res://tools/validate_data.gd`
- 테스트: `godot --headless --path . -s res://tests/run_all.gd`
