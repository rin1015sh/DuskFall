extends RefCounted
## JSON Schema 일부를 검사한다. GDScript에는 스키마 검사기가 없어 필요한 만큼만 직접 구현했다.
##
## 지원 키워드: type, enum, const, required, properties, additionalProperties,
## patternProperties, items, minItems, maxItems, uniqueItems, minimum, maximum,
## minLength, pattern, oneOf, anyOf, allOf, $ref(같은 파일 안 "#/$defs/..."만).
## 모르는 키워드는 오류로 본다(스키마 오타를 잡으려고).
##
## 쓰는 법: var errors := SchemaValidator.new().validate(data, schema)
## 오류는 "경로: 내용" 문자열 배열이다. 빈 배열이면 통과.

const _KNOWN := [
	"$schema", "$id", "$defs", "$comment", "title", "description",
	"type", "enum", "const", "required", "properties", "additionalProperties",
	"patternProperties", "items", "minItems", "maxItems", "uniqueItems",
	"minimum", "maximum", "minLength", "pattern", "oneOf", "anyOf", "allOf", "$ref",
]

var _root: Dictionary = {}
var _regex_cache: Dictionary = {}


func validate(data: Variant, schema: Dictionary) -> PackedStringArray:
	_root = schema
	var errors := PackedStringArray()
	_check(data, schema, "$", errors)
	return errors


func _check(value: Variant, schema: Variant, path: String, errors: PackedStringArray) -> void:
	if typeof(schema) == TYPE_BOOL:
		if not schema:
			errors.append("%s: 허용되지 않는 값" % path)
		return
	if typeof(schema) != TYPE_DICTIONARY:
		errors.append("%s: 스키마가 객체가 아니다" % path)
		return
	for key: String in schema.keys():
		if not _KNOWN.has(key):
			errors.append("%s: 지원하지 않는 스키마 키워드 '%s'" % [path, key])

	if schema.has("$ref"):
		var target: Variant = _resolve_ref(schema["$ref"])
		if target == null:
			errors.append("%s: 찾을 수 없는 $ref '%s'" % [path, schema["$ref"]])
		else:
			_check(value, target, path, errors)

	if schema.has("type") and not _type_ok(value, schema["type"]):
		errors.append("%s: 타입이 %s여야 하는데 %s" % [path, str(schema["type"]), _type_name(value)])
		return  # 타입이 틀리면 나머지 검사는 의미가 없다.

	if schema.has("const") and not _equal(value, schema["const"]):
		errors.append("%s: 값이 %s여야 한다" % [path, JSON.stringify(schema["const"])])
	if schema.has("enum"):
		var found := false
		for option: Variant in schema["enum"]:
			if _equal(value, option):
				found = true
				break
		if not found:
			errors.append("%s: %s는 허용 목록 %s에 없다" % [path, JSON.stringify(value), JSON.stringify(schema["enum"])])

	match typeof(value):
		TYPE_DICTIONARY:
			_check_object(value, schema, path, errors)
		TYPE_ARRAY:
			_check_array(value, schema, path, errors)
		TYPE_STRING:
			_check_string(value, schema, path, errors)
		TYPE_INT, TYPE_FLOAT:
			if schema.has("minimum") and value < schema["minimum"]:
				errors.append("%s: %s < 최솟값 %s" % [path, value, schema["minimum"]])
			if schema.has("maximum") and value > schema["maximum"]:
				errors.append("%s: %s > 최댓값 %s" % [path, value, schema["maximum"]])

	if schema.has("allOf"):
		for sub: Variant in schema["allOf"]:
			_check(value, sub, path, errors)
	if schema.has("anyOf"):
		if _count_matches(value, schema["anyOf"], path) == 0:
			errors.append("%s: anyOf 중 맞는 것이 없다" % path)
	if schema.has("oneOf"):
		var n := _count_matches(value, schema["oneOf"], path)
		if n != 1:
			errors.append("%s: oneOf 중 정확히 하나가 맞아야 하는데 %d개" % [path, n])


