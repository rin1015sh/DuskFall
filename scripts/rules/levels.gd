extends RefCounted
## 레벨 성장 표(data/rules/progression.json — SRD 5.2.1 Character Advancement)의 창구.
## 레벨 상한·경험치·숙련 보너스는 여기서만 읽는다(클래스·생성기·성장 코드에 따로 적지 않는다).

const ID := "standard"


static func _table() -> Dictionary:
	return RulesDB.get_entry("progression", ID)


## 게임 레벨 상한(1차 범위 5)
static func level_cap() -> int:
	return int(_table().get("level_cap", 5))


static func _row(level: int) -> Dictionary:
	for r: Dictionary in _table().get("levels", []):
		if int(r["level"]) == level:
			return r
	return {}


## 그 레벨에 필요한 경험치
static func xp_for(level: int) -> int:
	return int(_row(level).get("xp", 0))


## 그 레벨의 숙련 보너스
static func proficiency_bonus(level: int) -> int:
	return int(_row(level).get("proficiency_bonus", 2))


## 경험치 → 레벨(상한까지)
static func level_for(xp: int) -> int:
	var lv := 1
	for r: Dictionary in _table().get("levels", []):
		if xp >= int(r["xp"]):
			lv = maxi(lv, int(r["level"]))
	return mini(lv, level_cap())


## SRD 멀티클래스 시전자 슬롯표(시전 레벨 → 슬롯 레벨별 수).
static func multiclass_slots(caster_level: int) -> Array:
	var t: Dictionary = _table().get("multiclass_slots", {})
	return t.get(str(clampi(caster_level, 1, 20)), [])


# ---------- 경험치 보상 표(BG3 — progression.json, bg3.wiki Experience) ----------

static func _cell(table_key: String, col_key: String, col: String, row_level: int) -> int:
	var t: Dictionary = _table().get(table_key, {})
	var cols: Array = t.get(col_key, [])
	var rows: Array = t.get("rows", [])
	var ci := cols.find(col)
	if ci < 0 or rows.is_empty():
		return 0
	var r: Array = rows[clampi(row_level, 1, rows.size()) - 1]
	return int(r[ci]) if ci < r.size() else 0


## 적 처치 경험치: 보상 레벨(적 레벨과 구역 레벨 중 큰 값, 13 이상은 12) × 보상 종류(zero·civilian·pack·combatant·elite·miniboss·boss)
static func creature_xp(level: int, category: String, area_level: int = 1) -> int:
	return _cell("creature_xp", "categories", category, maxi(level, area_level))


## 퀘스트 단계 경험치(구역 레벨 × 종류 — 예: combat_close_major)
static func quest_step_xp(kind: String, area_level: int) -> int:
	return _cell("quest_step_xp", "kinds", kind, area_level)


## 장소 발견 경험치(활성 파티 평균 레벨 올림 × 크기 small·medium·big)
static func discovery_xp(size: String, party_level: int) -> int:
	return _cell("discovery_xp", "sizes", size, party_level)


## SRD 도전지수 → BG3식 몬스터 레벨(몬스터 데이터 level이 없을 때의 기본값)
static func level_from_cr(cr: float) -> int:
	for r: Dictionary in _table().get("cr_to_level", {}).get("rows", []):
		if cr <= float(r["cr_max"]) + 0.0001:
			return int(r["level"])
	return 12
