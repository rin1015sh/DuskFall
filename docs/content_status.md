# 콘텐츠 현황

> `tools/content_report.gd`가 데이터에서 만든다(손으로 고치지 않는다). 레벨 상한 12(data/rules/progression.json).

## 요약

| 종류 | 수 |
| --- | --- |
| class | 12 |
| spell | 271 |
| weapon | 38 |
| armor | 13 |
| item | 59 |
| feat | 56 |
| species | 39 |
| background | 4 |
| monster | 60 |
| capability | 203 |
| terrain_preset | 11 |
| map | 5 |

## 클래스 기능

동작 장치: `스크립트`(effects/<id>.gd), `태그`(caps → 엔진 메커니즘), `부여`(grants), `고르기`(choice_kind), `설정`(toggle), `반응`(kind reaction).
**설명만** = 데이터에 설명은 있으나 엔진이 이 기능으로 하는 일이 없다(생성기가 명세로 처리하는 무기 마스터리·전문화 등 포함) — 새 기능이면 장치를 달아야 한다.

### 바바리안 (barbarian) — 생명 주사위 d12, 역할 melee

| 레벨 | 기능 | 하위 | 장치 | 상태 |
| --- | --- | --- | --- | --- |
| 1 | 분노 (rage) |  | 스크립트 rage |  |
| 1 | 맨몸 방어 (unarmored_defense) |  | 태그 unarmored_defense_con |  |
| 2 | 위험 감지 (danger_sense) |  | 부여 advantage |  |
| 2 | 무모한 공격 (reckless_attack) |  | 스크립트 reckless_attack; 태그 reckless |  |
| 3 | 독수리의 질주 (primal_dash) | wildheart | 스크립트 primal_dash |  |
| 3 | 급강하 일격 (diving_strike) | wildheart | 스크립트 diving_strike |  |
| 3 | 원초의 쇄도 (primal_stampede) | wildheart | 스크립트 primal_stampede |  |
| 3 | 피의 갈망 (tigers_bloodlust) | wildheart | 스크립트 tigers_bloodlust |  |
| 3 | 선동의 울부짖음 (inciting_howl) | wildheart | 스크립트 inciting_howl |  |
| 3 | 야생 마법 분노 (wild_magic_rage) | wild_magic | 태그 wild_magic_rage |  |
| 3 | 빛의 화살 (wild_bolt_of_light) | wild_magic | 스크립트 wild_bolt_of_light |  |
| 3 | 무형의 정령 (wild_intangible_spirit) | wild_magic | 스크립트 wild_intangible_spirit |  |
| 3 | 야생 순간 이동 (wild_teleport) | wild_magic | 스크립트 wild_teleport |  |
| 3 | 마법 인지 (magic_awareness) | wild_magic | 스크립트 magic_awareness |  |
| 3 | 거인의 분노 (giants_rage) | giant | 태그 giants_rage |  |
| 3 | 탐욕의 품 (vapraks_greed) | giant | 태그 carry_quarter_more |  |
| 3 | 거인의 기적 (giant_thaumaturgy) | giant | 부여 at_will |  |
| 3 | 광란 (frenzy) | berserker | 태그 frenzy |  |
| 3 | 광란의 일격 (frenzied_strike) | berserker | 스크립트 frenzied_strike |  |
| 3 | 격노의 투척 (enraged_throw) | berserker | 스크립트 enraged_throw |  |
| 3 | 짐승의 말 (wildheart_speech) | wildheart | 부여 at_will |  |
| 3 | 짐승의 심장 (bestial_heart) | wildheart | 고르기(option) |  |
| 3 | 굽히지 않는 흉포함 (unrelenting_ferocity) | wildheart | 스크립트 unrelenting_ferocity |  |
| 5 | 빠른 이동 (fast_movement) |  | 태그 fast_movement |  |
| 5 | 거인의 발길질 (boot_of_the_giants) | giant | 스크립트 boot_of_the_giants |  |
| 5 | 추가 공격 (extra_attack) |  | 태그 extra_attack; 부여 attacks_per_action |  |
| 6 | 원소 쪼개기 (elemental_cleaver) | giant | 스크립트 elemental_cleaver; 설정 |  |
| 6 | 광기 없는 분노 (mindless_rage) | berserker | 태그 mindless_rage |  |
| 6 | 짐승의 면모 (animal_aspect) | wildheart | 고르기(option) |  |
| 6 | 강화 마법: 2레벨 슬롯 (bolstering_magic_slot2) | wild_magic | 스크립트 bolstering_magic |  |
| 6 | 강화 마법: 축복 (bolstering_magic_boon) | wild_magic | 스크립트 bolstering_magic |  |
| 6 | 강화 마법: 1레벨 슬롯 (bolstering_magic_slot1) | wild_magic | 스크립트 bolstering_magic |  |
| 7 | 야성의 본능 (feral_instinct) |  | 부여 initiative_bonus, condition_immunities |  |
| 8 | 대지 걸음 (lands_stride_wildheart) | wildheart | 태그 ignore_difficult_terrain |  |
| 9 | 잔혹한 치명타 (brutal_critical) |  | 태그 brutal_critical |  |
| 9 | 강화 마법: 3레벨 슬롯 (bolstering_magic_slot3) | wild_magic | 스크립트 bolstering_magic |  |
| 10 | 강력한 내던지기 (mighty_impel) | giant | 스크립트 mighty_impel |  |
| 10 | 불안정한 반발 (unstable_backlash) | wild_magic | 태그 unstable_backlash; 반응 |  |
| 10 | 짐승의 면모(둘째) (animal_aspect_10) | wildheart | 고르기(option) |  |
| 10 | 위협적인 존재감 (intimidating_presence) | berserker | 스크립트 intimidating_presence |  |
| 10 | 위협 유지 (maintain_intimidation) | berserker | 스크립트 intimidating_presence |  |
| 11 | 끈질긴 분노 (relentless_rage) |  | 스크립트 relentless_rage |  |

### 바드 (bard) — 생명 주사위 d8, 역할 caster

| 레벨 | 기능 | 하위 | 장치 | 상태 |
| --- | --- | --- | --- | --- |
| 1 | 바드의 영감 (bardic_inspiration) |  | 스크립트 bardic_inspiration |  |
| 2 | 만물박사 (jack_of_all_trades) |  | 태그 jack_of_all_trades |  |
| 2 | 휴식의 노래 (song_of_rest) |  | 스크립트 song_of_rest |  |
| 3 | 전문화 (bard_expertise) |  | 고르기(expertise) |  |
| 3 | 영감의 망토 (mantle_of_inspiration) | glamour | 스크립트 mantle_of_inspiration |  |
| 3 | 추가 숙련 (bonus_proficiencies_lore) | lore | 고르기(skill) |  |
| 3 | 비꼬는 말 (cutting_words) | lore | 반응 |  |
| 3 | 용맹의 훈련 (valour_training) | valour | 부여 armor_training, weapon_training |  |
| 3 | 전투 영감 (combat_inspiration) | valour | 태그 combat_inspiration |  |
| 3 | 칼날 묘기 (blade_flourish) | swords | 부여 special_attacks |  |
| 3 | 칼날의 훈련 (swords_training) | swords | 부여 armor_training, weapon_training |  |
| 3 | 칼날 전투 방식 (swords_fighting_style) | swords | 고르기(feat) |  |
| 5 | 영감의 샘 (font_of_inspiration) |  | 처리: 자원 recharge |  |
| 6 | 위엄의 명령 (majesty_command) | glamour | 스크립트 majesty_command |  |
| 6 | 위엄의 망토 (mantle_of_majesty) | glamour | 스크립트 mantle_of_majesty |  |
| 6 | 추가 공격(칼날) (swords_extra_attack) | swords | 태그 extra_attack; 부여 attacks_per_action |  |
| 6 | 추가 공격(용맹) (valour_extra_attack) | valour | 태그 extra_attack; 부여 attacks_per_action |  |
| 6 | 마법의 발견 (magical_discoveries) | lore | 고르기(spell) |  |
| 6 | 대항 매혹 (countercharm) |  | 태그 countercharm; 반응 |  |
| 10 | 마법의 비밀 (magical_secrets) |  | 고르기(spell) |  |
| 10 | 전문화(10레벨) (expertise_10) |  | 고르기(expertise) |  |

