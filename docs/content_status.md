# 콘텐츠 현황

> `tools/content_report.gd`가 데이터에서 만든다(손으로 고치지 않는다). 레벨 상한 20(data/rules/progression.json).

## 요약

| 종류 | 수 |
| --- | --- |
| class | 12 |
| spell | 240 |
| weapon | 38 |
| armor | 13 |
| item | 36 |
| feat | 10 |
| species | 15 |
| background | 4 |
| monster | 31 |
| capability | 76 |
| terrain_preset | 11 |
| map | 5 |

## 클래스 기능

동작 장치: `스크립트`(effects/<id>.gd), `태그`(caps → 엔진 메커니즘), `부여`(grants), `고르기`(choice_kind), `설정`(toggle), `반응`(kind reaction).
**설명만** = 데이터에 설명은 있으나 엔진이 이 기능으로 하는 일이 없다(생성기가 명세로 처리하는 무기 마스터리·전문화 등 포함) — 새 기능이면 장치를 달아야 한다.

### 바바리안 (barbarian) — 생명 주사위 d12, 역할 melee

| 레벨 | 기능 | 하위 | 장치 | 상태 |
| --- | --- | --- | --- | --- |
| 1 | 분노 (rage) |  | 스크립트 rage |  |
| 1 | 분노 연장 (extend_rage) |  | 스크립트 extend_rage |  |
| 1 | 맨몸 방어 (unarmored_defense) |  | 태그 unarmored_defense_con |  |
| 1 | 무기 마스터리 (weapon_mastery) |  | 처리: 생성기 — 클래스 weapon_mastery 표(2종, 4레벨 3종)와 명세 masteries |  |
| 2 | 위험 감지 (danger_sense) |  | 부여 advantage |  |
| 2 | 무모한 공격 (reckless_attack) |  | 스크립트 reckless_attack; 태그 reckless |  |
| 3 | 원시 지식 (primal_knowledge) |  | 고르기(skill) |  |
| 3 | 광란 (frenzy) | berserker | 태그 frenzy |  |
| 5 | 추가 공격 (extra_attack) |  | 태그 extra_attack; 부여 attacks_per_action |  |
| 5 | 빠른 이동 (fast_movement) |  | 태그 fast_movement |  |
| 6 | 광기 없는 분노 (mindless_rage) | berserker | 태그 mindless_rage |  |
| 7 | 야생의 본능 (feral_instinct) |  | 부여 advantage |  |
| 7 | 본능적 도약 (instinctive_pounce) |  | 태그 instinctive_pounce |  |
| 9 | 잔혹한 일격 (brutal_strike) |  | 태그 brutal_strike; 설정 |  |
| 10 | 보복 (retaliation) | berserker | 태그 retaliation; 반응 |  |

### 바드 (bard) — 생명 주사위 d8, 역할 caster

| 레벨 | 기능 | 하위 | 장치 | 상태 |
| --- | --- | --- | --- | --- |
| 1 | 바드의 영감 (bardic_inspiration) |  | 스크립트 bardic_inspiration |  |
| 2 | 전문화 (expertise) |  | 처리: 생성기 — 명세 expertise(숙련 기능 2개, 숙련 보너스 2배) |  |
| 2 | 만물박사 (jack_of_all_trades) |  | 태그 jack_of_all_trades |  |
| 3 | 추가 숙련 (bonus_proficiencies_lore) | lore | 고르기(skill) |  |
| 3 | 비꼬는 말 (cutting_words) | lore | 반응 |  |
| 5 | 영감의 샘 (font_of_inspiration) |  | 스크립트 font_of_inspiration |  |
| 6 | 마법의 발견 (magical_discoveries) | lore | 고르기(spell) |  |
| 7 | 대항 매혹 (countercharm) |  | 태그 countercharm; 반응 |  |
| 9 | 전문화(9레벨) (expertise_9) |  | 고르기(expertise) |  |
| 10 | 마법의 비밀 (magical_secrets) |  | 처리: 클래스 spellcasting.extra_lists — 10레벨부터 준비 주문을 클레릭·드루이드·위저드 목록에서도 고른다(주문 창·생성기 검사) |  |

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
| 6 | 축복받은 치유자 (blessed_healer) | life | 태그 blessed_healer |  |
| 7 | 축복받은 일격 (blessed_strikes) |  | 고르기(option) |  |
| 10 | 신성 개입 (divine_intervention) |  | 태그 free_cast_class_spell; 설정 |  |

