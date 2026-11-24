---
name: add-class
description: 클래스·하위 클래스·클래스 기능을 추가하거나 레벨을 늘린다. 바드·레인저 같은 새 클래스, 자체 하위 클래스, 상한 레벨 확장에 쓴다.
---

# 클래스·하위 클래스 추가

요청: $ARGUMENTS

새 클래스는 **데이터만으로** 들어가야 한다(룰북 1단계 '클래스 확장 원칙'). 코드에 클래스 id나 기능 id를 적지 않는다.
엔진이 모르는 메커니즘이 필요할 때만 엔진에 능력 태그를 추가하거나 효과 스크립트를 만든다.

## 먼저 읽을 것

- 룰북 6단계(공통 변환 규칙, 기존 클래스 표, 결정 기록), 2단계(판정 분류), 3단계(행동 경제·반응), 7단계(휴식 회복), 8단계(훅 목록).
- 원문: `docs/srd/03_Classes/<번호>_<Class>.md`(예: `08_Ranger.md`). 레벨 상한은 `data/rules/progression.json`의 `level_cap`(지금 5).
- 기존 클래스 데이터(`data/classes/fighter.json` 등)와 `docs/content_status.md`(기능별 동작 장치 현황), `data/rules/capabilities.json`(쓸 수 있는 능력 태그).

## 순서

1. 원문에서 기본 특성(생명 주사위, 내성, 기능 목록, 무기·갑옷 훈련, 무기 마스터리 개수)과 1~상한 레벨 기능을 표로 뽑는다.
2. 기능마다 룰북 6단계 형식으로 변환안을 만든다: 원문 요지 / 내 게임 안 / 구분([원문 유지]·[변형]·[자체]) / 이유 / **동작 장치**(아래 표).
   - 거리·시간은 공통 변환, 반응형 기능은 반응 설정 대상, 도구 숙련·언어는 삭제, HP는 고정값.
   - 서술형 기능은 1차 제외하거나 대화 분기·감지·소환·표면 같은 기존 시스템으로 바꾼다.
   - SRD에 없는 하위 클래스는 새 이름·새 설명으로 자체 설계(`"source": "original"`). BG3 하위 클래스 이름은 쓰지 않는다.
3. 변환표를 사용자에게 보여 주고 확인받는다. [변형]·[자체] 항목과 **새 능력 태그·새 스크립트가 필요한 기능**은 꼭 짚는다.
4. `data/classes/<id>.json`을 쓴다(스키마 `data/schema/class.schema.json`).
5. 엔진 작업이 필요하면 먼저 한다: 새 메커니즘 → 엔진에 `has_cap("<태그>")` 처리 + `capabilities.json`에 태그 추가 + 테스트,
   또는 `scripts/rules/effects/<id>.gd` 효과 스크립트 + 테스트. 결정은 `docs/rules/changes.md`에.
6. 클래스 주문 목록이 필요하면 `/add-spell`로 주문 데이터 `classes`에 클래스 목록 id를 더한다(새 주문도).
7. `godot --headless --path . -s res://tools/content_report.gd`로 현황표를 새로 만들어 '설명만'으로 남은 기능이 없는지 본다.
8. `/verify`(데이터 검증 + 테스트 — `tests/test_class_pipeline.gd`가 새 클래스를 1~상한 레벨로 자동 생성해 본다).

## 클래스 데이터 필드

| 필드 | 뜻 |
| --- | --- |
| `hit_die`, `primary`, `saves`, `skills{choose, from}` | 기본 특성 |
| `weapon_training`, `armor_training` | 훈련(simple·martial·light·medium·heavy·shield 또는 무기 id) |
| `weapon_mastery` | 레벨 → 마스터리 무기 수 |
| `asi_levels` | 능력치 향상 레벨 |
| `resources[]` | `{id, max(숫자·레벨표·"proficiency_bonus"), recharge(short·short_one·long)}` |
| `spellcasting` | `ability`, `type`(prepared·spellbook·known), `list`(주문 데이터 classes 값), `cantrips`(레벨표)·`prepared`(아는 주문형은 레벨표, BG3 준비형은 "level_plus_ability" = 클래스 레벨 + 능력 수정치), `slots`(레벨 → [1레벨 슬롯 수, …] — 절반 시전자는 표만 다르다), `slot_recharge`(long·short — 계약형), `swap`(준비 교체: `out_of_combat` 전투 밖 언제나 — BG3 준비형, `long_rest` 긴 휴식 뒤 바꿀 수 −1 전부·n개, `level_up` 레벨 업 때 — BG3 아는 주문형 1 — spell_prep.gd), 주문서형은 `spellbook`({"1": 6, "per_level": 2}) |
| `features[]`, `subclasses[]{id, name, level, features, always_prepared}` | 기능(아래), 하위 클래스(고르는 레벨 = `level`) |
| `default_build` | 추천 빌드(동료·시험·생성 화면 시작값). 생성 명세에서 class·level·team을 뺀 것 — 종족·배경·능력치·보너스·기능·하위 클래스·고르는 기능·주문·장비 |
| `ai_role` | melee·ranged·caster·healer(AI 고지 찾기·위치) |
| `art.sheet` | 임시 걷기 시트(assets/actors) |
| `color` | 클래스 기능 아이콘 색 `#rrggbb` |

## 기능 동작 장치

| 장치 | 필드 | 쓰는 곳 |
| --- | --- | --- |
| 능력 태그 | `caps: [...]` | 엔진이 검사하는 메커니즘(행운·추가 보너스 행동·등반·소마법 강화 등 — `capabilities.json`) |
| 부여 | `grants: {attacks_per_action, crit_threshold, weapon_training, armor_training, extra_cantrips, caps, advantage, spellbook_school}` | 생성기가 적용(spellbook_school = 주문서 학파 무료 주문) |
| 고르기 | `choices` + `choice_kind`(feat·expertise·option) + `choice_grants{선택: grants}` | 명세 키 = 기능 id |
| 직접 쓰기 | `kind`(action·bonus_action·free) 또는 `usable: true` + `script` + `resource` | 단축 막대(`icon`, `glyph`, `target`, `explore`) |
| 반응 | `kind: "reaction"` + `hook` + `script` | 반응 목록·반응 설정에 자동 |
| 훅 | `hook`(on_hit 등) + `script` | 판정 중 자동 |
| 상시 설정 | `toggle{values[{id, name}], desc}` | 상시 발동 탭, 값은 `c.options[기능 id]` |
| AI | `ai{when: hp_below_half·foes_2plus·never}` | AI가 자동 사용 |
| 레벨표 | `dice_by_level` | 급소 공격처럼 레벨마다 주사위 |
| 다른 곳 처리 | `handled_by: "…"` | 생성기·다른 스크립트가 처리(현황표에 표시) |
| 보류 | `status: "deferred"` | 표시만 |

## 보고

기능 변환표(동작 장치 포함), 새 능력 태그·스크립트, 사용자 결정이 필요한 항목, 현황표의 '설명만' 수.