### 클레릭 (cleric) — 생명 주사위 d8, 역할 healer

| 레벨 | 기능 | 하위 | 장치 | 상태 |
| --- | --- | --- | --- | --- |
| 1 | 수확자 (reaper) | death | 태그 reaper; 부여 weapon_training |  |
| 1 | 전쟁 사제 (war_priest) | war | 태그 war_priest; 부여 armor_training, weapon_training |  |
| 1 | 생명의 제자 (disciple_of_life) | life | 태그 spell_heal_bonus; 부여 armor_training |  |
| 1 | 사기꾼의 축복 (blessing_of_the_trickster) | trickery | 스크립트 blessing_of_the_trickster |  |
| 1 | 경고의 섬광 (warding_flare) | light | 반응 |  |
| 1 | 폭풍의 분노 (wrath_of_the_storm) | tempest | 부여 armor_training, weapon_training; 설정; 반응 |  |
| 1 | 앎의 축복 (blessings_of_knowledge) | knowledge | 고르기(expertise) |  |
| 1 | 자연의 시종 (acolyte_of_nature) | nature | 부여 armor_training; 고르기(spell_pick) |  |
| 2 | 죽음의 손길 (touch_of_death) | death | 태그 touch_of_death; 설정 |  |
| 2 | 인도된 일격 (guided_strike) | war | 태그 guided_strike; 설정 |  |
| 2 | 이중 존재 (invoke_duplicity) | trickery | 스크립트 invoke_duplicity |  |
| 2 | 파괴의 분노 (destructive_wrath) | tempest | 태그 destructive_wrath; 설정 |  |
| 2 | 짐승·식물 매혹 (charm_animals_and_plants) | nature | 스크립트 charm_animals_and_plants |  |
| 2 | 시대의 지식 (knowledge_of_the_ages) | knowledge | 스크립트 knowledge_of_the_ages; 설정 |  |
| 2 | 새벽의 광휘 (radiance_of_the_dawn) | light | 스크립트 radiance_of_the_dawn |  |
| 2 | 생명 보존 (preserve_life) | life | 스크립트 preserve_life |  |
| 2 | 언데드 퇴치 (turn_undead) |  | 스크립트 turn_undead |  |
| 2 | 신성 변환 (channel_divinity) |  | 처리: 자원 channel_divinity(2레벨 1회, 6레벨 2회, 짧은 휴식 — BG3) — 언데드 퇴치·영역 기능이 쓴다 |  |
| 5 | 언데드 파괴 (destroy_undead) |  | 처리: turn_undead 스크립트 안 |  |
| 6 | 생각 읽기 (read_thoughts) | knowledge |  | 보류(deferred) |
| 6 | 원소 누그러뜨리기 (dampen_elements) | nature | 반응 |  |
| 6 | 넓어진 섬광 (improved_warding_flare) | light | 반응 |  |
| 6 | 벼락 일격 (thunderbolt_strike) | tempest | 태그 thunderbolt_strike |  |
| 6 | 축복받은 치유자 (blessed_healer) | life | 태그 blessed_healer |  |
| 6 | 그림자 망토 (cloak_of_shadows) | trickery | 스크립트 cloak_of_shadows |  |
| 6 | 전쟁 신의 축복 (war_gods_blessing) | war | 반응 |  |
| 6 | 피할 수 없는 파괴 (inescapable_destruction) | death | 부여 ignore_resistance |  |
| 10 | 신성 개입 (divine_intervention) |  | 태그 free_cast_class_spell; 설정 |  |

### 드루이드 (druid) — 생명 주사위 d8, 역할 caster

| 레벨 | 기능 | 하위 | 장치 | 상태 |
| --- | --- | --- | --- | --- |
| 2 | 야생 변신 (wild_shape) |  | 스크립트 wild_shape |  |
| 2 | 변신 풀기 (revert_wild_shape) |  | 스크립트 revert_wild_shape |  |
| 2 | 자연 회복 (natural_recovery) | land | 스크립트 arcane_recovery |  |
| 2 | 대지의 소마법 (land_cantrip) | land | 고르기(spell_pick) |  |
| 2 | 눈부신 숨결 (dazzling_breath) | stars | 스크립트 dazzling_breath |  |
| 2 | 전투 야생 변신 (combat_wild_shape) | moon | 처리: 야생 변신 형태 목록(wild_shape.forms_for) |  |
| 2 | 달빛 치유 (lunar_mend) | moon | 스크립트 lunar_mend |  |
| 2 | 빛의 화살 (luminous_arrow) | stars | 스크립트 luminous_arrow |  |
| 2 | 포자 후광 (halo_of_spores) | spores | 반응 |  |
| 2 | 공생체 (symbiotic_entity) | spores | 스크립트 symbiotic_entity |  |
| 2 | 별의 형상 (starry_form) | stars | 스크립트 starry_form; 설정 |  |
| 2 | 별자리 지도 (star_map) | stars | 처리: 자원 innate_guiding_bolt(타고난 시전 — 무료 횟수 먼저) |  |
| 3 | 대지 회합 주문 (circle_land_spells) | land | 고르기(option) |  |
| 5 | 야생의 일격 (wild_strike) |  | 태그 wild_strike |  |
| 6 | 우주의 징조: 불운 (cosmic_omen_woe) | stars | 반응 |  |
| 6 | 우주의 징조: 행운 (cosmic_omen_weal) | stars | 태그 cosmic_omen; 반응 |  |
| 6 | 곰팡이 감염 (fungal_infestation) | spores |  | 보류(deferred) |
| 6 | 원초의 일격 (primal_strike) | moon | 태그 primal_strike |  |
| 6 | 대지 걸음 (lands_stride) | land | 태그 ignore_difficult_terrain |  |
| 10 | 퍼지는 포자 (spreading_spores) | spores | 스크립트 spreading_spores |  |
| 10 | 자연의 수호 (natures_ward) | land | 부여 condition_immunities, damage_immunities, condition_immunity_from |  |
| 10 | 향상된 야생의 일격 (improved_wild_strike) |  | 태그 improved_wild_strike |  |
| 10 | 반짝이는 별자리 (twinkling_constellations) | stars | 태그 twinkling_constellations |  |

### 전사 (fighter) — 생명 주사위 d10, 역할 melee

| 레벨 | 기능 | 하위 | 장치 | 상태 |
| --- | --- | --- | --- | --- |
| 1 | 전투 방식 (fighting_style) |  | 고르기(feat) |  |
| 1 | 재기의 숨결 (second_wind) |  | 스크립트 second_wind |  |
| 2 | 행동 연쇄 (action_surge) |  | 스크립트 action_surge |  |
| 3 | 무기 결속 (weapon_bond) | eldritch_knight | 부여 condition_immunities |  |
| 3 | 주문 시전(비전 기사) (ek_spellcasting) | eldritch_knight | 처리: 생성기 — 하위 클래스 spellcasting(1/3 시전자, 위저드 목록, 지능, 명세 subclass_spells) |  |
| 3 | 비전 사격 (arcane_shot) | arcane_archer | 고르기(special_attack) |  |
| 3 | 비전 궁수의 지식 (arcane_archer_lore) | arcane_archer | 부여 skills; 고르기(spell_pick) |  |
| 3 | 기법 (manoeuvres) | battle_master | 고르기(special_attack) |  |
| 3 | 전투 우위 (combat_superiority) | battle_master | 처리: 무기 액션 group maneuver(actions._special_attack) |  |
| 3 | 향상된 치명타 (improved_critical) | champion | 부여 crit_threshold |  |
| 5 | 추가 공격 (extra_attack) |  | 태그 extra_attack; 부여 attacks_per_action |  |
| 7 | 뛰어난 운동선수 (remarkable_athlete) | champion | 태그 jump_plus_1, jump_plus_1, half_proficiency_physical |  |
| 7 | 휘는 화살 (curving_shot) | arcane_archer | 태그 curving_shot; 설정 |  |
| 7 | 마법 화살 (magic_arrow) | arcane_archer | 태그 magic_ranged |  |
| 7 | 전쟁 마법 (war_magic) | eldritch_knight | 태그 war_magic |  |
| 9 | 불굴 (indomitable) |  | 스크립트 indomitable |  |
| 10 | 추가 전투 방식 (additional_fighting_style) | champion | 고르기(feat) |  |
| 10 | 비전 일격 (eldritch_strike) | eldritch_knight | 태그 eldritch_strike |  |
| 11 | 추가 공격 2회 (two_extra_attacks) |  | 태그 extra_attack; 부여 attacks_per_action |  |

