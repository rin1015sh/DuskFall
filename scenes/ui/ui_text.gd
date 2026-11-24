extends RefCounted
## 화면 글(한국어·영어 둘 다 — CLAUDE.md 작업 규칙). lang을 바꾸면 다음 그리기부터 바뀐다.

static var lang := "ko"

const TEXT := {
	"move": {"ko": "이동", "en": "Move"},
	"attack": {"ko": "공격", "en": "Attack"},
	"shove": {"ko": "밀치기", "en": "Shove"},
	"jump": {"ko": "점프", "en": "Jump"},
	"dash": {"ko": "질주", "en": "Dash"},
	"disengage": {"ko": "이탈", "en": "Disengage"},
	"hide": {"ko": "숨기", "en": "Hide"},
	"stand": {"ko": "일어서기", "en": "Stand Up"},
	"switch": {"ko": "무기 전환", "en": "Swap Weapons"},
	"end_turn": {"ko": "턴 종료", "en": "End Turn"},
	"round": {"ko": "라운드 %d", "en": "Round %d"},
	"enemy_turn": {"ko": "적의 턴", "en": "Enemy Turn"},
	"pick_targets": {"ko": "대상 %d/%s: %s — Enter·[시전]으로 바로 시전, 다시 누르면 빼기, Esc 취소", "en": "Targets %d/%s: %s — Enter or [Cast] to cast now, click again to remove, Esc to cancel"},
	"cast_now": {"ko": "시전", "en": "Cast"},
	"level_short": {"ko": "%d레벨", "en": "Lv %d"},
	"toggle_hp": {"ko": "HP 보기 (H)", "en": "Show HP (H)"},
	"toggle_highlight": {"ko": "물체 강조 (G)", "en": "Highlight (G)"},
	"victory": {"ko": "승리", "en": "Victory"},
	"defeat": {"ko": "패배 — 게임 오버", "en": "Defeat — Game Over"},
	"move_cost": {"ko": "이동 %d칸 (남은 %d)", "en": "Move %d (left %d)"},
	"opportunity": {"ko": "기회 공격 %d회", "en": "%d opportunity attack(s)"},
	"hit_chance": {"ko": "명중 %d%%", "en": "Hit %d%%"},
	"fail_chance": {"ko": "%s 실패 %d%%", "en": "%s fails %d%%"},
	"damage_range": {"ko": "피해 %d~%d (평균 %.1f)", "en": "Damage %d-%d (avg %.1f)"},
	"shove_chance": {"ko": "밀치기 성공 %d%% · %d칸", "en": "Shove %d%% · %d tiles"},
	"fall": {"ko": "낙하 %d단계", "en": "Fall %d levels"},
	"blocked": {"ko": "불가: %s", "en": "Not possible: %s"},
	"reaction_preview": {"ko": "칸 반응: %s", "en": "Tile reactions: %s"},
	"spread_warning": {"ko": "다음 라운드에 불이 번진다: %s", "en": "Fire spreads next round: %s"},
	"threatened": {"ko": "위협받음", "en": "Threatened"},
	"high_ground": {"ko": "고지 %+d", "en": "High ground %+d"},
	"actions": {"ko": "행동 %d · 보너스 %d · 반응 %d · 이동 %d", "en": "Action %d · Bonus %d · Reaction %d · Move %d"},
	"hp": {"ko": "HP %d/%d", "en": "HP %d/%d"},
	"info": {"ko": "AC %d · 속도 %d칸 · 상태: %s", "en": "AC %d · Speed %d · Conditions: %s"},
	"none": {"ko": "없음", "en": "none"},
	"exploring": {"ko": "탐험", "en": "Exploring"},
	"combat_start": {"ko": "전투 시작!", "en": "Combat!"},
	"sneaking": {"ko": "은신 중", "en": "Sneaking"},
	"start_fight": {"ko": "공격 — 전투 시작", "en": "Attack — starts combat"},
	"surprise_hint": {"ko": "숨어 있으면 알아채지 못한 적은 기습", "en": "Unaware foes are surprised"},
	"talk": {"ko": "대화: %s", "en": "Talk: %s"},
	"pick_lock": {"ko": "자물쇠 따기 DC %d · 성공 %d%% (도둑 도구 %d)", "en": "Pick lock DC %d · %d%% (tools %d)"},
	"loot": {"ko": "열기", "en": "Open"},
	"owned": {"ko": "소유물 — 보이면 들킨다", "en": "Owned — stealing in sight is noticed"},
	"disarm": {"ko": "함정 해제 DC %d · 성공 %d%% (해체 도구 %d)", "en": "Disarm DC %d · %d%% (kits %d)"},
	"examine": {"ko": "살펴보기: %s DC %d · 성공 %d%%", "en": "Examine: %s DC %d · %d%%"},
	"sneak_on": {"ko": "은신 켬", "en": "Sneak: on"},
	"sneak_off": {"ko": "은신 끔", "en": "Sneak: off"},
	"linked": {"ko": "묶임", "en": "Linked"},
	"unlinked": {"ko": "풀림", "en": "Unlinked"},
	"short_rest": {"ko": "짧은 휴식 (%d)", "en": "Short Rest (%d)"},
	"long_rest": {"ko": "긴 휴식 (보급품 %d)", "en": "Long Rest (supplies %d)"},
	"save": {"ko": "저장", "en": "Save"},
	"load": {"ko": "불러오기", "en": "Load"},
	"saved": {"ko": "저장했다", "en": "Saved"},
	"lv": {"ko": "레벨", "en": " Lv"},
	"res_action": {"ko": "행동", "en": "Action"},
	"res_bonus": {"ko": "보너스 행동", "en": "Bonus Action"},
	"res_reaction": {"ko": "반응", "en": "Reaction"},
	"res_move": {"ko": "이동 %.1fm / %.1fm", "en": "Movement %.1fm / %.1fm"},
	"rt_move": {"ko": "실시간 이동(이번 라운드 %d칸)", "en": "Real-time move (%d this round)"},
	"camp_rested": {"ko": "캠프에서 쉬었다%s", "en": "Rested at camp%s"},
	"partial": {"ko": "(부분 휴식)", "en": " (partial)"},
	"swap": {"ko": "교체: %s ↔ %s", "en": "Swap: %s ↔ %s"},
	"gold": {"ko": "골드", "en": "Gold"},
	"buy": {"ko": "사기", "en": "Buy"},
	"sell": {"ko": "팔기", "en": "Sell"},
	"tab_passives": {"ko": "상시 발동", "en": "Passives"},
	"roll_title": {"ko": "%s 판정", "en": "%s Check"},
	"roll_accept": {"ko": "받아들이기", "en": "Accept"},
	"roll_go": {"ko": "굴리기", "en": "Roll"},
	"roll_inspiration": {"ko": "영감으로 다시 굴림 (%d)", "en": "Reroll with Inspiration (%d)"},
	"roll_tactical": {"ko": "전술적 판단 +1d10 (재기의 숨결 %d)", "en": "Tactical Mind +1d10 (Second Wind %d)"},
	"tab_all": {"ko": "전체", "en": "All"},
	"set_melee": {"ko": "근거리", "en": "Melee"},
	"set_ranged": {"ko": "원거리", "en": "Ranged"},
	"camp": {"ko": "캠프로(긴 휴식)", "en": "Go to Camp (Long Rest)"},
	"character": {"ko": "캐릭터", "en": "Character"},
	"inventory": {"ko": "소지품", "en": "Inventory"},
	"abilities": {"ko": "능력치", "en": "Abilities"},
	"armor_class": {"ko": "방어도", "en": "Armour Class"},
	"attack_bonus": {"ko": "공격 보너스", "en": "Attack Bonus"},
	"damage": {"ko": "피해", "en": "Damage"},
	"conditions": {"ko": "상태", "en": "Conditions"},
	"features": {"ko": "주목할 만한 특성", "en": "Notable Features"},
	"weight": {"ko": "무게", "en": "Weight"},
	"tab_common": {"ko": "공용", "en": "Common"},
	"tab_class": {"ko": "클래스", "en": "Class"},
	"tab_spells": {"ko": "주문", "en": "Spells"},
	"tab_items": {"ko": "아이템", "en": "Items"},
	"tab_explore": {"ko": "탐험", "en": "Explore"},
	"cost_action": {"ko": "행동", "en": "Action"},
	"cost_bonus": {"ko": "보너스 행동", "en": "Bonus Action"},
	"cost_attack": {"ko": "공격(공격 행동)", "en": "Attack (Attack action)"},
	"cost_reaction": {"ko": "반응", "en": "Reaction"},
	"cost_free": {"ko": "무료", "en": "Free"},
	"cost_explore": {"ko": "탐험 전용", "en": "Exploration"},
	"target_self": {"ko": "자신", "en": "Self"},
	"target_cell": {"ko": "칸", "en": "Tile"},
	"target_enemy": {"ko": "적", "en": "Enemy"},
	"target_ally": {"ko": "아군", "en": "Ally"},
	"target_ally_down": {"ko": "쓰러진 아군", "en": "Downed ally"},
	"target_creature": {"ko": "생물", "en": "Creature"},
	"regroup": {"ko": "모이기", "en": "Regroup"},
	"level_up": {"ko": "레벨 업 → %d", "en": "Level Up → %d"},
	"pick_feat": {"ko": "재주 고르기", "en": "Choose a Feat"},
	"new_class": {"ko": "새 클래스: %s 1레벨", "en": "New class: %s level 1"},
	"explore_status": {"ko": "%s (%d레벨, 경험치 %d) — 영감 %d · 골드 %d · 도둑 도구 %d · 해체 도구 %d", "en": "%s (Lv %d, XP %d) — Inspiration %d · Gold %d · Thieves' tools %d · Disarm kits %d"},
	"close": {"ko": "닫기", "en": "Close"},
	"use_inspiration": {"ko": "실패하면 영감으로 다시 굴림 (영감 %d)", "en": "Reroll failures with Inspiration (%d)"},
	"roll_result": {"ko": "d20 %d → %d (DC %d) %s", "en": "d20 %d → %d (DC %d) %s"},
	"success": {"ko": "성공", "en": "Success"},
	"failure": {"ko": "실패", "en": "Failure"},
	"spellbook": {"ko": "주문서", "en": "Spellbook"},
	"spells_window": {"ko": "주문 준비", "en": "Prepare Spells"},
	"prepared_n": {"ko": "준비 %d / %d", "en": "Prepared %d / %d"},
	"swap_all": {"ko": "자유롭게 바꿀 수 있다(다음 전투까지)", "en": "Change freely (until next combat)"},
	"swap_anytime": {"ko": "전투 밖에서는 언제든 바꿀 수 있다", "en": "Change any time outside combat"},
	"swap_left": {"ko": "바꿀 수 있는 주문 %d개(다음 전투까지)", "en": "%d change(s) left (until next combat)"},
	"swap_closed": {"ko": "긴 휴식 뒤에 바꿀 수 있다", "en": "Change after a long rest"},
	"swap_combat": {"ko": "전투 중에는 바꿀 수 없다", "en": "Can't change during combat"},
	"swap_none": {"ko": "이 클래스는 준비 주문을 바꾸지 않는다", "en": "This class doesn't prepare spells"},
	"cantrips": {"ko": "소마법", "en": "Cantrips"},
	"always_prepared": {"ko": "항상 준비", "en": "Always Prepared"},
	"spell_level_n": {"ko": "%d레벨", "en": "Level %d"},
	"learn_scrolls": {"ko": "두루마리에서 배우기", "en": "Learn from Scrolls"},
	"learn_btn": {"ko": "%s 배우기 (%dgp)", "en": "Learn %s (%dgp)"},
	"no_scrolls": {"ko": "배울 두루마리가 없다", "en": "No scrolls to learn"},
	"ritual": {"ko": "의식", "en": "Ritual"},
	"prep_full": {"ko": "준비 칸이 가득 찼다", "en": "No free preparation slot"},
	"slot_head": {"ko": "머리", "en": "Head"}, "slot_cloak": {"ko": "망토", "en": "Cloak"}, "slot_armor": {"ko": "갑옷", "en": "Armour"},
	"slot_hands": {"ko": "장갑", "en": "Hands"}, "slot_feet": {"ko": "신발", "en": "Feet"}, "slot_amulet": {"ko": "목걸이", "en": "Amulet"},
	"slot_ring1": {"ko": "반지", "en": "Ring"}, "slot_ring2": {"ko": "반지", "en": "Ring"},
	"slot_melee_main": {"ko": "근접 주무기", "en": "Melee Main Hand"}, "slot_melee_off": {"ko": "근접 보조", "en": "Melee Off Hand"},
	"slot_ranged_main": {"ko": "원거리 주무기", "en": "Ranged Main Hand"}, "slot_ranged_off": {"ko": "원거리 보조", "en": "Ranged Off Hand"},
	"short_head": {"ko": "머리", "en": "Head"}, "short_cloak": {"ko": "망토", "en": "Cloak"}, "short_armor": {"ko": "갑옷", "en": "Armour"},
	"short_hands": {"ko": "장갑", "en": "Hands"}, "short_feet": {"ko": "신발", "en": "Feet"}, "short_amulet": {"ko": "목걸이", "en": "Amulet"},
	"short_ring1": {"ko": "반지", "en": "Ring"}, "short_ring2": {"ko": "반지", "en": "Ring"}, "short_melee_main": {"ko": "주무기", "en": "Main"},
	"short_melee_off": {"ko": "보조", "en": "Off"}, "short_ranged_main": {"ko": "원거리", "en": "Ranged"}, "short_ranged_off": {"ko": "보조", "en": "Off"},
	"equip": {"ko": "장착", "en": "Equip"}, "unequip": {"ko": "벗기", "en": "Unequip"},
	"give_to": {"ko": "%s에게 넘기기", "en": "Give to %s"}, "send_camp": {"ko": "캠프로 보내기", "en": "Send to Camp"},
	"take_out": {"ko": "꺼내기", "en": "Take"}, "camp_stash": {"ko": "캠프 보관함", "en": "Camp Chest"},
	"use_item": {"ko": "사용", "en": "Use"}, "empty_slot": {"ko": "비어 있음", "en": "Empty"},
	"rarity_common": {"ko": "일반", "en": "Common"}, "rarity_uncommon": {"ko": "고급", "en": "Uncommon"}, "rarity_rare": {"ko": "희귀", "en": "Rare"},
	"rarity_very_rare": {"ko": "매우 희귀", "en": "Very Rare"}, "rarity_legendary": {"ko": "전설", "en": "Legendary"},
	"tip_ac": {"ko": "방어도 %+d", "en": "AC %+d"}, "tip_saves": {"ko": "내성 %+d", "en": "Saving throws %+d"},
	"tip_min": {"ko": "%s %d", "en": "%s becomes %d"}, "tip_adv": {"ko": "%s 유리", "en": "Advantage on %s"},
	"tip_cap": {"ko": "특수: %s", "en": "Special: %s"}, "tip_no_armor": {"ko": "(갑옷·방패 없을 때)", "en": "(no armour or shield)"},
	"tip_weapon": {"ko": "피해 %s %s", "en": "Damage %s %s"}, "tip_armor": {"ko": "방어도 %d", "en": "AC %d"},
	"tip_weight": {"ko": "%.2f kg · %d gp", "en": "%.2f kg · %d gp"},
}

