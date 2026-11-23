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