### 몽크 (monk) — 생명 주사위 d8, 역할 melee

| 레벨 | 기능 | 하위 | 장치 | 상태 |
| --- | --- | --- | --- | --- |
| 1 | 무술 (martial_arts) |  | 태그 martial_arts |  |
| 1 | 보너스 비무장 공격 (martial_arts_strike) |  | 스크립트 martial_arts_strike |  |
| 1 | 맨몸 방어 (unarmored_defense) |  | 태그 unarmored_defense_wis |  |
| 1 | 몽크의 기 (monks_focus) |  | 처리: 자원 focus = 몽크 레벨 + 1(짧은 휴식 — BG3 기) |  |
| 1 | 연타 (flurry_of_blows) |  | 스크립트 flurry_of_blows |  |
| 2 | 맨몸 이동 (unarmored_movement) |  | 태그 unarmored_movement |  |
| 2 | 바람의 걸음: 이탈 (step_of_the_wind_disengage) |  | 스크립트 step_of_the_wind |  |
| 2 | 바람의 걸음 (step_of_the_wind) |  | 스크립트 step_of_the_wind |  |
| 2 | 인내의 방어 (patient_defense) |  | 스크립트 patient_defense |  |
| 3 | 그림자 기술: 숨기 (shadow_arts_hide) | shadow | 스크립트 shadow_arts_hide |  |
| 3 | 그림자 기술: 어둠 (shadow_arts_darkness) | shadow | 스크립트 ki_spell |  |
| 3 | 그림자 기술: 암시야 (shadow_arts_darkvision) | shadow | 스크립트 ki_spell |  |
| 3 | 그림자 기술: 흔적 없는 이동 (shadow_arts_pass_without_trace) | shadow | 스크립트 ki_spell |  |
| 3 | 그림자 기술: 침묵 (shadow_arts_silence) | shadow | 스크립트 ki_spell |  |
| 3 | 폭풍의 손길 (touch_of_the_storm) | four_elements | 스크립트 ki_spell |  |
| 3 | 휩쓰는 불씨 일격 (sweeping_cinder_strike) | four_elements | 스크립트 ki_spell |  |
| 3 | 원소 균형의 구 (sphere_of_elemental_balance) | four_elements | 스크립트 ki_spell |  |
| 3 | 원소의 제자 (elemental_disciplines) | four_elements | 고르기(option) |  |
| 3 | 불과 물의 조화 (harmony_of_fire_and_water) | four_elements | 스크립트 harmony_of_fire_and_water |  |
| 3 | 돌풍 정령의 쇄도 (rush_of_the_gale_spirits) | four_elements | 스크립트 ki_spell |  |
| 3 | 서리 칼날 (blade_of_rime) | four_elements | 스크립트 ki_spell |  |
| 3 | 산의 냉기 (chill_of_the_mountain) | four_elements | 스크립트 ki_spell |  |
| 3 | 불뱀의 송곳니 (fangs_of_the_fire_snake) | four_elements | 스크립트 fangs_of_the_fire_snake |  |
| 3 | 네 천둥의 주먹 (fist_of_four_thunders) | four_elements | 스크립트 ki_spell |  |
| 3 | 꺾이지 않는 바람의 주먹 (fist_of_unbroken_air) | four_elements | 스크립트 fist_of_unbroken_air |  |
| 3 | 화살 튕기기 (deflect_missiles) |  | 스크립트 deflect_attacks; 반응 |  |
| 3 | 취권 (drunken_technique) | drunken_master | 스크립트 drunken_technique |  |
| 3 | 취중 공연 (drunken_performance) | drunken_master | 부여 skills |  |
| 3 | 능청스러운 한 잔 (cheeky_tipple) | drunken_master | 부여 condition_immunities |  |
| 3 | 바람 타기 (ride_the_wind) | four_elements | 스크립트 ki_spell |  |
| 3 | 열린 손 기법 (open_hand_technique) | open_hand | 태그 open_hand_technique; 설정 |  |
| 3 | 안개 자세 (mist_stance) | four_elements | 스크립트 ki_spell |  |
| 3 | 불사조의 불꽃 (flames_of_the_phoenix) | four_elements | 스크립트 ki_spell |  |
| 3 | 정상의 징 (gong_of_the_summit) | four_elements | 스크립트 ki_spell |  |
| 3 | 지옥불의 포옹 (embrace_of_the_inferno) | four_elements | 스크립트 ki_spell |  |
| 3 | 북풍의 움켜쥠 (clench_of_the_north_wind) | four_elements | 스크립트 ki_spell |  |
| 3 | 물 채찍 (water_whip) | four_elements | 스크립트 water_whip; 설정 |  |
| 3 | 그림자 기술: 환영 (shadow_arts_illusion) | shadow | 부여 at_will |  |
| 4 | 취하게 하는 일격 (intoxicating_strike) | drunken_master | 스크립트 intoxicating_strike |  |
| 4 | 취하게 하는 일격(보너스) (intoxicating_strike_bonus) | drunken_master | 스크립트 intoxicating_strike |  |
| 4 | 파티의 주인공 (life_of_the_party) | drunken_master | 태그 life_of_the_party |  |
| 4 | 느린 낙하 (slow_fall) |  | 태그 slow_fall; 반응 |  |
| 5 | 추가 공격 (extra_attack) |  | 태그 extra_attack; 부여 attacks_per_action |  |
| 5 | 충격의 일격 (stunning_strike) |  | 태그 stunning_strike; 설정 |  |
| 5 | 그림자 망토 (shadow_cloak) | shadow | 스크립트 shadow_cloak |  |
| 6 | 기 강화 타격 (empowered_strikes) |  | 태그 empowered_strikes |  |
| 6 | 벌떡 일어서기 (leap_to_your_feet) | drunken_master | 태그 stand_up_one_tile |  |
| 6 | 기의 발현 (manifestation) | open_hand | 태그 manifestation; 설정 |  |
| 6 | 몸의 완전함 (wholeness_of_body) | open_hand | 스크립트 wholeness_of_body |  |
| 6 | 공격 되돌리기 (redirect_attack) | drunken_master | 반응 |  |
| 6 | 그림자 걸음 (shadow_step) | shadow | 스크립트 shadow_step |  |
| 7 | 마음의 고요 (stillness_of_mind) |  | 태그 stillness_of_mind |  |
| 7 | 회피 (evasion) |  | 태그 evasion |  |
| 9 | 기 공명: 주먹 (ki_resonation_punch) | open_hand | 스크립트 ki_resonation_punch |  |
| 9 | 기 공명: 주먹(보너스) (ki_resonation_punch_bonus) | open_hand | 스크립트 ki_resonation_punch |  |
| 9 | 기 공명: 폭발 (ki_resonation_blast) | open_hand | 스크립트 ki_resonation_blast |  |
| 9 | 고급 맨몸 이동 (advanced_unarmoured_movement) |  | 태그 ignore_difficult_terrain, jump_plus_1, jump_plus_1, jump_plus_1, jump_plus_1 |  |
| 9 | 술 깨는 깨달음 (sobering_realisation) | drunken_master | 스크립트 sobering_realisation |  |
| 9 | 향상된 원소 시전 (improved_elemental_casting) | four_elements | 태그 improved_elemental_casting |  |
| 10 | 신체의 순수 (purity_of_body) |  | 부여 damage_immunities, condition_immunities |  |
| 11 | 평온 (tranquillity) | open_hand | 태그 tranquillity |  |
| 11 | 그림자 일격 (shadow_strike) | shadow | 스크립트 shadow_strike |  |
| 11 | 술꾼의 행운 (drunkards_luck) | drunken_master | 태그 drunkards_luck; 설정 |  |

