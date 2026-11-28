# 프로젝트: SRD 5.2 쿼터뷰 파티 RPG (Godot 4)

BG3류 CRPG. 타일 격자 + 2D 일러스트 3/4 탑뷰(위에서 살짝 비스듬히 내려다보는 시점, 카메라 회전 없음), 실시간 탐험 + 4인 파티 턴제 전투.
규칙은 SRD 5.2.1을 BG3식으로 개편한 룰북을 따른다.

## 규칙의 원천 (가장 중요)

- 모든 게임 규칙은 `docs/rules/rulebook.md`가 정한다. 코드와 룰북이 다르면 룰북이 맞다.
- 수치는 BG3 우선(2026-11-24): BG3와 SRD 5.2가 다르면 BG3. SRD는 BG3에 없는 콘텐츠 수치와 라이선스 근거로만 쓴다.
- 주문 변환표는 `docs/rules/spells_table.md`(데이터에서 생성 — `godot --headless --path . -s res://tools/spells_table.gd`, 손으로 고치지 않는다), 주문 데이터는 `data/content/spells.json`.
- SRD 원문 수치는 `docs/srd/`(SRD 5.2.1 마크다운)에서 확인한다. 기억에 의존하지 않는다.
- 룰북에 없는 규칙이 필요하면 지어내지 말고 사용자에게 묻는다. 결정되면 `docs/rules/changes.md`에 날짜·내용·이유를 남긴다.
- 우선순위: 구체 규칙 > 일반 규칙, 룰북 결정 기록 > SRD 원문, 데이터 > 스크립트.
- 룰북은 길다. 필요한 단계만 찾아 읽는다.
  1 설정 · 2 판정 분류 · 3 전투·행동 경제 · 4 환경·상태이상·범위 · 5 탐험 · 6 캐릭터·주문 변환 · 7 휴식·사망 · 8 구현 사양 · 9 검증·악용 방지

## 자주 쓰는 수치

- 1칸 = 5피트 = 1.5m. 거리 = max(|dx|, |dy|). 대각선 1칸, 벽 모서리 대각선 통과 불가.
- 1턴 = 6초. 1분 = 10턴, 10분 = 100턴, 1시간 이상 = 긴 휴식까지.
- 주문 범위·시야 원뿔은 매끄러운 도형(Area.cov_*): 원 반지름 N + 0.5칸, 원뿔 반각 atan(1/2)(시야는 45°), 칸 덮인 비율 25%↑면 포함(걸친 칸도 그냥 맞고, 시야에서도 보인다 — 보너스 없음), 미만 제외.
  옛 칸 마스크(원 dx² + dy² ≤ N² + N)는 함정·오라 등에 남아 있다. 큰 생물(큼 2×2·거대 3×3)은 점유 칸 중 가장 많이 덮인 칸으로.
- 이니셔티브 = d4 + 민첩(BG3). 사거리 상한 12칸(18m), 무기 먼 사거리 없음, 던지기 사거리는 근력·무게 공식(Physics.throw_range_tiles).
- 높이 1단계 = 5피트. 2단계 이상 높으면 명중 +2, 낮으면 −2.
- 표면 연쇄 상한: 깊이 3, 한 번에 64칸.

## 아키텍처 (룰북 8단계)

- 오토로드: `RulesDB`(JSON 로드·스키마 검사), `Dice`(시드 난수·굴림 로그), `EventBus`(훅 시그널).
- 노드·스크립트: `GridWorld`(칸 데이터만), `TurnManager`, `SurfaceSystem`, `Creature`, `Resolver`(상태 없음), `ReactionQueue`.
- 규칙 엔진은 화면 좌표를 모른다. 표현 계층(`scenes/`)은 판정 결과만 구독한다.
- 모든 규칙 데이터는 효과 모델로 쓴다: 훅 → 조건 → 대상·범위 → 효과 목록.
  효과 종류는 룰북 8단계 목록 안에서만 쓴다. 새 종류가 필요하면 엔진에 먼저 추가하고 `changes.md`에 기록한다.
