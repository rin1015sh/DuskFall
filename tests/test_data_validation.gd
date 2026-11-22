extends "res://tests/test_case.gd"
## 저장소의 실제 데이터가 검증을 통과하는지, 그리고 spell 스키마가 틀린 주문을 잡는지.

const DataValidator := preload("res://tools/data_validator.gd")
const SchemaValidator := preload("res://scripts/rules/schema_validator.gd")


func test_repository_data_passes() -> void:
	var v := DataValidator.new()
	var ok := v.run()
	assert_true(ok, "데이터 검증 오류: %s" % str(v.errors))
	assert_true(v.entries.get("spell", {}).size() > 0, "주문이 읽혔다")


func test_spell_schema_rejects_bad_spell() -> void:
	var schema: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/schema/spell.schema.json"))
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/spells.json"))
	var spell: Dictionary = data["spells"][0].duplicate(true)
	spell["level"] = 12
	spell["effects"] = {"apply": [{"type": "explode"}]}
	spell["range"] = {"type": "tiles"}
	data["spells"] = [spell]
	var e := SchemaValidator.new().validate(data, schema)
	assert_any_contains(e, "최댓값", "레벨 0~9")
	assert_any_contains(e, "\"explode\"", "룰북 8단계 목록 밖 효과 종류")
	assert_any_contains(e, "oneOf", "tiles 사거리에 칸 수 없음")
