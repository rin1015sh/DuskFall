extends SceneTree
## 데이터 검증 명령. 실행: godot --headless --path . -s res://tools/validate_data.gd
## 실패가 있으면 종료 코드 1.

const DataValidator := preload("res://tools/data_validator.gd")


func _initialize() -> void:
	var v := DataValidator.new()
	var ok := v.run()
	for line in v.info:
		print("[정보] ", line)
	for line in v.warnings:
		print("[경고] ", line)
	for line in v.errors:
		printerr("[오류] ", line)
	print("데이터 검증 %s — 오류 %d, 경고 %d" % ["통과" if ok else "실패", v.errors.size(), v.warnings.size()])
	quit(0 if ok else 1)
