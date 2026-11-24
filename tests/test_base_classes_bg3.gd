extends "res://tests/test_case.gd"
## 기본 클래스 기능 BG3 개편(changes.md 2026-11-24) — 클래스마다 더한다.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Features := preload("res://scripts/rules/features.gd")


func _pc(cls: String, lv: int, extra: Dictionary = {}) -> Node:
	var spec := Builder.default_spec(cls, lv)
	spec.merge(extra, true)
	var r := Builder.build(spec)
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func test_fighter() -> void:
	var f := _pc("fighter", 5)
	assert_false(f.feature_data.has("tactical_mind") or f.feature_data.has("tactical_shift"), "전술적 판단·이동 없음")


func test_bard() -> void:
	var b := _pc("bard", 2)
	assert_eq(b.resources["bardic_inspiration"]["max"], 3, "영감 3회")
	assert_eq(int(b.skill_bonuses["persuasion"]), b.proficiency_bonus, "전문화는 3레벨부터")
	var b3 := _pc("bard", 3)
	assert_eq(int(b3.skill_bonuses["persuasion"]), b3.proficiency_bonus * 2)
	var w := make_world(["...."])
	w["grid"].place(b, Vector2i(0, 0))
	w["party"] = [b]
	b.hp = 1
	b.reset_turn()
	var r: Dictionary = Features.use(w, b, "song_of_rest")
	assert_true(r.get("ok", false), str(r))
	assert_eq(b.resource("song_of_rest"), 0)