- 효과 모델로 표현이 안 되는 것만 데이터에 `"script": "<id>"`를 달고 `res://scripts/rules/effects/<id>.gd`에 구현한다.
- 클래스·종족 기능은 코드에 이름을 적지 않는다(룰북 1단계 클래스 확장 원칙): 엔진은 `has_cap("<능력 태그>")`로 검사하고,
  기능 데이터가 `caps`·`grants`·`choice_kind`·`toggle`·`kind reaction`·`icon/glyph/target/explore`·`ai.when`으로 장치를 고른다(`/add-class` 표).
  소지품은 캐릭터마다(c.inventory, 캠프 보관함 world.stash — scripts/rules/interact.gd), 장비 칸·마법 물품은 scripts/rules/equipment.gd(명세 equipment → 생성기가 AC·무기·착용 효과).
  준비 주문 교체·주문서 학습·의식은 scripts/rules/spell_prep.gd(클래스 `spellcasting.swap` — 준비형은 out_of_combat로 전투 밖 언제나, 아는 주문형은 레벨 업 때 1개, 준비 수 `prepared` = 표 또는 "level_plus_ability", 화면 scenes/ui/spellbook_window.gd — K).
  추천 빌드는 클래스 `default_build`, AI 주문은 주문 데이터로 분류(scripts/ai/spell_roles.gd), 주문 아이콘은 주문 `icon`.

## 폴더

```text
res://
  data/rules/     conditions.json surfaces.json reactions.json materials.json actions.json weapon_actions.json
                  progression.json(레벨 상한 12·XP·숙련 보너스·멀티클래스 슬롯표 단일 출처) capabilities.json(능력 태그 — 엔진 메커니즘 이름)
  data/content/   spells.json weapons.json armor.json items.json feats.json backgrounds.json species.json shops.json terrain_presets.json
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
  자동 점검 테스트(새 콘텐츠 자동 포함): tests/test_class_pipeline.gd(모든 클래스 1~상한 레벨 생성·데이터만으로 만든 클래스), tests/test_content_smoke.gd(포함 주문 전부 시전·쓰는 아이템 전부 사용).
  콘텐츠 현황표: `godot --headless --path . -s res://tools/content_report.gd` → docs/content_status.md(기능별 동작 장치, '설명만'·미구현 표시).
- 규칙 코드를 바꾸면 `tests/`에 테스트를 더한다.
- 한 번에 한 기능. 큰 작업은 계획을 먼저 보여 주고 확인받는다.
- 작업이 끝나면 바꾼 것, 관련 룰북 항목, 남은 일을 짧게 보고한다.

## 라이선스

- SRD 콘텐츠는 `"source": "SRD 5.2.1"`, 자체 콘텐츠는 `"source": "original"`.
- BG3 고유 이름·캐릭터·지명·설명 문구는 쓰지 않는다(규칙 구조만 참고). 금지어는 `tools/banned_names.txt`.
- 크레딧에 SRD 저작자 표시 문장을 그대로 넣는다(`spells.json`의 `attribution`).

## 그래픽·입력 (데이터와 맞물리는 부분)