### 드루이드 (druid) — 생명 주사위 d8, 역할 caster

| 레벨 | 기능 | 하위 | 장치 | 상태 |
| --- | --- | --- | --- | --- |
| 1 | 드루이드어 (druidic) |  | 처리: 클래스 always_prepared(동물과 대화). 숨은 글 남기기는 삭제(언어) |  |
| 1 | 원초의 질서 (primal_order) |  | 고르기(option) |  |
| 2 | 야생 변신 (wild_shape) |  | 스크립트 wild_shape |  |
| 2 | 변신 풀기 (revert_wild_shape) |  | 스크립트 revert_wild_shape |  |
| 2 | 야생 동료 (wild_companion) |  | 스크립트 wild_companion |  |
| 3 | 대지 회합 주문 (circle_land_spells) | land | 고르기(option) |  |
| 3 | 땅의 도움 (lands_aid) | land | 스크립트 lands_aid |  |
| 5 | 야생의 부활 (wild_resurgence) |  | 스크립트 wild_resurgence |  |
| 6 | 자연 회복 (natural_recovery) | land | 스크립트 arcane_recovery |  |
| 6 | 자연 회복: 무료 시전 (natural_recovery_cast) | land | 태그 free_cast_class_spell; 설정 |  |
| 7 | 원소의 격노 (elemental_fury) |  | 고르기(option) |  |
| 10 | 자연의 수호 (natures_ward) | land | 고르기(option) |  |

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
| 7 | 추가 전투 방식 (additional_fighting_style) | champion | 고르기(feat) |  |
| 9 | 불굴 (indomitable) |  | 스크립트 indomitable |  |
| 9 | 전술 대가 (tactical_master) |  | 태그 tactical_master; 설정 |  |
| 10 | 영웅 전사 (heroic_warrior) | champion | 태그 heroic_warrior |  |

### 몽크 (monk) — 생명 주사위 d8, 역할 melee

| 레벨 | 기능 | 하위 | 장치 | 상태 |
| --- | --- | --- | --- | --- |
| 1 | 무술 (martial_arts) |  | 태그 martial_arts |  |
| 1 | 보너스 비무장 공격 (martial_arts_strike) |  | 스크립트 martial_arts_strike |  |
| 1 | 맨몸 방어 (unarmored_defense) |  | 태그 unarmored_defense_wis |  |
| 2 | 몽크의 기 (monks_focus) |  | 처리: 자원 focus(레벨만큼, 짧은 휴식) — 연타·인내의 방어·바람의 걸음·충격의 일격이 쓴다 |  |
| 2 | 연타 (flurry_of_blows) |  | 스크립트 flurry_of_blows |  |
| 2 | 인내의 방어 (patient_defense) |  | 스크립트 patient_defense |  |
| 2 | 바람의 걸음 (step_of_the_wind) |  | 스크립트 step_of_the_wind |  |
| 2 | 맨몸 이동 (unarmored_movement) |  | 태그 unarmored_movement |  |
| 2 | 신비한 대사 (uncanny_metabolism) |  | 태그 uncanny_metabolism |  |
| 3 | 공격 쳐내기 (deflect_attacks) |  | 스크립트 deflect_attacks; 반응 |  |
| 3 | 열린 손 기법 (open_hand_technique) | open_hand | 태그 open_hand_technique; 설정 |  |
| 4 | 느린 낙하 (slow_fall) |  | 태그 slow_fall; 반응 |  |
| 5 | 추가 공격 (extra_attack) |  | 태그 extra_attack; 부여 attacks_per_action |  |
| 5 | 충격의 일격 (stunning_strike) |  | 태그 stunning_strike; 설정 |  |
| 6 | 강화된 타격 (empowered_strikes) |  | 태그 empowered_strikes |  |
| 6 | 몸의 완전함 (wholeness_of_body) | open_hand | 스크립트 wholeness_of_body |  |
| 7 | 회피 (evasion) |  | 태그 evasion |  |
| 9 | 곡예 이동 (acrobatic_movement) |  | 태그 climber |  |
| 10 | 고양된 집중 (heightened_focus) |  | 태그 heightened_focus |  |
| 10 | 자기 회복 (self_restoration) |  | 태그 self_restoration |  |

