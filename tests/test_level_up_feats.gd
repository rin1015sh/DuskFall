extends "res://tests/test_case.gd"
## 레벨 업 재주 고르기(BG3식, changes.md 2026-11-24): 능력치 향상 레벨에서 능력치 +2 또는 일반 재주를 고른다.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Progression := preload("res://scripts/rules/progression.gd")


func test_feat_pick_on_asi_level() -> void:
	var r := Builder.build(Builder.default_spec("fighter", 3))
	var c: Node = own(r["creature"])
	var w := {"xp": 999999}
	assert_eq(Progression.asi_level_for(c, "fighter"), 4)
	var picks: Array = Progression.feat_choices(c, "fighter")
	assert_true(picks.size() > 6, "능력치 +2와 재주들")
	var gwm: Array = picks.filter(func(p: Dictionary) -> bool: return str(p["pick"].get("feat", "")) == "great_weapon_master")
	assert_eq(gwm.size(), 1)
	assert_true(Progression.level_up(w, c, "fighter", {"asi_pick": gwm[0]["pick"]}))
	assert_eq(c.level, 4)
	assert_true(c.feature_data.has("great_weapon_master"), "고른 재주")
	assert_eq(Progression.asi_level_for(c, "fighter"), 0, "5레벨은 향상 없음")


func test_athlete_auto_ability() -> void:
	var r := Builder.build(Builder.default_spec("fighter", 3))
	var c: Node = own(r["creature"])
	var p: Array = Progression.feat_choices(c, "fighter").filter(func(x: Dictionary) -> bool: return str(x["pick"].get("feat", "")) == "athlete")
	assert_eq(p.size(), 1)
	var str_before: int = c.abilities["str"]
	assert_true(Progression.level_up({"xp": 999999}, c, "fighter", {"asi_pick": p[0]["pick"]}))
	assert_true(int(c.abilities["str"]) + int(c.abilities["dex"]) > str_before + int(r["creature"].abilities["dex"]) - 1, "고르는 +1 자동")