- 시점: 3/4 탑뷰, 표현 계층은 3D(scenes/battle/view3d.gd — 1칸 = 1유닛, 높이 1단계 = 1유닛, 직교 카메라가 남쪽 위 51.3°에서 내려다봄, 회전 없음).
  확대 1에서 가로 1칸 = 64px, 높이 1단계 = 40px, 바닥 세로 1칸 ≈ 50px. 벽 2.8유닛(방 남쪽 벽은 0.5로 잘라 냄). 칸 고르기는 카메라 광선(view3d.pick).
  바닥·벽·절벽은 그물(map_view.gd, terrain.gdshader — 캐릭터 앞 벽은 체크무늬로 비침, floor.gdshader — 종류가 다른 바닥 경계를 흔들어 맞물리고 변형 a·b를 얼룩으로 섞음, overlay.gdshader — 물·얼음·진흙 가장자리를 웅덩이처럼), 캐릭터·소품은 세운 판(Sprite3D, 세로 1.6배 — scenes/kit/kit3d.gd), 바닥 무늬는 눕힌 판.
  자연 지형(맵 `art.terrain: "natural"`, terrain_natural.gd): 맵 전체를 칸당 5×5 점의 한 그물로 — 높이 차 1단계 이웃은 부드러운 비탈, 2단계 이상은
  외곽선을 잡음으로 흔들고 그물을 다듬어 둥글고 울퉁불퉁한 가파른 바위 경사(floor.gdshader가 기울기로 바위 그림 `art.cliff_rock` = wall_cave 등을 섞음),
  절벽 위·아래 풀·바위 자동 장식(`art.cliff_decor`), 오르기 지점 절벽 면에 사다리(`art.climb_art`). 비탈은 이어진 칸 높이를 넓게 평균해 곧고 완만하게 그리고,
  캐릭터·소품·하이라이트는 그려진 바닥(map_view.ground_at)에 선다. 규칙 높이는 칸 정수 그대로. 그림자는 북서쪽 햇빛 하나로(드리운 그림자·면 음영).
  지형 프리셋 도장: 맵 `stamps`(`data/content/terrain_presets.json`, scripts/rules/map_stamps.gd — 높이·재질·오르기 지점·빛·바닥·소품을 한꺼번에, 돌리기·뒤집기·base). 모음 맵 terrain_presets_demo, 시범 맵 hill_path.
  도트 화면(scenes/battle/pixel_view.gd): 1칸 = 32도트(그림 1도트 = 세계 1/32유닛 = 화면 2 × 확대 px). 확대는 단계로 끊는다(ZOOM_STEPS 0.5·1·1.5·2 — 그림 1도트 = 화면 정수 칸, 굵고 얇은 도트가 섞이지 않게).
  3D 세계를 그림 도트 절반 크기 화소의 SubViewport에 그려(몬스터만 촘촘한 도트용) 가장 가까운 점으로 확대, 도트 카메라는 그림 도트 격자에 맞추고 끝수만큼 그림을 밀어 떨림 없음,
  깊이 차이 외곽선(pixel_outline.gdshader — 검은 선 대신 윤곽 안쪽 1도트를 제 색의 어두운 쪽으로 곱하는 sel-out, 화소 단위로 재고 두께만 1도트라 촘촘한 몬스터도 고른 굵기.
  잔풀·꽃·돌멩이 Kit3D.NO_OUTLINE, 빛을 내는 물건(불·초·등·수정) Kit3D.GLOWING은 깊이를 쓰지 않아 외곽선 없음. 컷아웃 부위·몬스터 변환본은 따로 테두리를 두르지 않는다).
  바닥·물·자연 지형 바위는 그림을 화면 줄에 맞춰 입힌다(바닥 세로 = z × sin, 바위 = 화면 방향 투영) — 그림 1줄 = 화면 1도트 줄. 키트 그림은 도트 변환본 assets/pixel_kit(tools/pixelize_kit.py — 조각마다 쿠와하라 → 반 크기 → 시트 팔레트 → 외톨이 점 지우기 → 2배 확대, 원본과 같은 크기라
  좌표 그대로, DungeonKit.art_dir로 바꿔 낌). 그림 원본을 고치면 변환을 다시 돌린다. 화면 단계 팔레트+Bayer 디더(pixel_post.gdshader, assets/pixel/palette.png)는 기본 꺼짐.
  원래 카메라는 광선 고르기·화면 투영용으로 남고 본 화면 3D 그리기만 끈다. UI는 원래 해상도. 끄기·조절 `--pixel=<1도트 px, 0 = 끔> --pixel_ss --pixel_art=0(원본 그림) --pixel_palette=1 --pixel_outline=0`.
  어우러짐(도트 화면): 바닥 경계는 덩어리 방식(floor.gdshader — 둘레 3×3 칸의 둥근 영향 + 바닥별 잡음 중 큰 바닥, 1도트 격자에 맞춰 딱 끊고 어두운 쪽 경계에 그늘).
  흩뿌림 장식(map_view._build_scatter — 새 도트 그림 assets/pixel_decor, tools/make_decor.py가 바닥 색에서 뽑아 그림): 키트 바닥 id별 기본표 SCATTER,
  3칸 얼룩 밀도·덤불 무리, 다른 바닥과 맞닿은 풀 칸은 경계 쪽에 큰 덤불. 맵 `art.scatter`(false = 끔, {바닥 id: [개수, [[id, 무게]...]]})·`art.scatter_density`.
  물·얼음·진흙 표면도 덩어리 방식(overlay.gdshader — 둥근 웅덩이, 물가 밝은 젖은 테·안쪽 깊이 띠, 물결 빛 점 반짝임 SURFACE_SHIMMER).
  맵 둘레(map_view._build_surround, 규칙 밖 그림만): 검은 바탕 대신 갈 수 없지만 이어져 보이는 지형 — 맵 밖 16칸에 맵 바닥과 이어 섞이는 바닥(둘레 바닥 + 얼룩,
  floor.gdshader cell_origin), 경계 바로 바깥 2.6칸은 지형에 맞는 큰 나무·바위로 빽빽하게 막고(남쪽 = 화면 앞은 1칸 띄우고 낮은 바위·덤불), 그 너머는 드문 나무·바위·풀,
  먼 끝만 살짝 어둡게. 지형 SURROUND_BIOMES: 풀 바닥 40%↑ forest, 아니면 rocky. 맵 `art.surround`(false = 끔, {biome, floor, patch, wall/low/far, width, density}).
  자연 지형이면 가장자리 벽 칸(경계)은 벽 대신 둘레로 덮는다(규칙상 막힘 그대로). 카메라가 보는 점은 맵 안으로 묶는다(battle_scene._apply_camera).
  폐허 벽(블록 지형 + 둘레 + 돌벽, 맵 `art.ruin`): 벽 높이를 칸마다 들쭉날쭉(그림만 — map_view._vis_top, 무너진 홈), 윗면은 칸마다 크기·높이가 다른 윗돌 블록 그물(map_view._ruin_cap — 돌마다 윗면 + 카메라에 보이는 앞면, 사이 줄눈, 재질 새 그림 assets/pixel_decor/ruin_stone.png 돌·이끼),
  벽면 덩굴·이끼·뿌리, 밑동 잔해·풀, 윗면 풀(RUIN_DECOR).
  수관 그늘(map_view._build_canopy): 나무(tree_*)마다 수관 크기 그늘을 칸당 4화소 그림으로 모아 바닥 셰이더(맵·둘레)에 — 그늘 두 단계, 잎 사이 빛 점이 바람에 흐름.
  맵 안 숲: 맵 안 나무 소품 칸은 통행 막힘(flags impassable — 그림과 규칙을 맞춘다. hill_path 나무 무리).
  빛과 그림자 층(pixel_light.gdshader — 도트 카메라 앞 판 두 장, 화면 깊이로 세계 위치를 되짚어 빛 지도 map_view._build_lighting을 찾음, 그림만·규칙 빛 단계 그대로):
  곱하기 판 = 빛 단계로 색 틀기(밝음 따뜻하게·어스름/어둠 차갑게) + 드리운 그림자(북서쪽 해, 벽 윗면·높은 땅이 남동쪽으로, 두 단계, 높이 바뀔 때만 계산) + 가장자리 살짝 어둡게,
  더하기 판 = 광원 빛 웅덩이(광원 이름으로 색 LIGHT_COLORS, 3단계로 끊어 도트 경계, 불은 일렁임, 광원 뺀 기본 빛이 밝은 곳일수록 약하게). `--pixel_light=0`이면 끔.
  바람(scenes/kit/sway.gdshader — Kit3D.SWAY 표의 풀·꽃·덤불·나무 판 위쪽이 흔들림, 자리마다 잔물결 + 지나가는 돌풍, 나무·덤불은 잎 반짝임 LEAFY). 도트 화면 기본, `--wind=0`이면 끔.
  그림체 방향(2026-11-26): 첨부 참고 화풍처럼 격자가 드러나지 않게 어우러진 깔끔한 도트. 새 그림 추가 허용, 시간대·분위기는 지금 그대로.
  캡처: `--shot=<png> --frames=<n>`, 카메라 고정 `--cam=x,y --zoom=<배율>`. 맵 그림은 던전 에셋 키트로 그린다:
  맵 데이터 `art`(wall·wall_top·cliff·floors[범례 글자 → 키트 바닥]·props[키트 물건 at/id/v]). 키트 목록은 `docs/from_dungeon_and_stone/DUNGEON_KIT.md`·`asset_library/`.
