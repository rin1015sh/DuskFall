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
