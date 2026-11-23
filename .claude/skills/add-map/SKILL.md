---
name: add-map
description: 새 맵(구역)을 설계하고 만든다. 지형·높이·빛·표면·전투 구역·함정·자물쇠·숨긴 물건·NPC·동료·전리품 배치까지 포함한다.
---

# 맵 추가

요청: $ARGUMENTS

## 먼저 읽을 것

- 룰북 1단계(쿼터뷰 고정, 벽 투명화), 3단계(전투 구역, 이동), 4단계(태그·빛·높이·표면), 5단계(시야 원뿔, 함정·자물쇠, 절도·소유, 낮밤 없음), 7단계(캠프 불가 구역, 보급품 배치), 9단계(예시 전투, 악용 사례).

## 구조

- 맵 한 장 = `data/maps/<id>.json`(스키마 `data/schema/map.schema.json`). 씬 파일은 없다 — 표현 계층(scenes/battle/map_view.gd, 3D)이 데이터를 읽어 그린다.
- 규칙 데이터: 글자 지도 `rows` + 범례 `legend`(글자 → material·height·surface·flags), `light`·`light_rects`·`light_sources`, `flags`·`flag_rects`
  (difficult·impassable·climb·no_camp), `zones`(전투 구역)·`zone_rewards`, `objects`(물체·상자·자물쇠), `traps`, `examines`, `spawns`(파티·몬스터·동료·대화), `transitions`.
- 그림: `art` — wall·wall_top·cliff·floors(범례 글자 → 키트 바닥)·props(키트 물건 at/id/v). 키트 목록은 `docs/from_dungeon_and_stone/DUNGEON_KIT.md`.
- 언덕·절벽 지형: `art.terrain: "natural"`이면 높이 차 1단계 = 부드러운 비탈, 2단계 이상 = 바위 절벽(`art.cliff_rock`, 자동 장식 `art.cliff_decor`, 사다리 `art.climb_art`).
- 지형 프리셋 도장: `stamps: [{"preset", "at": [x, y], "rot": 0|90|180|270, "flip", "base"}]` — `data/content/terrain_presets.json`의 프리셋
  (낮은 턱·작은/큰 둔덕·능선·긴 비탈길·비탈길 고원·바위 고원·절벽 띠·동굴 절벽·바위 노두·전망 바위)을 찍으면 높이·재질·오르기 지점·빛·바닥 그림·소품이 한꺼번에 들어간다.
  모음 미리보기: 맵 `terrain_presets_demo`(`--map=terrain_presets_demo`). 새 모양은 프리셋을 추가해 쓴다(id 영어 snake_case, 이름 ko/en, `"source": "original"`).
- 캡처로 확인: `godot --path . res://scenes/battle/battle_scene.tscn -- --map=<id> --cam=x,y --zoom=0.6 --shot=<png> --frames=40`(화면이 필요하면 xvfb-run).

## 설계 점검표

- 전투 구역마다: 높이 차 1곳 이상, 환경 상호작용 1개 이상(물·기름·마른 풀·기름통 등), 은신 경로가 되는 어두운 길, 큰 생물이 지나갈 2칸 통로 여부.
- 판정에 실패해도 진행이 막히지 않는 대체 경로(2단계).
- 함정은 발견 뒤 발동 범위가 보이게, 해제 말고 다른 해법(던져서 발동, 점프, 파괴)도 가능하게.
- 보급품은 구역마다 긴 휴식 1~2회분. 캠프 불가 구역을 정한다.
- 고정 카메라에서 가림 문제가 없는지(카메라 쪽 벽 높이).
- 숨긴 물건·함정은 수동 지각 반경 3칸 안에 길이 지나가는지.

## 순서

1. 맵 개요(목적, 동선, 전투 구역, 핵심 상호작용)를 글과 간단한 칸 그림(텍스트)으로 보여 주고 확인받는다.
2. 씬과 데이터를 만든다(그림은 임시 타일로 시작).
3. 검증: 모든 구역 도달 가능, 적대 생물이 모두 전투 구역 안, 고립 칸 없음, 2×2 생물 경로, 빛 레이어 계산.
4. 전투 구역마다 `/balance-check`.
5. `/verify`.