## 엔진 사유(장비·소지품) → 영어
const EQUIP_REASON_EN := {
	"장비를 바꿀 수 없는 생물": "Can't change equipment", "소지품에 없다": "Not in inventory", "장비가 아니다": "Not equipment",
	"그 칸에 넣을 수 없다": "Doesn't fit that slot", "전투 중에는 갑옷을 바꿀 수 없다": "Can't change armour in combat",
	"훈련하지 않은 갑옷": "Not proficient with this armour", "빈 칸": "Empty slot",
}

## 엔진 사유(한국어) → 영어(주문 준비 창)
const REASON_EN := {
	"전투 중에는 바꿀 수 없다": "Can't change during combat", "긴 휴식 뒤에 바꿀 수 있다": "Change after a long rest",
	"준비 주문을 바꾸지 않는 클래스": "This class doesn't prepare spells", "주문서가 없다": "No spellbook",
	"주문 두루마리가 아니다": "Not a spell scroll", "두루마리가 없다": "No scroll", "내 클래스 주문 목록에 없는 주문": "Not on your class list",
	"소마법은 주문서에 적지 않는다": "Cantrips aren't copied", "아직 준비할 수 없는 레벨": "Level too high to prepare yet",
	"이미 주문서에 있다": "Already in spellbook", "전투 중에는 적을 수 없다": "Can't copy during combat",
}