### 팔라딘 (paladin) — 생명 주사위 d10, 역할 melee

| 레벨 | 기능 | 하위 | 장치 | 상태 |
| --- | --- | --- | --- | --- |
| 1 | 신성한 손길 (lay_on_hands) |  | 스크립트 lay_on_hands |  |
| 1 | 무기 마스터리 (weapon_mastery) |  | 처리: 생성기 — 클래스 weapon_mastery 표(2종)와 명세 masteries |  |
| 2 | 전투 방식 (fighting_style) |  | 고르기(feat) |  |
| 2 | 팔라딘의 강타 (paladins_smite) |  | 처리: 클래스 always_prepared(신성한 강타) + 자원 innate_divine_smite(슬롯 없이 긴 휴식마다 1회 — 무료 횟수 먼저) |  |
| 3 | 신성 변환 (channel_divinity) |  | 처리: 자원 channel_divinity(2회, 짧은 휴식에 1회 회복) — 하위 클래스 기능이 쓴다 |  |
| 3 | 신성 감지 (divine_sense) |  | 스크립트 divine_sense |  |
| 3 | 헌신의 맹세 주문 (oath_spells_devotion) | devotion | 처리: 하위 클래스 always_prepared(3레벨 악과 선 보호·신앙의 방패, 5레벨 원조·진실의 구역) |  |
| 3 | 신성한 무기 (sacred_weapon) | devotion | 스크립트 sacred_weapon |  |
| 5 | 추가 공격 (extra_attack) |  | 태그 extra_attack; 부여 attacks_per_action |  |
| 5 | 충직한 탈것 (faithful_steed) |  | 처리: 클래스 always_prepared(탈것 찾기) + 자원 innate_find_steed(슬롯 없이 긴 휴식마다 1회). 올라타기 없음(BG3식 동료) |  |
| 6 | 보호의 오라 (aura_of_protection) |  | 오라(auras.gd) |  |
| 7 | 헌신의 오라 (aura_of_devotion) | devotion | 오라(auras.gd) |  |
| 9 | 적 퇴치 (abjure_foes) |  | 스크립트 abjure_foes |  |
| 10 | 용기의 오라 (aura_of_courage) |  | 오라(auras.gd) |  |

### 레인저 (ranger) — 생명 주사위 d10, 역할 ranged

| 레벨 | 기능 | 하위 | 장치 | 상태 |
| --- | --- | --- | --- | --- |
| 1 | 선호하는 적 (favored_enemy) |  | 처리: 클래스 always_prepared(사냥꾼의 표식) + 자원 innate_hunters_mark(슬롯 없이 긴 휴식마다 2회, 5레벨 3회 — 무료 횟수 먼저) |  |
| 1 | 무기 마스터리 (weapon_mastery) |  | 처리: 생성기 — 클래스 weapon_mastery 표(2종)와 명세 masteries |  |
| 2 | 노련한 탐험가 (deft_explorer) |  | 고르기(expertise) |  |
| 2 | 전투 방식 (fighting_style) |  | 고르기(feat) |  |
| 3 | 사냥꾼의 지식 (hunters_lore) | hunter | 태그 hunters_lore |  |
| 3 | 사냥꾼의 먹잇감 (hunters_prey) | hunter | 고르기(option) |  |
| 5 | 추가 공격 (extra_attack) |  | 태그 extra_attack; 부여 attacks_per_action |  |
| 6 | 방랑 (roving) |  | 태그 fast_movement, climber |  |
| 7 | 방어 전술 (defensive_tactics) | hunter | 고르기(option) |  |
| 9 | 전문화(9레벨) (expertise_9) |  | 고르기(expertise) |  |
| 10 | 지치지 않음 (tireless) |  | 스크립트 tireless |  |

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
| 6 | 전문화(6레벨) (expertise_6) |  | 고르기(expertise) |  |
| 7 | 회피 (evasion) |  | 태그 evasion |  |
| 7 | 믿음직한 재능 (reliable_talent) |  | 태그 reliable_talent |  |
| 9 | 최상급 은신 (supreme_sneak) | thief | 태그 stealth_attack; 설정 |  |

