# 콘텐츠 현황

> `tools/content_report.gd`가 데이터에서 만든다(손으로 고치지 않는다). 레벨 상한 5(data/rules/progression.json).

## 요약

| 종류 | 수 |
| --- | --- |
| class | 5 |
| spell | 156 |
| weapon | 38 |
| armor | 13 |
| item | 11 |
| feat | 10 |
| species | 15 |
| background | 4 |
| monster | 21 |
| capability | 26 |
| terrain_preset | 11 |
| map | 5 |

## 클래스 기능

동작 장치: `스크립트`(effects/<id>.gd), `태그`(caps → 엔진 메커니즘), `부여`(grants), `고르기`(choice_kind), `설정`(toggle), `반응`(kind reaction).
**설명만** = 데이터에 설명은 있으나 엔진이 이 기능으로 하는 일이 없다(생성기가 명세로 처리하는 무기 마스터리·전문화 등 포함) — 새 기능이면 장치를 달아야 한다.

### 클레릭 (cleric) — 생명 주사위 d8, 역할 healer

| 레벨 | 기능 | 하위 | 장치 | 상태 |
| --- | --- | --- | --- | --- |
| 1 | 신성한 서열 (divine_order) |  | 고르기(option) |  |
| 1 | 생명의 제자 (disciple_of_life) | life | 태그 spell_heal_bonus |  |
| 2 | 신성 변환 (channel_divinity) |  | 처리: 자원 channel_divinity — 신성한 불꽃·언데드 퇴치·생명 보존이 쓴다(choices는 안내용) |  |
| 2 | 신성한 불꽃 (divine_spark) |  | 스크립트 divine_spark |  |
| 2 | 언데드 퇴치 (turn_undead) |  | 스크립트 turn_undead |  |
| 2 | 생명 보존 (preserve_life) | life | 스크립트 preserve_life |  |
| 5 | 언데드 소각 (sear_undead) |  | 처리: turn_undead 스크립트 안 |  |

### 전사 (fighter) — 생명 주사위 d10, 역할 melee

| 레벨 | 기능 | 하위 | 장치 | 상태 |
| --- | --- | --- | --- | --- |
| 1 | 전투 방식 (fighting_style) |  | 고르기(feat) |  |
| 1 | 재기의 숨결 (second_wind) |  | 스크립트 second_wind |  |
| 1 | 무기 마스터리 (weapon_mastery) |  | 처리: 생성기 — 클래스 weapon_mastery 표(레벨별 개수)와 명세 masteries |  |
| 2 | 행동 연쇄 (action_surge) |  | 스크립트 action_surge |  |
| 2 | 전술적 판단 (tactical_mind) |  | 스크립트 tactical_mind; 태그 check_boost_d10 |  |
| 3 | 향상된 치명타 (improved_critical) | champion | 부여 crit_threshold |  |
| 3 | 뛰어난 운동선수 (remarkable_athlete) | champion | 태그 crit_free_move, jump_plus_1; 부여 advantage |  |
| 5 | 추가 공격 (extra_attack) |  | 태그 extra_attack; 부여 attacks_per_action |  |
| 5 | 전술적 이동 (tactical_shift) |  | 처리: second_wind 스크립트 안 |  |

### 레인저 (ranger) — 생명 주사위 d10, 역할 ranged

| 레벨 | 기능 | 하위 | 장치 | 상태 |
| --- | --- | --- | --- | --- |
| 1 | 선호하는 적 (favored_enemy) |  | 처리: 클래스 always_prepared(사냥꾼의 표식) + 자원 innate_hunters_mark(슬롯 없이 긴 휴식마다 2회, 5레벨 3회 — 무료 횟수 먼저) |  |
| 1 | 무기 마스터리 (weapon_mastery) |  | 처리: 생성기 — 클래스 weapon_mastery 표(2종)와 명세 masteries |  |
| 2 | 노련한 탐험가 (deft_explorer) |  | 고르기(expertise) |  |
| 2 | 전투 방식 (fighting_style) |  | 고르기(feat) |  |
| 3 | 사냥꾼의 지식 (hunters_lore) | hunter |  | 보류(deferred) |
| 3 | 사냥꾼의 먹잇감 (hunters_prey) | hunter | 고르기(option) |  |
| 5 | 추가 공격 (extra_attack) |  | 태그 extra_attack; 부여 attacks_per_action |  |

### 로그 (rogue) — 생명 주사위 d8, 역할 ranged