- 캐릭터 그림: 종족이 있는 사람(파티·동료·NPC)은 2D 일러스트 컷아웃 — Skeleton2D 뼈대(scenes/battle/cutout_rig.gd)를 SubViewport로 그려 세운 판에 입힘(actor_view.gd),
  체형 틀·뼈·애니메이션 data/rules/body_templates.json, 종족 모습·재질 색·무기/갑옷 모양 data/rules/cutout_looks.json, 모습 계산 scripts/rules/cutout.gd,
  부위 그림 assets/cutout/<체형>/<부위>.png(없으면 코드로 그린 임시 그림, 규격 docs/art/cutout_spec.md), 초상·소지품 전신은 cutout_portraits.gd(앞모습). 몬스터는 그림(art.image), art.cutout = false면 걷기 시트.
  도트 그림 모드(도트 화면 기본, `--pixel_chars=0`이면 매끈한 그림): 뼈대를 도트 배율(맵 = 그림 1화소가 화면 1도트, 초상 = PORTRAIT_DOT 0.5)로 줄여 그리고(CutoutRig.dot·canvas_px),
  부위마다 3단 음영(왼쪽 위 밝은 테·본색·오른쪽 아래 그늘 테, 밝은 쪽 따뜻하게·그늘 차갑게, 부위 테두리 없음 — 몸 윤곽은 화면 외곽선), 갑옷 무늬·눈은 도트 점. 장비 구조(부위 갈아 끼우기·재질 색·모양·등급 빛)는 그대로.
  몬스터 그림은 도트 변환본 assets/pixel_actors(tools/pixelize_actors.py — 같은 이름의 큰 원화 assets/monsters(에셋팩 반실사)에서, 키 84 × 크기 배율 화소로 축소(몬스터만 지형 도트보다 2배 촘촘 — 2026-11-27 결정; 2배 → 쿠와하라 → 평균), 대비 키우기(평균 밝기 유지), 명암 테(왼쪽 위 밝게·오른쪽 아래 어둡게), 그림별 팔레트, 테두리는 굽지 않음(화면 외곽선이 1도트로) — 그림 1화소 = 지형 도트 절반).
