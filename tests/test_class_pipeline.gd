extends "res://tests/test_case.gd"
## 콘텐츠 파이프라인 안전망: 데이터에 있는 모든 클래스(새 클래스 자동 포함)를 레벨 1~상한까지 추천 빌드로 만들어 본다.
## 클래스 데이터만 추가하면 이 테스트가 바로 그 클래스를 점검한다(코드에 클래스 목록이 없어야 한다 — 룰북 1단계 '클래스 확장 원칙').

const Builder := preload("res://scripts/rules/character_builder.gd")
const Progression := preload("res://scripts/rules/progression.gd")


func _db() -> Node:
	return tree.root.get_node("RulesDB")


func test_every_class_builds_at_every_level() -> void:
	var ids: Array = _db().ids("class")
	assert_true(ids.size() >= 4, "클래스 %d개" % ids.size())
	for cid: String in ids:
		for lv in range(1, Progression.level_cap() + 1):
			var spec := Builder.default_spec(cid, lv)
			assert_eq(spec.get("class", ""), cid, "%s 추천 빌드가 있다" % cid)
			var r := Builder.build(spec)
			assert_eq(r["errors"].size(), 0, "%s %d레벨 생성 오류 %s" % [cid, lv, str(r["errors"])])
			var c: Node = r["creature"]
			if c == null:
				continue
			own(c)
			assert_eq(c.level, lv, "%s 레벨" % cid)
			assert_true(c.hp_max > 0, "%s %d레벨 HP" % [cid, lv])
			assert_true(c.ac() >= 10, "%s %d레벨 AC" % [cid, lv])


## 클래스 기능 데이터의 script는 모두 있고(검증기도 본다) 기능 ID가 클래스 안에서 겹치지 않는다
func test_class_features_are_well_formed() -> void:
	for cid: String in _db().ids("class"):
		var cls: Dictionary = _db().get_entry("class", cid)
		var seen := {}
		var feats: Array = cls.get("features", []).duplicate()
		for sc: Dictionary in cls.get("subclasses", []):
			feats.append_array(sc.get("features", []))
		for f: Dictionary in feats:
			var fid := str(f.get("id", ""))
			assert_false(seen.has(fid), "%s 기능 ID '%s' 중복" % [cid, fid])
			seen[fid] = true
			if f.has("script"):
				assert_true(ResourceLoader.exists("res://scripts/rules/effects/%s.gd" % f["script"]), "%s 기능 %s 스크립트" % [cid, fid])


## 데이터만으로 만든 클래스가 코드 수정 없이 동작한다: 추천 빌드·능력 태그·grants·고르는 기능(option)·상시 설정·반응·단축 막대 기능
func test_data_only_class_works_without_code() -> void:
	var db: Node = _db()
	var cls := {
		"id": "test_warden", "name": {"ko": "시험 파수꾼", "en": "Test Warden"}, "hit_die": 10, "saves": ["str", "con"],
		"skills": {"choose": 2, "from": ["athletics", "perception", "survival"]}, "weapon_training": ["simple"], "armor_training": ["light"],
		"asi_levels": [4], "ai_role": "ranged", "color": "#40c080",
		"features": [
			{"id": "warden_stance", "name": {"ko": "자세", "en": "Stance"}, "level": 1, "choices": ["guard", "hunt"], "choice_kind": "option",
				"choice_grants": {"guard": {"armor_training": ["heavy"]}, "hunt": {"caps": ["ranged_weapon_attack_bonus"]}}},
			{"id": "warden_luck", "name": {"ko": "행운", "en": "Luck"}, "level": 1, "caps": ["reroll_natural_1"],
				"toggle": {"values": [{"id": "on", "name": {"ko": "켬", "en": "On"}}, {"id": "off", "name": {"ko": "끔", "en": "Off"}}]}},
			{"id": "warden_strikes", "name": {"ko": "연타", "en": "Strikes"}, "level": 2, "grants": {"attacks_per_action": 2, "crit_threshold": 19}},
			{"id": "warden_parry", "name": {"ko": "받아넘기기", "en": "Parry"}, "level": 1, "kind": "reaction", "hook": "on_hit", "script": "uncanny_dodge"},
			{"id": "warden_breath", "name": {"ko": "숨 고르기", "en": "Breather"}, "level": 1, "kind": "bonus_action", "resource": "warden_breath",
				"script": "second_wind", "glyph": "breath", "icon": "statuses/refreshed.webp", "explore": true, "ai": {"when": "hp_below_half"}}],
		"resources": [{"id": "warden_breath", "max": 1, "recharge": "short"}],
		"subclasses": [],
		"default_build": {"species": "human", "background": "soldier", "scores": {"str": 15, "dex": 13, "con": 14, "int": 8, "wis": 12, "cha": 10},
			"bonus": {"str": 2, "con": 1}, "skills": ["athletics", "perception"], "warden_stance": "hunt", "armor": "leather_armor",
			"weapons": {"melee": {"main": "spear", "off": ""}, "ranged": {"main": "shortbow"}}}}
	db._entries["class"]["test_warden"] = cls
	var r := Builder.build(Builder.default_spec("test_warden", 2))
	db._entries["class"].erase("test_warden")
	assert_eq(r["errors"].size(), 0, "데이터만으로 생성 %s" % str(r["errors"]))
	var c: Node = own(r["creature"])
	assert_true(c.has_cap("reroll_natural_1"), "기능 caps")
	assert_true(c.has_cap("ranged_weapon_attack_bonus"), "고른 option의 grants.caps(hunt)")
	assert_eq(c.attacks_per_action, 2, "grants.attacks_per_action")
	assert_eq(c.crit_threshold, 19, "grants.crit_threshold")
	assert_true("warden_parry" in c.known_reactions, "반응 기능은 반응 목록에")
	db._entries["class"]["test_warden"] = cls
	var Actions := load("res://scripts/rules/actions.gd")
	assert_true(Actions.passives(c).any(func(p: Dictionary) -> bool: return p["id"] == "warden_luck"), "상시 발동 탭(toggle)")
	var d: Dictionary = Actions.def_of("feature:warden_breath")
	assert_true(bool(d["explore"]) and str(d["icon"]).ends_with("refreshed.webp"), "단축 막대 기능 데이터(explore·icon)")
	db._entries["class"].erase("test_warden")