### 팔라딘 (paladin) — 생명 주사위 d10, 역할 melee

| 레벨 | 기능 | 하위 | 장치 | 상태 |
| --- | --- | --- | --- | --- |
| 1 | 신성한 손길 (lay_on_hands) |  | 스크립트 lay_on_hands |  |
| 2 | 전투 방식 (fighting_style) |  | 고르기(feat) |  |
| 2 | 팔라딘의 강타 (paladins_smite) |  | 처리: 클래스 always_prepared(신성한 강타) + 자원 innate_divine_smite(슬롯 없이 긴 휴식마다 1회 — 무료 횟수 먼저) |  |
| 3 | 자연의 분노 (natures_wrath) | ancients | 스크립트 oath_save_condition |  |
| 3 | 신앙 없는 자 퇴치 (turn_the_faithless) | ancients | 스크립트 oath_turn |  |
| 3 | 맹세 주문(복수) (oath_spells_vengeance) | vengeance | 처리: 하위 클래스 always_prepared |  |
| 3 | 심문관의 힘 (inquisitors_might) | vengeance | 스크립트 oath_ally_condition |  |
| 3 | 적 물리치기 (abjure_enemy) | vengeance | 스크립트 oath_save_condition |  |
| 3 | 적대의 맹세 (vow_of_enmity) | vengeance | 스크립트 vow_of_enmity |  |
| 3 | 맹세 주문(왕관) (oath_spells_crown) | crown | 처리: 하위 클래스 always_prepared |  |
| 3 | 올바른 명료함 (righteous_clarity) | crown | 스크립트 oath_ally_condition |  |
| 3 | 투사의 도전 (champion_challenge) | crown | 스크립트 champion_challenge |  |
| 3 | 전세 역전 (turn_the_tide) | crown | 스크립트 turn_the_tide |  |
| 3 | 파기자 주문 (oath_spells_oathbreaker) | oathbreaker | 처리: 하위 클래스 always_prepared |  |
| 3 | 앙심 어린 고통 (spiteful_suffering) | oathbreaker | 스크립트 oath_save_condition |  |
| 3 | 언데드 조종 (control_undead) | oathbreaker | 스크립트 control_undead |  |
| 3 | 무시무시한 모습 (dreadful_aspect) | oathbreaker | 스크립트 dreadful_aspect |  |
| 3 | 치유의 광휘 (healing_radiance) | ancients | 스크립트 healing_radiance |  |
| 3 | 맹세 주문(고대인) (oath_spells_ancients) | ancients | 처리: 하위 클래스 always_prepared |  |
| 3 | 신성 변환 (channel_divinity) |  | 처리: 자원 channel_divinity(2회, 짧은 휴식에 1회 회복) — 하위 클래스 기능이 쓴다 |  |
| 3 | 부정한 것 퇴치 (turn_the_unholy) | devotion | 스크립트 oath_turn |  |
| 3 | 신성한 무기 (sacred_weapon) | devotion | 스크립트 sacred_weapon |  |
| 3 | 신성한 질책 (holy_rebuke) | devotion | 스크립트 holy_rebuke |  |
| 3 | 맹세 주문(헌신) (oath_spells_devotion) | devotion | 처리: 하위 클래스 always_prepared |  |
| 3 | 신성 감지 (divine_sense) |  | 스크립트 divine_sense |  |
| 5 | 추가 공격 (extra_attack) |  | 태그 extra_attack; 부여 attacks_per_action |  |
| 5 | 충직한 탈것 (faithful_steed) |  | 처리: 클래스 always_prepared(탈것 찾기) + 자원 innate_find_steed(슬롯 없이 긴 휴식마다 1회). 올라타기 없음(BG3식 동료) |  |
| 6 | 보호의 오라 (aura_of_protection) |  | 오라(auras.gd) |  |
| 7 | 증오의 오라 (aura_of_hate) | oathbreaker | 오라(auras.gd) |  |
| 7 | 신성한 충성 (divine_allegiance) | crown | 반응 |  |
| 7 | 끈질긴 복수자 (relentless_avenger) | vengeance | 태그 relentless_avenger |  |
| 7 | 수호의 오라 (aura_of_warding) | ancients | 오라(auras.gd) |  |
| 7 | 헌신의 오라 (aura_of_devotion) | devotion | 오라(auras.gd) |  |
| 9 | 적 퇴치 (abjure_foes) |  | 스크립트 abjure_foes |  |
| 10 | 용기의 오라 (aura_of_courage) |  | 오라(auras.gd) |  |
| 11 | 빛나는 일격 (radiant_strikes) |  | 부여 weapon_hit_bonus |  |

### 레인저 (ranger) — 생명 주사위 d10, 역할 ranged

| 레벨 | 기능 | 하위 | 장치 | 상태 |
| --- | --- | --- | --- | --- |
| 1 | 선호하는 적 (favored_enemy) |  | 처리: 클래스 always_prepared(사냥꾼의 표식) + 자원 innate_hunters_mark(슬롯 없이 긴 휴식마다 2회, 5레벨 3회 — 무료 횟수 먼저) |  |
| 2 | 노련한 탐험가 (deft_explorer) |  | 고르기(expertise) |  |
| 2 | 전투 방식 (fighting_style) |  | 고르기(feat) |  |
| 3 | 모인 무리 (gathered_swarm) | swarmkeeper | 고르기(option); 설정 |  |
| 3 | 공포의 매복자 (dread_ambusher) | gloom_stalker | 태그 dread_ambusher; 부여 initiative_bonus |  |
| 3 | 뛰어난 암시야 (superior_darkvision) | gloom_stalker | 부여 darkvision_tiles |  |
| 3 | 그늘 장막 (umbral_shroud) | gloom_stalker | 스크립트 shadow_cloak |  |
| 3 | 레인저의 동료 (rangers_companion) | beast_master | 스크립트 rangers_companion; 설정 |  |
| 3 | 사냥감 (hunters_prey) | hunter | 고르기(option) |  |
| 5 | 동료의 결속 (companions_bond) | beast_master | 처리: rangers_companion |  |
| 5 | 추가 공격 (extra_attack) |  | 태그 extra_attack; 부여 attacks_per_action |  |
| 6 | 방랑 (roving) |  | 태그 fast_movement, climber |  |
| 7 | 방어 전술 (defensive_tactics) | hunter | 고르기(option) |  |
| 7 | 뛰어난 훈련 (exceptional_training) | beast_master | 처리: 생략 |  |
| 7 | 강철 정신 (iron_mind) | gloom_stalker | 부여 save_proficiencies |  |
| 7 | 꿈틀대는 물결 (writhing_tide) | swarmkeeper | 스크립트 writhing_tide |  |
| 9 | 전문화(9레벨) (expertise_9) |  | 고르기(expertise) |  |
| 10 | 지치지 않음 (tireless) |  | 스크립트 tireless |  |
| 11 | 일제 사격 (volley) | hunter | 스크립트 volley |  |
| 11 | 소용돌이 공격 (whirlwind_attack) | hunter | 스크립트 volley |  |
| 11 | 야수의 분노 (bestial_fury) | beast_master | 처리: rangers_companion |  |
| 11 | 추적자의 연타 (stalkers_flurry) | gloom_stalker | 태그 stalkers_flurry |  |
| 11 | 강력한 무리 (mighty_swarm) | swarmkeeper | 태그 mighty_swarm |  |