| 레벨 | 기능 | 하위 | 장치 | 상태 |
| --- | --- | --- | --- | --- |
| 1 | 전문화 (expertise) |  | 처리: 생성기 — 명세 expertise(숙련 기능의 숙련 보너스 2배) |  |
| 1 | 급소 공격 (sneak_attack) |  | 스크립트 sneak_attack; 태그 sneak_attack; 설정 |  |
| 1 | 무기 마스터리 (weapon_mastery) |  | 처리: 생성기 — 클래스 weapon_mastery 표(레벨별 개수)와 명세 masteries |  |
| 2 | 교활한 행동 (cunning_action) |  | 태그 bonus_dash_disengage_hide |  |
| 3 | 안정된 조준 (steady_aim) |  | 스크립트 steady_aim |  |
| 3 | 빠른 손 (fast_hands) | thief | 태그 extra_bonus_action |  |
| 3 | 2층 작업 (second_story_work) | thief | 태그 climber, jump_dex, jump_plus_1 |  |
| 5 | 교활한 일격 (cunning_strike) |  | 스크립트 cunning_strike; 태그 cunning_strike; 설정 |  |
| 5 | 교묘한 회피 (uncanny_dodge) |  | 스크립트 uncanny_dodge; 반응 |  |

### 위저드 (wizard) — 생명 주사위 d6, 역할 caster

| 레벨 | 기능 | 하위 | 장치 | 상태 |
| --- | --- | --- | --- | --- |
| 1 | 의식 숙련 (ritual_adept) |  |  | 보류(deferred) |
| 1 | 비전 회복 (arcane_recovery) |  | 스크립트 arcane_recovery |  |
| 2 | 학자 (scholar) |  | 고르기(expertise) |  |
| 3 | 방출 학자 (evocation_savant) | evoker |  | 보류(deferred) |
| 3 | 강력한 소마법 (potent_cantrip) | evoker | 태그 cantrip_half_on_miss |  |
| 5 | 주문 암기 (memorize_spell) |  |  | 보류(deferred) |

## 주문

- 상태: included 137, excluded_v1 13, candidate_exclusion 6
- 포함 주문 레벨별: 2레벨 43, 0레벨 20, 3레벨 30, 1레벨 44
- 스크립트 주문 67개, 그중 포함인데 미구현: 없음
- 아이콘(icon) 없는 포함 주문(학파 색 별로 표시): 없음
- 클래스 주문 목록: wizard 109, cleric 58, ranger 32

## 아이템

- 분류: currency 1, potion 5, food 1, scroll 2, tool 2
- 동작하는 분류: potion(마시기·먹이기·던지기), scroll(두루마리 읽기), food(캠프 보급품), tool(자물쇠·함정). **magic(장착 효과)은 아직 동작 없음** — 장비 칸 설계가 먼저 필요

## 능력 태그 사용

| 태그 | 이름 | 쓰는 곳 |
| --- | --- | --- |
| armor_ac_plus_1 | 방어 | 재주 defense |
| bonus_dash_disengage_hide | 교활한 행동 | rogue |
| cantrip_half_on_miss | 강력한 소마법 | wizard |
| check_boost_d10 | 전술적 판단 | fighter |
| climber | 등반 | rogue |
| crit_free_move | 치명타 뒤 이동 | fighter |
| cunning_strike | 교활한 일격 | rogue |
| extra_attack | 추가 공격 | fighter, ranger |
| extra_bonus_action | 추가 보너스 행동 | rogue |
| extra_damage_wounded | 거상 학살자 | (몬스터 특성 또는 아직 없음) |
| horde_breaker | 무리 파괴자 | (몬스터 특성 또는 아직 없음) |
| immune_magic_sleep | 마법 수면 면역 | 종족 elf |
| initiative_proficiency | 경계 | 재주 alert |
| jump_dex | 민첩 도약 | rogue |
| jump_plus_1 | 도약 +1칸 | fighter, rogue |
| long_rest_inspiration | 기지 | 종족 human |
| nimble_escape | 날렵한 탈출 | (몬스터 특성 또는 아직 없음) |
| pack_tactics | 무리 전술 | (몬스터 특성 또는 아직 없음) |
| ranged_weapon_attack_bonus | 궁술 | 재주 archery |
| reroll_low_damage_two_handed | 대형 무기 전투 | 재주 great_weapon_fighting |
| reroll_natural_1 | 행운 | 종족 halfling |
| sneak_attack | 급소 공격 | rogue |
| spell_heal_bonus | 생명의 제자 | cleric |
| sunlight_sensitivity | 햇빛 민감 | (몬스터 특성 또는 아직 없음) |
| two_weapon_fighting | 쌍수 전투 | 재주 two_weapon_fighting |
| weapon_damage_twice | 야만적 공격 | 재주 savage_attacker |