### 소서러 (sorcerer) — 생명 주사위 d6, 역할 caster

| 레벨 | 기능 | 하위 | 장치 | 상태 |
| --- | --- | --- | --- | --- |
| 1 | 타고난 마법 (innate_sorcery) |  | 스크립트 innate_sorcery |  |
| 2 | 마법의 샘 (font_of_magic) |  | 처리: 자원 sorcery_points(레벨만큼, 긴 휴식) + 기능 슬롯→점수·점수→슬롯 |  |
| 2 | 슬롯을 마법 점수로 (convert_slot) |  | 스크립트 convert_slot |  |
| 2 | 마법 점수로 슬롯 (create_slot) |  | 스크립트 create_slot |  |
| 2 | 주문 변형 (metamagic) |  | 고르기(option); 설정 |  |
| 3 | 용의 회복력 (draconic_resilience) | draconic | 태그 unarmored_defense_cha; 부여 hp_per_level |  |
| 3 | 용의 주문 (draconic_spells) | draconic | 처리: 하위 클래스 always_prepared(3레벨 변신·색채의 구슬·명령·용의 숨결, 5레벨 공포·비행) |  |
| 5 | 마법 회복 (sorcerous_restoration) |  | 태그 sorcerous_restoration |  |
| 6 | 원소 친화 (elemental_affinity) | draconic | 고르기(option) |  |
| 7 | 마법의 화신 (sorcery_incarnate) |  | 태그 sorcery_incarnate |  |
| 10 | 주문 변형(10레벨) (metamagic_10) |  | 고르기(option) |  |

### 워락 (warlock) — 생명 주사위 d8, 역할 caster

| 레벨 | 기능 | 하위 | 장치 | 상태 |
| --- | --- | --- | --- | --- |
| 1 | 계약 마법 (pact_magic) |  | 처리: 클래스 spellcasting — 슬롯이 모두 같은 레벨(1·2·3), 짧은 휴식에 회복(slot_recharge short), 낮은 주문은 그 레벨로 올려 시전 |  |
| 1 | 섬뜩한 영창 (eldritch_invocations) |  | 고르기(option) |  |
| 2 | 섬뜩한 영창(2레벨) (eldritch_invocations_2) |  | 고르기(option) |  |
| 2 | 마법적 기지 (magical_cunning) |  | 스크립트 magical_cunning |  |
| 3 | 어둠의 축복 (dark_ones_blessing) | fiend | 태그 dark_ones_blessing |  |
| 3 | 악마의 주문 (fiend_spells) | fiend | 처리: 하위 클래스 always_prepared(3레벨 불타는 손·명령·작열 광선·암시, 5레벨 화염구·악취 구름) |  |
| 5 | 섬뜩한 영창(5레벨) (eldritch_invocations_5) |  | 고르기(option) |  |
| 6 | 어둠의 자의 행운 (dark_ones_own_luck) | fiend | 스크립트 dark_ones_own_luck |  |
| 7 | 섬뜩한 영창(7레벨) (eldritch_invocations_7) |  | 고르기(option) |  |
| 9 | 섬뜩한 영창(9레벨) (eldritch_invocations_9) |  | 고르기(option) |  |
| 9 | 후원자와 접촉 (contact_patron) |  |  | 보류(deferred) |
| 10 | 악마의 회복력 (fiendish_resilience) | fiend | 고르기(option) |  |
| 12 | 섬뜩한 영창(12레벨) (eldritch_invocations_12) |  | 고르기(option) |  |
| 15 | 섬뜩한 영창(15레벨) (eldritch_invocations_15) |  | 고르기(option) |  |
| 18 | 섬뜩한 영창(18레벨) (eldritch_invocations_18) |  | 고르기(option) |  |