### 로그 (rogue) — 생명 주사위 d8, 역할 ranged

| 레벨 | 기능 | 하위 | 장치 | 상태 |
| --- | --- | --- | --- | --- |
| 1 | 전문화 (expertise) |  | 처리: 생성기 — 명세 expertise(숙련 기능의 숙련 보너스 2배) |  |
| 1 | 급소 공격 (sneak_attack) |  | 스크립트 sneak_attack; 태그 sneak_attack; 설정 |  |
| 2 | 교활한 행동 (cunning_action) |  | 태그 bonus_dash_disengage_hide |  |
| 3 | 대담함 (rakish_audacity) | swashbuckler | 태그 rakish_sneak; 부여 initiative_bonus_from |  |
| 3 | 화려한 발놀림 (fancy_footwork) | swashbuckler | 태그 no_oa_from_melee_target |  |
| 3 | 암살 (assassinate) | assassin | 태그 assassinate |  |
| 3 | 재빠른 손놀림 (assassins_alacrity) | assassin | 처리: 탐험 중 공격은 행동 비용이 없어(탐험 규칙) 전투 시작 때 행동·보너스 행동이 그대로 있다 |  |
| 3 | 마법사의 손 손재주 (mage_hand_legerdemain) | arcane_trickster |  | 보류(deferred) |
| 3 | 주문 시전(비전 사기꾼) (at_spellcasting) | arcane_trickster | 처리: 생성기 — 하위 클래스 spellcasting(1/3 시전자, 위저드 목록, 지능, 명세 subclass_spells) |  |
| 3 | 2층 작업 (second_story_work) | thief | 태그 fall_resistance, climber |  |
| 3 | 빠른 손 (fast_hands) | thief | 태그 extra_bonus_action |  |
| 3 | 안정된 조준 (steady_aim) |  | 스크립트 steady_aim |  |
| 4 | 지저분한 수법 (dirty_tricks) | swashbuckler | 부여 special_attacks |  |
| 5 | 교묘한 회피 (uncanny_dodge) |  | 스크립트 uncanny_dodge; 반응 |  |
| 5 | 교활한 일격 (cunning_strike) |  | 스크립트 cunning_strike; 태그 cunning_strike; 설정 |  |
| 6 | 전문화(6레벨) (expertise_6) |  | 고르기(expertise) |  |
| 7 | 믿음직한 재능 (reliable_talent) |  | 태그 reliable_talent |  |
| 7 | 회피 (evasion) |  | 태그 evasion |  |
| 9 | 최상급 은신 (supreme_sneak) | thief | 스크립트 supreme_sneak |  |
| 9 | 마법 매복 (magical_ambush) | arcane_trickster | 태그 magical_ambush |  |
| 9 | 위장 신분 (infiltration_expertise) | assassin |  | 보류(deferred) |
| 9 | 허세 (panache) | swashbuckler | 스크립트 panache |  |
| 11 | 향상된 교활한 일격 (improved_cunning_strike) |  | 태그 improved_cunning_strike; 설정 |  |

### 소서러 (sorcerer) — 생명 주사위 d6, 역할 caster

| 레벨 | 기능 | 하위 | 장치 | 상태 |
| --- | --- | --- | --- | --- |
| 1 | 무덤의 힘 (strength_of_the_grave) | shadow_magic | 스크립트 strength_of_the_grave |  |
| 1 | 어둠의 눈 (eyes_of_the_dark) | shadow_magic | 부여 darkvision_tiles |  |
| 1 | 폭풍 비행 (tempestuous_flight) | storm | 스크립트 surge_teleport |  |
| 1 | 폭풍의 마법 (tempestuous_magic) | storm | 태그 tempestuous_magic |  |
| 1 | 급증: 순간 이동 (surge_teleport_action) | wild_magic | 스크립트 surge_teleport |  |
| 1 | 혼돈의 물결 (tides_of_chaos) | wild_magic | 스크립트 tides_of_chaos |  |
| 1 | 야생 마법 급증 (wild_magic_surge) | wild_magic | 태그 wild_magic_surge |  |
| 1 | 용의 혈통 조상 (draconic_ancestry) | draconic | 고르기(option) |  |
| 1 | 용의 회복력 (draconic_resilience) | draconic | 태그 unarmored_defense_13; 부여 hp_per_level |  |
| 1 | 타고난 마법 (innate_sorcery) |  | 스크립트 innate_sorcery |  |
| 2 | 마법의 샘 (font_of_magic) |  | 처리: 자원 sorcery_points(레벨만큼, 긴 휴식) + 기능 슬롯→점수·점수→슬롯 |  |
| 2 | 슬롯을 마법 점수로 (convert_slot) |  | 스크립트 convert_slot |  |
| 2 | 마법 점수로 슬롯 (create_slot) |  | 스크립트 create_slot |  |
| 2 | 주문 변형 (metamagic) |  | 고르기(option); 설정 |  |
| 3 | 어둠의 눈: 어둠 (eyes_darkness) | shadow_magic | 스크립트 ki_spell |  |
| 5 | 마법 회복 (sorcerous_restoration) |  | 태그 sorcerous_restoration |  |
| 6 | 운 비틀기 (bend_luck) | wild_magic | 태그 bend_luck; 반응 |  |
| 6 | 폭풍의 심장 (heart_of_the_storm) | storm | 태그 heart_of_the_storm; 부여 resistances |  |
| 6 | 원소 친화 (elemental_affinity) | draconic | 고르기(option) |  |
| 6 | 불길한 징조의 사냥개 (hound_of_ill_omen) | shadow_magic | 스크립트 hound_of_ill_omen |  |
| 7 | 마법의 화신 (sorcery_incarnate) |  | 태그 sorcery_incarnate |  |
| 10 | 주문 변형(10레벨) (metamagic_10) |  | 고르기(option) |  |
| 11 | 통제된 혼돈 (controlled_chaos) | wild_magic | 태그 controlled_chaos |  |
| 11 | 용의 날개 (draconic_wings) | draconic | 스크립트 draconic_wings |  |
| 11 | 폭풍의 분노 (storms_fury) | storm | 태그 storms_fury; 반응 |  |
| 11 | 그림자 걷기 (shadow_walk) | shadow_magic | 스크립트 surge_teleport |  |

### 워락 (warlock) — 생명 주사위 d8, 역할 caster

