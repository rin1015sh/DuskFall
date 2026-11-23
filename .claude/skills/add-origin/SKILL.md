---
name: add-origin
description: 종족(혈통 포함)·배경·재주를 추가하거나 고친다.
---

# 종족·배경·재주 추가

요청: $ARGUMENTS

## 먼저 읽을 것

- 룰북 6단계 종족·배경·재주 표와 결정 기록, 5단계 영감, 1단계 체형 틀.
- 원문: `docs/srd/04_CharacterOrigins.md`, `05_Feats.md`.

## 규칙

- 종족: 크기, 속도(칸), 암시야(칸), 특성은 기능과 같은 효과 모델. 체형 틀(medium / small / dwarf)을 정한다. 드래곤본·골리앗은 넣지 않는다.
- 배경: 기능 숙련 2, 출신 재주 1, 도구 숙련 없음, 장비는 꾸러미 하나로 고정, 영감 목표 3~5개(대화·행동 태그). 능력치 보너스는 배경과 무관하게 자유 배분(+2/+1 또는 +1/+1/+1).
- 재주: 출신·일반·전투 방식 구분. Grappler처럼 삭제된 규칙에 기대는 재주는 넣지 않는다.
- 자체 콘텐츠는 새 이름·새 설명, `"source": "original"`.

## 데이터에서 자동으로 되는 것(지금 엔진이 읽는 필드)

- 종족: `size`, `speed_tiles`, `darkvision_tiles`, `resistances`, `save_advantage_vs`, `save_advantage_abilities`, `condition_immunities`(상태 id만), `hp_per_level`,
  `features[]`(클래스 기능과 같은 장치 — `caps`·`script`·`resource`·`hook` 등, `/add-class`의 기능 동작 장치 표), `resources`, `spells[{level, spell}]`, `origin_feat_choice`, 혈통은 `parent`.
- 배경: `skills`, `feat`(출신 재주). `equipment`·`gold`·`inspiration_goals`는 아직 엔진이 쓰지 않는다.
- 재주: `tags`(능력 태그 — `data/rules/capabilities.json`), 주문 재주는 `spell_list`·`cantrips`·`level1_spells`(명세 키 = 재주 id로 고른 주문, 1레벨 주문은 긴 휴식마다 1회 타고난 시전).
  `skill_choices`·`ability_increase`·`effects_ko`는 아직 엔진이 쓰지 않는다 — 동작이 필요하면 장치를 먼저 만든다.

## 순서

1. 원문 또는 요청을 위 규칙으로 변환한 표를 보여 주고 확인받는다.
2. `species.json` / `backgrounds.json` / `feats.json`에 추가한다. 종족은 머리·피부색·부가 부위(꼬리·뿔 등) 그림 목록을 남긴다.
3. 이름은 `name.ko`·`name.en` 둘 다. 테스트(캐릭터 생성 시 특성 적용)와 `/verify`.
