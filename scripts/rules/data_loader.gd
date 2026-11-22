extends RefCounted
## data/ 아래 JSON을 읽고 스키마를 검사해 종류·ID별로 모은다.
## RulesDB(게임 시작)와 tools/data_validator.gd(검증)가 같이 쓴다.
##
## 파일 규칙: 최상위에 "schema": "<kind>_v<n>"를 두고, data/schema/<kind>.schema.json으로 검사한다.
## 항목은 최상위 자체("id"가 있을 때)이거나 최상위 배열 안의 "id"를 가진 객체다.

const SchemaValidator := preload("res://scripts/rules/schema_validator.gd")

const SCHEMA_DIR_NAME := "schema"

var errors := PackedStringArray()
## kind → { id → {"entry": Dictionary, "file": String} }
var entries: Dictionary = {}
var files_loaded := 0

var _schemas: Dictionary = {}


func load_dir(data_dir: String) -> bool:
	errors.clear()
	entries.clear()
	files_loaded = 0
	var schema_dir := data_dir.path_join(SCHEMA_DIR_NAME)
	for path in list_files(data_dir, ["json"]):
		if path.begins_with(schema_dir + "/"):
			continue
		if _load_file(path, schema_dir):
			files_loaded += 1
	return errors.is_empty()


func _load_file(path: String, schema_dir: String) -> bool:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		errors.append("%s:%d: JSON 문법 오류 — %s" % [path, json.get_error_line(), json.get_error_message()])
		return false
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY or not data.has("schema"):
		errors.append("%s: 최상위에 \"schema\": \"<kind>_v<n>\"가 없다" % path)
		return false
	var m := RegEx.create_from_string("^([a-z][a-z0-9_]*)_v[0-9]+$").search(str(data["schema"]))
	if m == null:
		errors.append("%s: schema 값 '%s'가 <kind>_v<n> 모양이 아니다" % [path, data["schema"]])
		return false
	var kind := m.get_string(1)
	var schema := _schema(schema_dir, kind)
	if schema.is_empty():
		errors.append("%s: 스키마 파일 %s/%s.schema.json이 없거나 읽을 수 없다" % [path, schema_dir, kind])
		return false
	for e in SchemaValidator.new().validate(data, schema):
		errors.append("%s: %s" % [path, e])
	_collect(kind, data, path)
	return true


func _schema(schema_dir: String, kind: String) -> Dictionary:
	if not _schemas.has(kind):
		var p := "%s/%s.schema.json" % [schema_dir, kind]
		var s: Variant = JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else null
		_schemas[kind] = s if typeof(s) == TYPE_DICTIONARY else {}
	return _schemas[kind]


func _collect(kind: String, data: Dictionary, path: String) -> void:
	var items: Array = []
	if data.has("id"):
		items.append(data)
	for key: String in data.keys():
		if typeof(data[key]) == TYPE_ARRAY:
			for item: Variant in data[key]:
				if typeof(item) == TYPE_DICTIONARY and item.has("id"):
					items.append(item)
	if not entries.has(kind):
		entries[kind] = {}
	for item: Dictionary in items:
		var id := str(item["id"])
		if entries[kind].has(id):
			errors.append("%s: %s ID '%s'가 겹친다(먼저 나온 곳 %s)" % [path, kind, id, entries[kind][id]["file"]])
		else:
			entries[kind][id] = {"entry": item, "file": path}


static func list_files(dir: String, exts: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for f in da.get_files():
		if exts.has(f.get_extension().to_lower()):
			out.append(dir.path_join(f))
	for d in da.get_directories():
		if d.begins_with("."):
			continue
		out.append_array(list_files(dir.path_join(d), exts))
	out.sort()
	return out