| 레벨 | 기능 | 하위 | 장치 | 상태 |
| --- | --- | --- | --- | --- |
| 1 | 주술검사의 저주 (hexblades_curse) | hexblade | 스크립트 hexblades_curse |  |
| 1 | 저주 무기 결속 (bind_hexed_weapon) | hexblade | 스크립트 bind_hexed_weapon |  |
| 1 | 주술 전사 (hex_warrior) | hexblade | 부여 armor_training, weapon_training |  |
| 1 | 주술검사 주문 (hexblade_spells) | hexblade | 처리: 하위 클래스 always_prepared |  |
| 1 | 필멸의 상기 (mortal_reminder) | great_old_one | 태그 mortal_reminder |  |
| 1 | 위대한 옛것 주문 (goo_spells) | great_old_one | 처리: 하위 클래스 always_prepared |  |
| 1 | 요정의 존재감 (fey_presence) | archfey | 스크립트 fey_presence; 설정 |  |
| 1 | 요정 후원자 주문 (archfey_spells) | archfey | 처리: 하위 클래스 always_prepared |  |
| 1 | 악마의 주문 (fiend_spells) | fiend | 처리: 하위 클래스 always_prepared |  |
| 1 | 어둠의 축복 (dark_ones_blessing) | fiend | 태그 dark_ones_blessing |  |
| 1 | 계약 마법 (pact_magic) |  | 처리: 클래스 spellcasting — 슬롯이 모두 같은 레벨(1·2·3), 짧은 휴식에 회복(slot_recharge short), 낮은 주문은 그 레벨로 올려 시전 |  |
| 1 | 섬뜩한 영창 (eldritch_invocations) |  | 고르기(option) |  |
| 2 | 마법적 기지 (magical_cunning) |  | 스크립트 magical_cunning |  |
| 2 | 섬뜩한 영창(2레벨) (eldritch_invocations_2) |  | 고르기(option) |  |
| 5 | 섬뜩한 영창(5레벨) (eldritch_invocations_5) |  | 고르기(option) |  |
| 6 | 어둠의 자의 행운 (dark_ones_own_luck) | fiend | 스크립트 dark_ones_own_luck |  |
| 6 | 저주받은 망령 (accursed_spectre) | hexblade |  | 보류(deferred) |
| 6 | 안개 탈출 (misty_escape) | archfey | 태그 misty_escape; 반응 |  |
| 6 | 엔트로피의 결계 (entropic_ward) | great_old_one | 반응 |  |
| 7 | 섬뜩한 영창(7레벨) (eldritch_invocations_7) |  | 고르기(option) |  |
| 9 | 후원자와 접촉 (contact_patron) |  |  | 보류(deferred) |
| 9 | 섬뜩한 영창(9레벨) (eldritch_invocations_9) |  | 고르기(option) |  |
| 10 | 저주의 갑옷 (armour_of_hexes) | hexblade | 태그 armour_of_hexes; 반응 |  |
| 10 | 생각의 방패 (thought_shield) | great_old_one | 태그 thought_shield; 부여 resistances |  |
| 10 | 현혹하는 방어 (beguiling_defences) | archfey | 부여 condition_immunities |  |
| 10 | 악마의 회복력 (fiendish_resilience) | fiend | 고르기(option) |  |
| 11 | 신비한 비전(6레벨) (mystic_arcanum_6) |  | 고르기(spell) |  |
| 12 | 섬뜩한 영창(12레벨) (eldritch_invocations_12) |  | 고르기(option) |  |

### 위저드 (wizard) — 생명 주사위 d6, 역할 caster

| 레벨 | 기능 | 하위 | 장치 | 상태 |
| --- | --- | --- | --- | --- |
| 1 | 의식 숙련 (ritual_adept) |  | 태그 ritual_from_spellbook |  |
| 1 | 비전 회복 (arcane_recovery) |  | 스크립트 arcane_recovery |  |
| 2 | 칼날노래 (bladesong) | bladesinger | 스크립트 bladesong |  |
| 2 | 전쟁과 노래의 수련 (training_in_war_and_song) | bladesinger | 부여 armor_training, skills, weapon_training |  |
| 2 | 실험 연금술 (experimental_alchemy) | transmuter |  | 보류(deferred) |
| 2 | 변환학파 학자 (transmuter_savant) | transmuter | 부여 scribe_discount |  |
| 2 | 섬뜩한 수확 (grim_harvest) | necromancer | 태그 grim_harvest |  |
| 2 | 사령학파 학자 (necromancer_savant) | necromancer | 부여 scribe_discount |  |
| 2 | 향상된 하급 환영 (improved_minor_illusion) | illusionist | 부여 bonus_action_spells |  |
| 2 | 환영학파 학자 (illusionist_savant) | illusionist | 부여 scribe_discount |  |
| 2 | 주문 조각 (sculpt_spells) | evoker | 태그 sculpt_spells |  |
| 2 | 방출학파 학자 (evoker_savant) | evoker | 부여 scribe_discount |  |
| 2 | 최면 응시 (hypnotic_gaze) | enchanter | 스크립트 hypnotic_gaze |  |
| 2 | 환혹학파 학자 (enchanter_savant) | enchanter | 부여 scribe_discount |  |
| 2 | 비전 결계 (arcane_ward) | abjurer | 태그 arcane_ward |  |
| 2 | 방호학파 학자 (abjurer_savant) | abjurer | 부여 scribe_discount |  |
| 2 | 예지 (portent) | diviner | 태그 portent; 반응 |  |
| 2 | 예언학파 학자 (diviner_savant) | diviner | 부여 scribe_discount |  |
| 2 | 소환학파 학자 (conjurer_savant) | conjurer | 부여 scribe_discount |  |
| 2 | 하급 소환: 물 (minor_conjuration) | conjurer | 스크립트 minor_conjuration |  |
| 2 | 학자 (scholar) |  | 고르기(expertise) |  |
| 5 | 주문 암기 (memorize_spell) |  | 태그 prepare_swap_short_rest |  |
| 6 | 강력한 소마법 (potent_cantrip) | evoker | 태그 cantrip_half_on_save |  |
| 6 | 선한 자리바꿈 (benign_transposition) | conjurer | 스크립트 benign_transposition |  |
| 6 | 추가 공격(검무가) (bladesinger_extra_attack) | bladesinger | 태그 extra_attack; 부여 attacks_per_action |  |
| 6 | 본능적 매혹 (instinctive_charm) | enchanter | 반응 |  |
| 6 | 투명 간파 (reveal_invisible) | illusionist | 스크립트 reveal_invisible |  |
| 6 | 변환자의 돌 (transmuters_stone) | transmuter | 스크립트 transmuters_stone; 설정 |  |
| 6 | 투사 결계 (projected_ward) | abjurer | 반응 |  |
| 6 | 언데드 노예 (undead_thralls) | necromancer |  | 보류(deferred) |
| 6 | 숙련된 예언 (expert_divination) | diviner | 태그 expert_divination |  |
| 10 | 변신술사 (shapechanger) | transmuter |  | 보류(deferred) |
| 10 | 방어의 노래 (song_of_defence) | bladesinger | 반응 |  |
| 10 | 죽음에 익숙함 (inured_to_undeath) | necromancer | 부여 resistances |  |
| 10 | 향상된 방호 (improved_abjuration) | abjurer | 태그 improved_abjuration |  |
| 10 | 환영 분신 (illusory_self) | illusionist | 반응 |  |
| 10 | 강화된 방출 (empowered_evocation) | evoker | 태그 evocation_add_mod |  |
| 10 | 집중된 소환 (focused_conjuration) | conjurer | 태그 focused_conjuration |  |
| 10 | 갈라진 환혹 (split_enchantment) | enchanter | 태그 split_enchantment |  |
| 10 | 셋째 눈 (third_eye) | diviner | 스크립트 third_eye; 설정 |  |

## 주문

- 상태: included 185, excluded_v1 80, candidate_exclusion 6
- 포함 주문 레벨별: 2레벨 45, 0레벨 24, 3레벨 30, 4레벨 16, 1레벨 50, 6레벨 10, 5레벨 10
- 스크립트 주문 77개, 그중 포함인데 미구현: 없음
- 아이콘(icon) 없는 포함 주문(학파 색 별로 표시): 없음
- 클래스 주문 목록: wizard 178, sorcerer 117, cleric 91, ranger 40, paladin 32, bard 100, druid 93, warlock 55

## 아이템

- 분류: gear 6, magic 42, currency 1, potion 5, food 1, scroll 2, tool 2
- 동작하는 분류: potion(마시기·먹이기·던지기), scroll(두루마리 읽기), food(캠프 보급품), tool(자물쇠·함정). **magic(장착 효과)은 아직 동작 없음** — 장비 칸 설계가 먼저 필요

## 능력 태그 사용

