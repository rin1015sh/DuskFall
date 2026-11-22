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
	"regroup": {"ko": "모이기", "en": "Regroup"},
	"level_up": {"ko": "레벨 업 → %d", "en": "Level Up → %d"},
	"explore_status": {"ko": "%s (%d레벨, 경험치 %d) — 영감 %d · 골드 %d · 도둑 도구 %d · 해체 도구 %d", "en": "%s (Lv %d, XP %d) — Inspiration %d · Gold %d · Thieves' tools %d · Disarm kits %d"},
	"close": {"ko": "닫기", "en": "Close"},
	"use_inspiration": {"ko": "실패하면 영감으로 다시 굴림 (영감 %d)", "en": "Reroll failures with Inspiration (%d)"},
	"roll_result": {"ko": "d20 %d → %d (DC %d) %s", "en": "d20 %d → %d (DC %d) %s"},
	"success": {"ko": "성공", "en": "Success"},
	"failure": {"ko": "실패", "en": "Failure"},
}


static func t(key: String) -> String:
	return TEXT.get(key, {}).get(lang, key)


## 데이터의 {"ko", "en"} 이름. 한국어가 비어 있으면 영어.
static func name_of(names: Dictionary) -> String:
	var v: Variant = names.get(lang)
	return v if v != null and v != "" else str(names.get("en", ""))
