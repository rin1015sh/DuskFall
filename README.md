# DuskFall

2D 3/4 쿼터뷰 격자 턴제 파티 던전 크롤러 (Godot 4.7, GL Compatibility). 규칙은 D&D 5판 SRD 5.2 예정.

## 여는 법

Godot 4.7을 켜고 프로젝트 관리자에서 **가져오기(Import)** → 이 폴더의 `project.godot`를 고른다. 처음 열 때 그림을 가져오느라 몇 분 걸린다.
아직 코드 · 메인 씬은 없다(실행 버튼을 누르면 메인 씬을 고르라고 한다).

## 들어 있는 것

던전 앤 스톤(이전 프로젝트)에서 옮겨 온 그림 · 소리 · 글꼴 — 모두 코드로 그린 WebP(투명 배경).

| 폴더 | 내용 |
|---|---|
| `assets/dungeon_kit` | 던전 에셋 키트 — 바닥 · 벽 · 문 · 소품 · 가구 · 식생 · 함정 · 빛 · 효과 288종(목록 `kit.json`, 설명 `docs/from_dungeon_and_stone/DUNGEON_KIT.md` · `asset_library/`) |
| `assets/floor` | 탐험 바닥 · 벽 · 소품 · 데칼 — 수정동굴 `f1` · 성채 `bf` · 빙하굴 `gc` · 탄광 `gm` · 묘 `it` · 묘지 `f2d` · 숲 `f2g` · 소굴 `f2b` · 사막 `f2r` · 늪 `f3` · 키트 재질 `kit` · 상자 `chest` (타일 표 참고 `reference/tiles.json`) |
| `assets/actors` | 맵 걷기 시트 — 종족 5 · 차림 53(`looks`) · 몬스터 270(`monsters`). 칸 72×108, 줄 = 아래 · 왼 · 오른 · 위, 칸 5 = 걸음 A · 반걸음 A · 섬 · 반걸음 B · 걸음 B, 원점 = 발 |
| `assets/monsters` | 몬스터 큰 그림 143종(전투 화면용 한 장씩) |
| `assets/party` | 탐험가 뒷모습 · 동작 7줄 시트 · 쓰러짐 |
| `assets/items` · `statuses` · `ui` | 아이템 아이콘 450 · 상태 아이콘 113 · 동전 |
| `assets/battle` | 전투 뒷그림 30 |
| `assets/town` · `city` | 도시 손그림 집 · 바닥 · 소품 · 시설 정면 · 실내 · 원경 · 음식 · 책 |
| `assets/shaders` | 셰이더(외곽선 · 바닥 번짐 · 수정 맥박 등) |
| `assets/fonts` | 송명 · Noto Sans KR(SIL OFL 1.1) |
| `assets/audio` | 효과음 · 걸음 · 분위기 99개(쓰인 곳 `docs/from_dungeon_and_stone/AUDIO.md`) — 받은 곳 라이선스 확인 전 공개 배포 금지 |

그림을 새로 그리는 도구(3D 점토 몸 → 손그림 마감)는 던전 앤 스톤 저장소 `tools/`에 남아 있다(그쪽 `docs/EXPORT_KIT.md`).
파일 이름에 이전 프로젝트의 지역 줄임 · 몬스터 id가 남아 있다 — 쓸 때 새 이름으로 바꾼다.
