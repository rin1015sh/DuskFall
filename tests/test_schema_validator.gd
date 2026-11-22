extends "res://tests/test_case.gd"
## tools/schema_validator.gd가 지원 키워드를 제대로 검사하는지.

const SchemaValidator := preload("res://scripts/rules/schema_validator.gd")


func _errs(data: Variant, schema: Dictionary) -> PackedStringArray:
	return SchemaValidator.new().validate(data, schema)


func test_type() -> void:
	assert_eq(_errs("a", {"type": "string"}).size(), 0)
	assert_any_contains(_errs(1, {"type": "string"}), "타입")
	assert_eq(_errs(3.0, {"type": "integer"}).size(), 0, "JSON 숫자 3.0은 정수")
	assert_any_contains(_errs(3.5, {"type": "integer"}), "타입")
	assert_eq(_errs(null, {"type": ["string", "null"]}).size(), 0)


func test_required_and_additional_properties() -> void:
	var schema := {"type": "object", "required": ["id"], "additionalProperties": false,
		"properties": {"id": {"type": "string"}}}
	assert_eq(_errs({"id": "x"}, schema).size(), 0)
	assert_any_contains(_errs({}, schema), "필수 키 'id'")
	assert_any_contains(_errs({"id": "x", "oops": 1}, schema), "정의되지 않은 키 'oops'")


func test_enum_const_pattern() -> void:
	assert_eq(_errs("fire", {"enum": ["fire", "cold"]}).size(), 0)
	assert_any_contains(_errs("mud", {"enum": ["fire", "cold"]}), "허용 목록")
	assert_eq(_errs(1.0, {"const": 1}).size(), 0, "1.0 == 1")
	assert_eq(_errs("2d6+1", {"type": "string", "pattern": "^[0-9]+d[0-9]+([+-][0-9]+)?$"}).size(), 0)
	assert_any_contains(_errs("2x6", {"type": "string", "pattern": "^[0-9]+d[0-9]+$"}), "패턴")


func test_items_and_ref() -> void:
	var schema := {"type": "array", "items": {"$ref": "#/$defs/n"},
		"$defs": {"n": {"type": "integer", "minimum": 0}}}
	assert_eq(_errs([0, 1, 2], schema).size(), 0)
	var e := _errs([0, -1], schema)
	assert_any_contains(e, "$[1]")
	assert_any_contains(_errs([1], {"items": {"$ref": "#/$defs/none"}}), "찾을 수 없는 $ref")


func test_one_of_any_of() -> void:
	var one := {"oneOf": [{"type": "null"}, {"type": "object"}]}
	assert_eq(_errs(null, one).size(), 0)
	assert_eq(_errs({}, one).size(), 0)
	assert_any_contains(_errs(1, one), "oneOf")
	assert_any_contains(_errs(1, {"anyOf": [{"type": "string"}]}), "anyOf")


func test_unknown_keyword_is_error() -> void:
	assert_any_contains(_errs(1, {"tpye": "string"}), "지원하지 않는 스키마 키워드")