### 위저드 (wizard) — 생명 주사위 d6, 역할 caster

| 레벨 | 기능 | 하위 | 장치 | 상태 |
| --- | --- | --- | --- | --- |
| 1 | 의식 숙련 (ritual_adept) |  | 태그 ritual_from_spellbook |  |
| 1 | 비전 회복 (arcane_recovery) |  | 스크립트 arcane_recovery |  |
| 2 | 학자 (scholar) |  | 고르기(expertise) |  |
| 3 | 방출 학자 (evocation_savant) | evoker | 부여 spellbook_school |  |
| 3 | 강력한 소마법 (potent_cantrip) | evoker | 태그 cantrip_half_on_miss |  |
| 5 | 주문 암기 (memorize_spell) |  | 태그 prepare_swap_short_rest |  |
| 6 | 주문 조각 (sculpt_spells) | evoker | 태그 sculpt_spells |  |
| 10 | 강화된 방출 (empowered_evocation) | evoker | 태그 evocation_add_mod |  |

## 주문

- 상태: included 175, excluded_v1 59, candidate_exclusion 6
- 포함 주문 레벨별: 2레벨 45, 0레벨 24, 3레벨 30, 4레벨 16, 1레벨 50, 5레벨 10
- 스크립트 주문 76개, 그중 포함인데 미구현: 없음
- 아이콘(icon) 없는 포함 주문(학파 색 별로 표시): 없음
- 클래스 주문 목록: wizard 159, sorcerer 106, cleric 80, ranger 40, paladin 32, bard 92, druid 83, warlock 51

## 아이템

- 분류: gear 6, magic 19, currency 1, potion 5, food 1, scroll 2, tool 2
- 동작하는 분류: potion(마시기·먹이기·던지기), scroll(두루마리 읽기), food(캠프 보급품), tool(자물쇠·함정). **magic(장착 효과)은 아직 동작 없음** — 장비 칸 설계가 먼저 필요

## 능력 태그 사용

