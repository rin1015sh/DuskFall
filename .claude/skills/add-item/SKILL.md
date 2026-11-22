---
name: add-item
description: 무기·갑옷·물약·두루마리·도구·음식(보급품)·마법 물품을 게임 데이터에 추가한다. "아이템 추가", "무기 만들기", "물약 넣기" 같은 요청에 쓴다.
---

# 아이템 추가

요청: $ARGUMENTS

## 먼저 읽을 것

- 룰북 3단계(행동 비용: 물약 마시기 보너스·먹이기 행동, 던지기 행동), 4단계(재질 태그, 던지기 무게 피해), 7단계(보급품·치유 물약·두루마리), 8단계(효과 모델).
- SRD에 있는 아이템이면 `docs/srd/06_Equipment.md` 또는 `10_MagicItems.md`에서 원문 수치를 가져온다.

## 순서

1. 종류를 정한다: weapon / armor / shield / consumable(potion·scroll·food) / tool / magic / misc.
2. SRD 아이템이면 원문 수치 그대로, `"source": "SRD 5.2.1"`. 자체 아이템이면 비슷한 SRD 아이템을 기준으로 수치를 제안하고 근거를 한 줄로 쓴 뒤 사용자 확인을 받는다. `"source": "original"`.
3. 해당 파일(`weapons.json`, `armor.json`, `items.json`)에 추가한다. 공통 필드:
   `id`, `name{ko,en}`, `category`, `rarity`, `weight_kg`(파운드 × 0.45), `price_gp`, `material`(4단계 재질 태그), `source`.
4. 종류별 필드:
   - 무기: `damage`, `damage_type`, `properties`(2024 속성: finesse·light·heavy·thrown·two_handed·versatile·reach·loading·ammunition), `mastery`, `range_tiles{normal,long}`, `sprite_parts`.
     가벼운 무기 보조 공격은 피해에 능력 수정치를 더하지 않는다(Two-Weapon Fighting 재주가 있으면 더함).
   - 갑옷: `ac_base`, `dex_cap`, `str_required`, `stealth_disadvantage`, `armor_category`(전투 중 교체 불가), `sprite_parts`.
   - 물약: 마시기 효과 + `throw`: 착지 칸과 직교 인접 4칸 안 모두에게 전체 효과, 치유 물약은 연소 해제, 생물을 직접 노리면 던지기 피해 1(룰북 9단계 결정).
   - 음식: `camp_supplies` 값(긴 휴식 1회 = 40).
   - 도구: 도둑 도구(자물쇠, 실패 시 파손), 함정 해체 도구(실패 시 소모 + 함정 발동, 같은 함정 재시도 불가).
5. 효과는 8단계 효과 모델로 쓴다. 표현이 안 되면 `script` + 효과 스크립트 + 테스트를 만든다.
6. 장비 아이템은 `sprite_parts`가 가리키는 부위 그림이 `art/`에 없으면 임시 그림 자리표시를 만들고 목록에 남긴다.
7. `/verify`를 돌린다.

## 보고

추가한 아이템 표(이름, 핵심 수치, 출처), 새로 만든 스크립트, 필요한 그림 목록.
