extends SceneTree
## 헤드리스 테스트 실행기. 실행: godot --headless --path . -s res://tests/run_all.gd
## tests/ 아래 test_*.gd를 모두 찾아 test_로 시작하는 메서드를 차례로 실행한다.
## 실패가 있으면 종료 코드 1. 인자 --filter=<글자>로 파일·메서드 이름을 골라 돌릴 수 있다.

const TESTS_DIR := "res://tests"


## 테스트 중에 난 스크립트 오류를 센다. 오류로 멈춘 테스트도 실패로 잡기 위해서다.
class ErrorCounter extends Logger:
	var count := 0
	var last := ""

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		count += 1
		last = "%s (%s:%d %s)" % [rationale if rationale != "" else code, file, line, function]

	func _log_message(_message: String, _error: bool) -> void:
		pass


var _started := false


func _process(_delta: float) -> bool:
	# 오토로드가 루트에 붙은 뒤(첫 프레임)에 실행한다.
	if _started:
		return false
	_started = true
	quit(_run_all())
	return true


func _run_all() -> int:
	var filter := ""
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--filter="):
			filter = arg.trim_prefix("--filter=")
	var errors := ErrorCounter.new()
	OS.add_logger(errors)
	var files := _find_tests(TESTS_DIR)
	var passed := 0
	var failed := 0
	for path in files:
		var script: Variant = load(path)
		if script == null or not script.can_instantiate():
			printerr("[실패] %s: 불러올 수 없다(문법 오류?)" % path)
			failed += 1
			continue
		for m: Dictionary in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			if filter != "" and not (path.contains(filter) or name.contains(filter)):
				continue
			var t: Object = script.new()
			t.tree = self
			if t.has_method("before_each"):
				t.before_each()
			var errors_before := errors.count
			t.call(name)
			if t.has_method("cleanup"):
				t.cleanup()
			if errors.count > errors_before:
				t.failures.append("스크립트 오류 %d건: %s" % [errors.count - errors_before, errors.last])
			if t.failures.is_empty():
				passed += 1
			else:
				failed += 1
				printerr("[실패] %s :: %s" % [path.get_file(), name])
				for f in t.failures:
					printerr("    ", f)
	OS.remove_logger(errors)
	print("테스트 %d개 — 통과 %d, 실패 %d" % [passed + failed, passed, failed])
	return 0 if failed == 0 else 1


func _find_tests(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for f in da.get_files():
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
			out.append(dir.path_join(f))
	for d in da.get_directories():
		out.append_array(_find_tests(dir.path_join(d)))
	out.sort()
	return out