| 태그 | 이름 | 쓰는 곳 |
| --- | --- | --- |
| agonizing_blast | 고통의 화살 | (몬스터 특성 또는 아직 없음) |
| arcane_ward | 비전 결계 | wizard |
| armor_ac_plus_1 | 방어 | 재주 defense |
| armour_of_hexes | 저주의 갑옷 | warlock |
| aspect_bear | 짐승의 면모: 곰 | (몬스터 특성 또는 아직 없음) |
| aspect_crocodile | 짐승의 면모: 악어 | (몬스터 특성 또는 아직 없음) |
| aspect_elk | 짐승의 면모: 엘크 | (몬스터 특성 또는 아직 없음) |
| aspect_honey_badger | 짐승의 면모: 벌꿀오소리 | (몬스터 특성 또는 아직 없음) |
| aspect_tiger | 짐승의 면모: 호랑이 | (몬스터 특성 또는 아직 없음) |
| aspect_wolf | 짐승의 면모: 늑대 | (몬스터 특성 또는 아직 없음) |
| aspect_wolverine | 짐승의 면모: 울버린 | (몬스터 특성 또는 아직 없음) |
| assassinate | 암살 | rogue |
| bend_luck | 운 비틀기 | sorcerer |
| bestial_bear | 곰의 심장 | (몬스터 특성 또는 아직 없음) |
| bestial_eagle | 독수리의 심장 | (몬스터 특성 또는 아직 없음) |
| bestial_elk | 엘크의 심장 | (몬스터 특성 또는 아직 없음) |
| bestial_tiger | 호랑이의 심장 | (몬스터 특성 또는 아직 없음) |
| bestial_wolf | 늑대의 심장 | (몬스터 특성 또는 아직 없음) |
| blessed_healer | 축복받은 치유자 | cleric |
| bonus_attack_on_crit_kill | 강타 추가 공격 | (몬스터 특성 또는 아직 없음) |
| bonus_dash_disengage_hide | 교활한 행동 | rogue |
| brawler | 주먹다짐 | (몬스터 특성 또는 아직 없음) |
| brutal_critical | 잔혹한 치명타 | barbarian |
| brutal_strike | 잔혹한 일격 | (몬스터 특성 또는 아직 없음) |
| cantrip_add_mod | 강력한 주문 시전 | (몬스터 특성 또는 아직 없음) |
| cantrip_half_on_miss | 강력한 소마법 | (몬스터 특성 또는 아직 없음) |
| cantrip_half_on_save | 강력한 소마법(BG3) | wizard |
| carry_quarter_more | 운반 +25% | barbarian, 종족 human |
| charger | 돌격병 | (몬스터 특성 또는 아직 없음) |
| check_boost_d10 | 전술적 판단 | (몬스터 특성 또는 아직 없음) |
| climber | 등반 | ranger, rogue |
| combat_inspiration | 전투 영감 | bard |
| concentration_advantage | 집중 유리 | (몬스터 특성 또는 아직 없음) |
| controlled_chaos | 통제된 혼돈 | sorcerer |
| cosmic_omen | 우주의 징조 | druid |
| countercharm | 대항 매혹 | bard |
| crit_free_move | 치명타 뒤 이동 | (몬스터 특성 또는 아직 없음) |
| crossbow_point_blank | 근접 석궁 | (몬스터 특성 또는 아직 없음) |
| crossbow_wounding | 깊은 상처 석궁 | (몬스터 특성 또는 아직 없음) |
| cunning_strike | 교활한 일격 | rogue |
| curving_shot | 휘는 화살 | fighter |
| dark_ones_blessing | 어둠의 축복 | warlock |
| dash_ignores_difficult | 질주 험지 무시 | (몬스터 특성 또는 아직 없음) |
| dash_temp_hp | 질주 임시 HP | (몬스터 특성 또는 아직 없음) |
| destructive_wrath | 파괴의 분노 | cleric |
| disc_blade_of_rime | 서리 칼날 | (몬스터 특성 또는 아직 없음) |
| disc_chill_of_the_mountain | 산의 냉기 | (몬스터 특성 또는 아직 없음) |
| disc_clench_of_the_north_wind | 북풍의 움켜쥠 | (몬스터 특성 또는 아직 없음) |
| disc_embrace_of_the_inferno | 지옥불의 포옹 | (몬스터 특성 또는 아직 없음) |
| disc_fangs_of_the_fire_snake | 불뱀의 송곳니 | (몬스터 특성 또는 아직 없음) |
| disc_fist_of_four_thunders | 네 천둥의 주먹 | (몬스터 특성 또는 아직 없음) |
| disc_fist_of_unbroken_air | 꺾이지 않는 바람의 주먹 | (몬스터 특성 또는 아직 없음) |
| disc_flames_of_the_phoenix | 불사조의 불꽃 | (몬스터 특성 또는 아직 없음) |
| disc_gong_of_the_summit | 정상의 징 | (몬스터 특성 또는 아직 없음) |
| disc_mist_stance | 안개 자세 | (몬스터 특성 또는 아직 없음) |
| disc_ride_the_wind | 바람 타기 | (몬스터 특성 또는 아직 없음) |
| disc_rush_of_the_gale_spirits | 돌풍 정령의 쇄도 | (몬스터 특성 또는 아직 없음) |
| disc_sphere_of_elemental_balance | 원소 균형의 구 | (몬스터 특성 또는 아직 없음) |
| disc_sweeping_cinder_strike | 휩쓰는 불씨 일격 | (몬스터 특성 또는 아직 없음) |
| disc_touch_of_the_storm | 폭풍의 손길 | (몬스터 특성 또는 아직 없음) |
| disc_water_whip | 물 채찍 | (몬스터 특성 또는 아직 없음) |
| draconic_acid | 용의 혈통 acid | (몬스터 특성 또는 아직 없음) |
| draconic_cold | 용의 혈통 cold | (몬스터 특성 또는 아직 없음) |
| draconic_fire | 용의 혈통 fire | (몬스터 특성 또는 아직 없음) |
| draconic_lightning | 용의 혈통 lightning | (몬스터 특성 또는 아직 없음) |
| draconic_poison | 용의 혈통 poison | (몬스터 특성 또는 아직 없음) |
| dread_ambusher | 공포의 매복자 | ranger |
| drunkards_luck | 술꾼의 행운 | monk |
| dual_wield_ac | 쌍수 방어 | (몬스터 특성 또는 아직 없음) |
| dual_wield_any | 무거운 쌍수 | (몬스터 특성 또는 아직 없음) |
| dueling | 결투 | 재주 dueling |
| eldritch_mind | 섬뜩한 정신 | (몬스터 특성 또는 아직 없음) |
| eldritch_strike | 비전 일격 | fighter |
| empowered_strikes | 강화된 타격 | monk |
| escape_the_horde | 무리 탈출 | (몬스터 특성 또는 아직 없음) |
| evasion | 회피 | monk, rogue |
| evocation_add_mod | 강화된 방출 | wizard |
| expert_divination | 숙련된 예언 | wizard |
| extra_attack | 추가 공격 | barbarian, bard, bard, fighter, fighter, monk, paladin, ranger, wizard |
| extra_bonus_action | 추가 보너스 행동 | rogue |
| extra_damage_wounded | 거상 학살자 | (몬스터 특성 또는 아직 없음) |
| fall_resistance | 낙하 저항 | rogue |
| fast_movement | 빠른 이동 | barbarian, ranger |
| focused_conjuration | 집중된 소환 | wizard |
| free_cast_class_spell | 신성 개입 | cleric |
| frenzy | 광란 | barbarian |
| giant_killer | 거인 사냥꾼 | (몬스터 특성 또는 아직 없음) |
| giants_rage | 거인의 분노 | barbarian |
| grim_harvest | 섬뜩한 수확 | wizard |
| guided_strike | 인도된 일격 | cleric |
| gwm_all_in | 강타 | (몬스터 특성 또는 아직 없음) |
| half_proficiency_physical | 절반 숙련(신체) | fighter |
| heart_of_the_storm | 폭풍의 심장 | sorcerer |
| heavy_armor_damage_reduction | 중갑 피해 감소 | (몬스터 특성 또는 아직 없음) |
| heightened_focus | 고양된 집중 | (몬스터 특성 또는 아직 없음) |
| heroic_warrior | 영웅 전사 | (몬스터 특성 또는 아직 없음) |
| horde_breaker | 무리 파괴자 | (몬스터 특성 또는 아직 없음) |
| hunters_lore | 사냥꾼의 지식 | (몬스터 특성 또는 아직 없음) |
| ignore_difficult_terrain | 험지 무시 | barbarian, druid, monk |
| immune_magic_sleep | 마법 수면 면역 | 종족 drow, 종족 elf, 종족 half_elf |
| improved_abjuration | 향상된 방호 | wizard |
| improved_cunning_strike | 향상된 교활한 일격 | rogue |
| improved_elemental_casting | 향상된 원소 시전 | monk |
| improved_wild_strike | 향상된 야생의 일격 | druid |
| instinctive_pounce | 본능적 도약 | (몬스터 특성 또는 아직 없음) |
| jack_of_all_trades | 만물박사 | bard |
| jump_dex | 민첩 도약 | (몬스터 특성 또는 아직 없음) |
| jump_half_more | 도약 +50% | (몬스터 특성 또는 아직 없음) |
| jump_plus_1 | 도약 +1칸 | fighter, fighter, monk, monk, monk, monk |
| life_of_the_party | 파티의 주인공 | monk |
| long_rest_inspiration | 기지 | (몬스터 특성 또는 아직 없음) |
| lucky | 행운의 별 | (몬스터 특성 또는 아직 없음) |
| mage_slayer | 마법사 사냥꾼 | (몬스터 특성 또는 아직 없음) |
| magic_ranged | 마법 화살 | fighter |
| magical_ambush | 마법 매복 | rogue |
| manifestation | 기의 발현 | monk |
| mark_spread | 먹잇감 확산 | (몬스터 특성 또는 아직 없음) |
| martial_arts | 무술 | monk |
| medium_armor_master | 중형 갑옷 숙달 | (몬스터 특성 또는 아직 없음) |
| melee_damage_advantage | 근접 피해 두 번 | (몬스터 특성 또는 아직 없음) |
| metamagic_careful | 신중한 주문 | (몬스터 특성 또는 아직 없음) |
| metamagic_distant | 원거리 주문 | (몬스터 특성 또는 아직 없음) |
| metamagic_extended | 연장된 주문 | (몬스터 특성 또는 아직 없음) |
| metamagic_heightened | 고양된 주문 | (몬스터 특성 또는 아직 없음) |
| metamagic_quickened | 빠른 주문 | (몬스터 특성 또는 아직 없음) |
| metamagic_seeking | 추적 주문 | (몬스터 특성 또는 아직 없음) |
| metamagic_subtle | 은밀한 주문 | (몬스터 특성 또는 아직 없음) |
| mighty_swarm | 강력한 무리 | ranger |
| mindless_rage | 광기 없는 분노 | barbarian |
| misty_escape | 안개 탈출 | warlock |
| mortal_reminder | 필멸의 상기 | warlock |
| multiattack_defense | 다중 공격 방어 | (몬스터 특성 또는 아직 없음) |
| nimble_escape | 날렵한 탈출 | (몬스터 특성 또는 아직 없음) |
| no_oa_from_melee_target | 치고 빠지기 | rogue |
| open_hand_technique | 열린 손 기법 | monk |
| pack_tactics | 무리 전술 | (몬스터 특성 또는 아직 없음) |
| pact_blade | 계약의 칼날 | (몬스터 특성 또는 아직 없음) |
| polearm_enter_oa | 장병기 경계 | (몬스터 특성 또는 아직 없음) |
| polearm_haft | 자루 공격 | (몬스터 특성 또는 아직 없음) |
| portent | 예지 | wizard |
| precision_attack | 정밀 공격 | (몬스터 특성 또는 아직 없음) |
| prepare_swap_short_rest | 주문 암기 | wizard |
| primal_strike | 원초의 일격 | druid |
| rakish_sneak | 대담한 급소 | rogue |
| ranged_weapon_attack_bonus | 궁술 | 재주 archery |
| reaper | 수확자 | cleric |
| reckless | 무모한 공격 | barbarian |
| relentless_avenger | 끈질긴 복수자 | paladin |
| reliable_talent | 믿음직한 재능 | rogue |
| repelling_blast | 밀어내는 화살 | (몬스터 특성 또는 아직 없음) |
| reroll_low_damage_two_handed | 대형 무기 전투 | 재주 great_weapon_fighting |
| reroll_natural_1 | 행운 | 종족 halfling |
| retaliation | 보복 | (몬스터 특성 또는 아직 없음) |
| riposte | 반격 | (몬스터 특성 또는 아직 없음) |
| ritual_from_spellbook | 의식 숙련 | wizard |
| savage_attacks | 야만적인 공격 | 종족 half_orc |
| sculpt_spells | 주문 조각 | wizard |
| self_restoration | 자기 회복 | (몬스터 특성 또는 아직 없음) |
| sentinel_oa | 파수 기회 공격 | (몬스터 특성 또는 아직 없음) |
| shield_dex_save_bonus | 방패 민첩 내성 | (몬스터 특성 또는 아직 없음) |
| short_rest_full_heal | 짧은 휴식 완전 회복 | (몬스터 특성 또는 아직 없음) |
| slow_fall | 느린 낙하 | monk |
| sneak_attack | 급소 공격 | rogue |
| sorcerous_restoration | 마법 회복 | sorcerer |
| sorcery_incarnate | 마법의 화신 | sorcerer |
| spell_crit_minus_1 | 주문 치명타 범위 | (몬스터 특성 또는 아직 없음) |
| spell_heal_bonus | 생명의 제자 | cleric |
| split_enchantment | 갈라진 환혹 | wizard |
| ss_all_in | 조준 | (몬스터 특성 또는 아직 없음) |
| ss_low_ground | 낮은 곳 사격 | (몬스터 특성 또는 아직 없음) |
| stalkers_flurry | 추적자의 연타 | ranger |
| stand_up_one_tile | 빠르게 일어서기 | monk |
| stealth_attack | 은신 공격 | (몬스터 특성 또는 아직 없음) |
| steel_will | 강철 의지 | (몬스터 특성 또는 아직 없음) |
| stillness_of_mind | 마음의 고요 | monk |
| storms_fury | 폭풍의 분노 | sorcerer |
| stunning_strike | 충격의 일격 | monk |
| sunlight_sensitivity | 햇빛 민감 | (몬스터 특성 또는 아직 없음) |
| surprise_immune | 기습 면역 | (몬스터 특성 또는 아직 없음) |
| swarm_bees | 벌 군단 | (몬스터 특성 또는 아직 없음) |
| swarm_jellyfish | 해파리 구름 | (몬스터 특성 또는 아직 없음) |
| swarm_moths | 나방 떼 | (몬스터 특성 또는 아직 없음) |
| tempestuous_magic | 폭풍의 마법 | sorcerer |
| thought_shield | 생각의 방패 | warlock |
| thunderbolt_strike | 벼락 일격 | cleric |
| touch_of_death | 죽음의 손길 | cleric |
| tranquillity | 평온 | monk |
| trap_sense | 함정 감각 | (몬스터 특성 또는 아직 없음) |
| twinkling_constellations | 반짝이는 별자리 | druid |
| two_weapon_fighting | 쌍수 전투 | 재주 two_weapon_fighting |
| unarmored_defense_13 | 용의 회복력 AC 13 | sorcerer |
| unarmored_defense_cha | 용의 비늘 | (몬스터 특성 또는 아직 없음) |
| unarmored_defense_con | 맨몸 방어(건강) | barbarian |
| unarmored_defense_wis | 맨몸 방어(지혜) | monk |
| unarmored_movement | 맨몸 이동 | monk |
| uncanny_metabolism | 신비한 대사 | (몬스터 특성 또는 아직 없음) |
| unstable_backlash | 불안정한 반발 | barbarian |
| war_caster_oa | 주문 기회 공격 | (몬스터 특성 또는 아직 없음) |
| war_magic | 전쟁 마법 | fighter |
| war_priest | 전쟁 사제 | cleric |
| wild_magic_rage | 야생 마법 분노 | barbarian |
| wild_magic_surge | 야생 마법 급증 | sorcerer |
| wild_strike | 야생의 일격 | druid |