| 태그 | 이름 | 쓰는 곳 |
| --- | --- | --- |
| agonizing_blast | 고통의 화살 | (몬스터 특성 또는 아직 없음) |
| armor_ac_plus_1 | 방어 | 재주 defense |
| blessed_healer | 축복받은 치유자 | cleric |
| bonus_dash_disengage_hide | 교활한 행동 | rogue |
| brutal_strike | 잔혹한 일격 | barbarian |
| cantrip_add_mod | 강력한 주문 시전 | (몬스터 특성 또는 아직 없음) |
| cantrip_half_on_miss | 강력한 소마법 | wizard |
| check_boost_d10 | 전술적 판단 | fighter |
| climber | 등반 | monk, ranger, rogue |
| countercharm | 대항 매혹 | bard |
| crit_free_move | 치명타 뒤 이동 | fighter |
| cunning_strike | 교활한 일격 | rogue |
| dark_ones_blessing | 어둠의 축복 | warlock |
| eldritch_mind | 섬뜩한 정신 | (몬스터 특성 또는 아직 없음) |
| empowered_strikes | 강화된 타격 | monk |
| escape_the_horde | 무리 탈출 | (몬스터 특성 또는 아직 없음) |
| evasion | 회피 | monk, rogue |
| evocation_add_mod | 강화된 방출 | wizard |
| extra_attack | 추가 공격 | barbarian, fighter, monk, paladin, ranger |
| extra_bonus_action | 추가 보너스 행동 | rogue |
| extra_damage_wounded | 거상 학살자 | (몬스터 특성 또는 아직 없음) |
| fast_movement | 빠른 이동 | barbarian, ranger |
| free_cast_class_spell | 신성 개입 | cleric, druid |
| frenzy | 광란 | barbarian |
| heightened_focus | 고양된 집중 | monk |
| heroic_warrior | 영웅 전사 | fighter |
| horde_breaker | 무리 파괴자 | (몬스터 특성 또는 아직 없음) |
| hunters_lore | 사냥꾼의 지식 | ranger |
| immune_magic_sleep | 마법 수면 면역 | 종족 elf |
| initiative_proficiency | 경계 | 재주 alert |
| instinctive_pounce | 본능적 도약 | barbarian |
| jack_of_all_trades | 만물박사 | bard |
| jump_dex | 민첩 도약 | rogue |
| jump_plus_1 | 도약 +1칸 | fighter, rogue |
| long_rest_inspiration | 기지 | 종족 human |
| martial_arts | 무술 | monk |
| metamagic_careful | 신중한 주문 | (몬스터 특성 또는 아직 없음) |
| metamagic_distant | 원거리 주문 | (몬스터 특성 또는 아직 없음) |
| metamagic_extended | 연장된 주문 | (몬스터 특성 또는 아직 없음) |
| metamagic_heightened | 고양된 주문 | (몬스터 특성 또는 아직 없음) |
| metamagic_quickened | 빠른 주문 | (몬스터 특성 또는 아직 없음) |
| metamagic_seeking | 추적 주문 | (몬스터 특성 또는 아직 없음) |
| metamagic_subtle | 은밀한 주문 | (몬스터 특성 또는 아직 없음) |
| mindless_rage | 광기 없는 분노 | barbarian |
| multiattack_defense | 다중 공격 방어 | (몬스터 특성 또는 아직 없음) |
| nimble_escape | 날렵한 탈출 | (몬스터 특성 또는 아직 없음) |
| open_hand_technique | 열린 손 기법 | monk |
| pack_tactics | 무리 전술 | (몬스터 특성 또는 아직 없음) |
| pact_blade | 계약의 칼날 | (몬스터 특성 또는 아직 없음) |
| prepare_swap_short_rest | 주문 암기 | wizard |
| ranged_weapon_attack_bonus | 궁술 | 재주 archery |
| reckless | 무모한 공격 | barbarian |
| reliable_talent | 믿음직한 재능 | rogue |
| repelling_blast | 밀어내는 화살 | (몬스터 특성 또는 아직 없음) |
| reroll_low_damage_two_handed | 대형 무기 전투 | 재주 great_weapon_fighting |
| reroll_natural_1 | 행운 | 종족 halfling |
| retaliation | 보복 | barbarian |
| ritual_from_spellbook | 의식 숙련 | wizard |
| sculpt_spells | 주문 조각 | wizard |
| self_restoration | 자기 회복 | monk |
| slow_fall | 느린 낙하 | monk |
| sneak_attack | 급소 공격 | rogue |
| sorcerous_restoration | 마법 회복 | sorcerer |
| sorcery_incarnate | 마법의 화신 | sorcerer |
| spell_heal_bonus | 생명의 제자 | cleric |
| stealth_attack | 은신 공격 | rogue |
| stunning_strike | 충격의 일격 | monk |
| sunlight_sensitivity | 햇빛 민감 | (몬스터 특성 또는 아직 없음) |
| tactical_master | 전술 대가 | fighter |
| two_weapon_fighting | 쌍수 전투 | 재주 two_weapon_fighting |
| unarmored_defense_cha | 용의 비늘 | sorcerer |
| unarmored_defense_con | 맨몸 방어(건강) | barbarian |
| unarmored_defense_wis | 맨몸 방어(지혜) | monk |
| unarmored_movement | 맨몸 이동 | monk |
| uncanny_metabolism | 신비한 대사 | monk |
| weapon_damage_twice | 야만적 공격 | 재주 savage_attacker |
