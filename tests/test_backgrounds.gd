extends "res://tests/test_case.gd"
## 배경(룰북 6단계, BG3 구성 12개 — 2026-11-24): 기능 숙련 2(BG3 값), 출신 재주 없음, 모든 클래스와 조합 가능.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Goals := preload("res://scripts/rules/goals.gd")

const BG3 := {"acolyte": ["insight", "religion"], "charlatan": ["deception", "sleight_of_hand"], "criminal": ["deception", "stealth"],
	"entertainer": ["acrobatics", "performance"], "village_champion": ["animal_handling", "survival"], "guild_crafter": ["insight", "persuasion"],
	"noble": ["history", "persuasion"], "outlander": ["athletics", "survival"], "sage": ["arcana", "history"],
	"soldier": ["athletics", "intimidation"], "urchin": ["sleight_of_hand", "stealth"], "haunted": ["medicine", "intimidation"]}


func test_twelve_backgrounds_with_bg3_skills() -> void:
	assert_eq(RulesDB.entries("background").size(), 12)
	for id: String in BG3:
		var b := RulesDB.get_entry("background", id)
		assert_false(b.is_empty(), id)
		assert_eq(Array(b["skills"]), BG3[id], "%s 기능 숙련" % id)
		assert_false(b.has("feat"), "%s 출신 재주 없음(BG3)" % id)
		assert_true(b["inspiration_goals"].size() >= 3, "%s 영감 목표 3개 이상" % id)


func test_every_background_builds_with_every_class() -> void:
	for id: String in BG3:
		for cls: String in ["fighter", "rogue", "wizard", "cleric", "bard", "ranger"]:
			var spec := Builder.default_spec(cls, 1)
			spec["background"] = id
			var r := Builder.build(spec)
			assert_eq(r["errors"].size(), 0, "%s + %s: %s" % [id, cls, str(r["errors"])])
			if r["errors"].is_empty():
				var c: Node = own(r["creature"])
				for sk: String in BG3[id]:
					assert_true(c.skill_bonuses.has(sk), "%s + %s: %s 숙련" % [id, cls, sk])


func test_new_background_goal_gives_inspiration() -> void:
	var c := make_creature({"team": "party"})
	c.background_id = "noble"
	var w := {"party": [c]}
	assert_eq(Goals.complete(w, "use_family_name"), "inspiration")
	assert_eq(int(w["inspiration"]), 1)
