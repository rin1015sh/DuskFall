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
}


static func t(key: String) -> String:
	return TEXT.get(key, {}).get(lang, key)


## 데이터의 {"ko", "en"} 이름. 한국어가 비어 있으면 영어.
static func name_of(names: Dictionary) -> String:
	var v: Variant = names.get(lang)
	return v if v != null and v != "" else str(names.get("en", ""))
