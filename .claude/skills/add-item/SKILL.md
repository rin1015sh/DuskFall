---
name: add-item
description: 무기·갑옷·물약·두루마리·도구·음식(보급품)·마법 물품을 게임 데이터에 추가한다. "아이템 추가", "무기 만들기", "물약 넣기" 같은 요청에 쓴다.
---

# 아이템 추가

요청: $ARGUMENTS

## 먼저 읽을 것

- 룰북 3단계(행동 비용: 물약 마시기 보너스·먹이기 행동, 던지기 행동, 두루마리 행동), 4단계(재질 태그, 던지기 무게 피해), 6단계(주문 두루마리), 7단계(보급품·치유 물약), 8단계(효과 모델).
- SRD 아이템이면 `docs/srd/06_Equipment.md` 또는 `10_MagicItems.md`에서 원문 수치를 가져온다.
- 스키마: `data/schema/weapon.schema.json`, `armor.schema.json`, `item.schema.json`.

## 순서

1. 파일을 정한다: 무기 `weapons.json`, 갑옷·방패 `armor.json`, 나머지 `items.json`.
2. SRD 아이템이면 원문 수치 그대로, `"source": "SRD 5.2.1"`. 자체 아이템이면 비슷한 SRD 아이템을 기준으로 수치를 제안하고 근거를 한 줄로 쓴 뒤 사용자 확인을 받는다. `"source": "original"`.
3. 공통 필드: `id`(영어 snake_case), `name{ko, en}`(둘 다 — 검증기가 빈 이름을 오류로 본다), `weight_kg`(파운드 × 0.45), `price_gp`, `material`(4단계 재질 태그), `source`.
4. 종류별 필드:
   - **무기**: `category`(simple_melee·simple_ranged·martial_melee·martial_ranged), `damage`, `damage_type`, `properties`(finesse·light·heavy·thrown·two_handed·versatile·reach·loading·ammunition), `versatile_damage`, `range_tiles`([보통, 최대] 칸), `ammunition`, `mastery`(cleave·graze·nick·push·sap·slow·topple·vex).
   - **갑옷**: `category`(light·medium·heavy·shield), `ac_base`, `dex_cap`(없으면 null, 중갑 0), `str_required`, `stealth_disadvantage`.
   - **물약**(`category: potion`): `effects`(효과 모델), `drink_cost`, `feed_cost`, `throwable`, `throw{area, removes}` — 행동 목록에 마시기·먹이기·던지기가 자동으로 뜬다.
   - **두루마리**(`category: scroll`): `spell`(주문 id), `save_dc`, `attack_bonus`(SRD: 소마법·1레벨 13 / +5). 내 클래스 주문 목록에 있으면 '두루마리 읽기'가 뜨고 슬롯 없이 시전, 쓰면 사라진다.
   - **음식**(`category: food`): `camp_supplies`(긴 휴식 1회 = 40).
   - **도구**(`category: tool`): 도둑 도구·함정 해체 도구(지금은 이 둘만 엔진이 쓴다).
   - **마법 물품**(`category: magic`): **아직 동작 없음** — 장비 칸(장착 효과) 설계가 먼저다. 넣기 전에 사용자에게 묻는다.
5. 효과는 8단계 효과 모델로 쓴다. 표현이 안 되면 `script` + 효과 스크립트 + 테스트를 만든다.
6. `/verify` — `tests/test_content_smoke.gd`가 쓰는 아이템(물약·두루마리)을 모두 행동 목록에서 써 본다.

## 보고

추가한 아이템 표(이름, 핵심 수치, 출처), 새로 만든 스크립트, 동작하지 않는 분류(마법 물품)를 넣었다면 그 사실.