func _check_object(obj: Dictionary, schema: Dictionary, path: String, errors: PackedStringArray) -> void:
	for key: String in schema.get("required", []):
		if not obj.has(key):
			errors.append("%s: 필수 키 '%s'가 없다" % [path, key])
	var props: Dictionary = schema.get("properties", {})
	var pattern_props: Dictionary = schema.get("patternProperties", {})
	for key: Variant in obj.keys():
		var sub_path := "%s.%s" % [path, key]
		var matched := false
		if props.has(key):
			matched = true
			_check(obj[key], props[key], sub_path, errors)
		for pattern: String in pattern_props.keys():
			if _regex(pattern).search(str(key)) != null:
				matched = true
				_check(obj[key], pattern_props[pattern], sub_path, errors)
		if not matched and schema.has("additionalProperties"):
			var extra: Variant = schema["additionalProperties"]
			if typeof(extra) == TYPE_BOOL and not extra:
				errors.append("%s: 정의되지 않은 키 '%s'" % [path, key])
			elif typeof(extra) == TYPE_DICTIONARY:
				_check(obj[key], extra, sub_path, errors)


func _check_array(arr: Array, schema: Dictionary, path: String, errors: PackedStringArray) -> void:
	if schema.has("minItems") and arr.size() < schema["minItems"]:
		errors.append("%s: 항목이 %d개 이상이어야 한다" % [path, schema["minItems"]])
	if schema.has("maxItems") and arr.size() > schema["maxItems"]:
		errors.append("%s: 항목이 %d개 이하여야 한다" % [path, schema["maxItems"]])
	if schema.get("uniqueItems", false):
		for i in arr.size():
			for j in range(i + 1, arr.size()):
				if _equal(arr[i], arr[j]):
					errors.append("%s: %d번과 %d번 항목이 같다" % [path, i, j])
	if schema.has("items"):
		for i in arr.size():
			_check(arr[i], schema["items"], "%s[%d]" % [path, i], errors)


func _check_string(s: String, schema: Dictionary, path: String, errors: PackedStringArray) -> void:
	if schema.has("minLength") and s.length() < schema["minLength"]:
		errors.append("%s: 문자열이 %d자 이상이어야 한다" % [path, schema["minLength"]])
	if schema.has("pattern") and _regex(schema["pattern"]).search(s) == null:
		errors.append("%s: '%s'가 패턴 %s에 맞지 않는다" % [path, s, schema["pattern"]])


func _count_matches(value: Variant, options: Array, path: String) -> int:
	var n := 0
	for sub: Variant in options:
		var tmp := PackedStringArray()
		_check(value, sub, path, tmp)
		if tmp.is_empty():
			n += 1
	return n


func _resolve_ref(ref: String) -> Variant:
	if not ref.begins_with("#/"):
		return null
	var node: Variant = _root
	for part in ref.substr(2).split("/"):
		if typeof(node) != TYPE_DICTIONARY or not node.has(part):
			return null
		node = node[part]
	return node


func _type_ok(value: Variant, expected: Variant) -> bool:
	if typeof(expected) == TYPE_ARRAY:
		for t: String in expected:
			if _type_ok(value, t):
				return true
		return false
	match expected:
		"null":
			return value == null
		"boolean":
			return typeof(value) == TYPE_BOOL
		"string":
			return typeof(value) == TYPE_STRING
		"object":
			return typeof(value) == TYPE_DICTIONARY
		"array":
			return typeof(value) == TYPE_ARRAY
		"number":
			return typeof(value) in [TYPE_INT, TYPE_FLOAT]
		"integer":
			# Godot의 JSON은 숫자를 모두 float로 읽는다. 소수점 아래가 0이면 정수로 본다.
			return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and value == floorf(value))
	return false


func _type_name(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "boolean"
		TYPE_STRING:
			return "string"
		TYPE_DICTIONARY:
			return "object"
		TYPE_ARRAY:
			return "array"
		TYPE_INT, TYPE_FLOAT:
			return "number"
	return type_string(typeof(value))


func _equal(a: Variant, b: Variant) -> bool:
	# 1과 1.0을 같게 본다(JSON 숫자).
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		return float(a) == float(b)
	if typeof(a) != typeof(b):
		return false
	return a == b


func _regex(pattern: String) -> RegEx:
	if not _regex_cache.has(pattern):
		_regex_cache[pattern] = RegEx.create_from_string(pattern)
	return _regex_cache[pattern]