- 체형 틀: 보통(인간·엘프·드로우·하프엘프·하프오크·티플링·아스트란), 작은(하플링·노움), 드워프는 작은 체형 변형. 드래곤본은 보통 체형 임시(전용 틀은 나중), 골리앗은 없다.
- 장비는 `sprite_parts`로 부위를 바꿔 끼우고, 재질·등급은 색 바꾸기 셰이더로 표현한다.
- 화면 UI는 BG3 배치를 참고한다: 하단 단축 막대(scenes/ui/hotbar.gd), 왼쪽 세로 파티 초상, 위 이니셔티브 초상 줄, 오른쪽 위 원형 미니맵, 캐릭터·소지품 창(I — scenes/ui/character_sheet.gd: 위 탭 소지품(파티원 나란히)·캐릭터·주문서, 왼쪽 종족·클래스·능력치·상태·저항·특성, 가운데 장비 칸·방어도·무기별 명중/피해, 오른쪽 검색·정렬(최신·가치·무게·유형)·소지품 칸·무게 막대. 모든 동작은 누르면 나오는 메뉴로도 된다 — iPad).
  색·틀은 scenes/ui/ui_style.gd 하나로(어두운 갈색 바탕, 청동·금 테두리, 둥근 모서리, 채도 낮춘 색, 제목 명조체). 새 화면도 이 스타일을 쓴다.
- 입력은 '미리보기 → 확정' 상태기계 하나로 처리한다. 여러 대상 주문은 BG3식으로 대상을 하나씩 모아 다 차면 시전(Enter·[시전]으로 먼저, Spellcasting.target_plan). 마우스는 올리기 = 미리보기(대상 막대·확률), 클릭 = 실행, 우클릭(끌지 않음)·Esc = 취소, 우클릭 끌기 = 화면 이동. 키(BG3식, 자리 키 physical_keycode — 한글 입력 상태에서도): WASD 탐험 중 고른 캐릭터 직접 걷기(전투 중엔 화면 이동, 방향키도 화면 이동), 1~0 단축 막대 칸, Space 턴 끝, Z 점프, V 밀치기, H 모든 HP 보기·G 상호작용 물체 강조(켜고 끄기 — iPad 키보드라 누르고 있는 Shift·Alt를 쓰지 않는다, 미니맵 아래 같은 버튼), I·C 캐릭터, K 주문, L 로그. 터치는 첫 탭 = 미리보기, 같은 곳 두 번째 탭 = 실행, 길게 누르기 = 정보, 드래그 = 화면 이동, 핀치 = 확대.
  행동을 고르면 단축 막대 위에 설명 카드(scenes/ui/action_info.gd — 툴팁과 같은 글)가 떠 있다(마우스 올리기 대신). 터치면 자신 대상 행동도 첫 탭 = 고르기·카드, 같은 칸 다시 탭 = 실행. 고른 칸 다시 누르기·× = 취소.
  창·버튼은 터치 → 마우스 흉내로 받고(project.godot), 맵 입력 상태기계는 흉내 낸 마우스를 버린다.

## Godot

- Godot 4.7(GL Compatibility). 실행 파일: `godot` (다르면 여기를 고친다)
- 데이터 검증: `godot --headless --path . -s res://tools/validate_data.gd`
- 테스트: `godot --headless --path . -s res://tests/run_all.gd`