## 엔진이 돌려준 사유를 화면 언어로(앞부분이 같으면 바꾼다 — "준비 수 초과(4)" 등은 그대로).
static func reason(text: String) -> String:
	if lang == "ko":
		return text
	if EQUIP_REASON_EN.has(text):
		return EQUIP_REASON_EN[text]
	for k: String in REASON_EN:
		if text.begins_with(k):
			return REASON_EN[k] + text.substr(k.length())
	if text.begins_with("금화가 모자라다"):
		return "Not enough gold" + text.substr("금화가 모자라다".length())
	if text.begins_with("이번에 바꿀 수 있는 주문은"):
		return "Changes allowed now:" + text.substr("이번에 바꿀 수 있는 주문은".length()).replace("개", "")
	if text.begins_with("준비 수 초과"):
		return "Too many prepared" + text.substr("준비 수 초과".length())
	return text


static func t(key: String) -> String:
	return TEXT.get(key, {}).get(lang, key)


## 데이터의 {"ko", "en"} 이름. 한국어가 비어 있으면 영어.
static func name_of(names: Dictionary) -> String:
	var v: Variant = names.get(lang)
	return v if v != null and v != "" else str(names.get("en", ""))


## 고르는 기능의 선택지 이름(생성 화면). 기능 데이터에 이름이 없는 option 값 — 모르면 id 그대로.
const CHOICE_NAMES := {
	"black": {"ko": "검은 용(산)", "en": "Black (Acid)"}, "blue": {"ko": "푸른 용(번개)", "en": "Blue (Lightning)"},
	"brass": {"ko": "놋쇠 용(화염)", "en": "Brass (Fire)"}, "bronze": {"ko": "청동 용(번개)", "en": "Bronze (Lightning)"},
	"copper": {"ko": "구리 용(산)", "en": "Copper (Acid)"}, "gold": {"ko": "황금 용(화염)", "en": "Gold (Fire)"},
	"green": {"ko": "초록 용(독)", "en": "Green (Poison)"}, "red": {"ko": "붉은 용(화염)", "en": "Red (Fire)"},
	"silver": {"ko": "은빛 용(냉기)", "en": "Silver (Cold)"}, "white": {"ko": "하얀 용(냉기)", "en": "White (Cold)"},
	"bounty_hunter": {"ko": "현상금 사냥꾼", "en": "Bounty Hunter"}, "keeper_of_the_veil": {"ko": "장막의 수호자", "en": "Keeper of the Veil"},
	"mage_breaker": {"ko": "마법 파괴자", "en": "Mage Breaker"}, "ranger_knight": {"ko": "레인저 기사", "en": "Ranger Knight"},
	"sanctified_stalker": {"ko": "성별된 추적자", "en": "Sanctified Stalker"}, "beast_tamer": {"ko": "짐승 조련사", "en": "Beast Tamer"},
	"urban_tracker": {"ko": "도시 추적자", "en": "Urban Tracker"}, "wasteland_cold": {"ko": "황무지 방랑자: 냉기", "en": "Wasteland Wanderer: Cold"},
	"wasteland_fire": {"ko": "황무지 방랑자: 화염", "en": "Wasteland Wanderer: Fire"}, "wasteland_poison": {"ko": "황무지 방랑자: 독", "en": "Wasteland Wanderer: Poison"},
}


static func choice_name(id: String) -> String:
	if CHOICE_NAMES.has(id):
		return name_of(CHOICE_NAMES[id])
	return id
