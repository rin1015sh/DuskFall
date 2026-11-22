extends RefCounted
## 테스트 바탕. tests/test_*.gd는 이 파일을 상속하고 test_로 시작하는 메서드를 둔다.
## 실행기는 tests/run_all.gd.

var failures: PackedStringArray = []
## 실행기가 넣어 준다. 오토로드는 tree.root.get_node("RulesDB")처럼 찾는다.
var tree: SceneTree

const CreatureScript := preload("res://scripts/rules/creature.gd")
var _owned: Array[Node] = []


## 테스트용 생물을 만든다. 테스트가 끝나면 실행기가 cleanup()으로 지운다.
func make_creature(values: Dictionary = {}) -> Node:
	var c: Node = CreatureScript.new()
	c.setup(values)
	_owned.append(c)
	return c


## 실행기가 테스트마다 부른다. 같은 시드로 시작해 결과가 늘 같다.
func before_each() -> void:
	Dice.set_seed(12345)


func cleanup() -> void:
	Dice.clear_forced()
	for n in _owned:
		if is_instance_valid(n):
			n.free()
	_owned.clear()


func assert_true(cond: bool, msg: String = "") -> void:
	if not cond:
		_fail("참이어야 한다", msg)


func assert_false(cond: bool, msg: String = "") -> void:
	if cond:
		_fail("거짓이어야 한다", msg)


func assert_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	if not _same(actual, expected):
		_fail("기댓값 %s, 실제 %s" % [var_to_str(expected), var_to_str(actual)], msg)


## 소수 비교(확률 등).
func assert_near(actual: float, expected: float, tolerance: float = 0.0001, msg: String = "") -> void:
	if absf(actual - expected) > tolerance:
		_fail("기댓값 %s ± %s, 실제 %s" % [expected, tolerance, actual], msg)


## 오류 목록에 text를 포함한 줄이 있는지.
func assert_any_contains(lines: PackedStringArray, text: String, msg: String = "") -> void:
	for line in lines:
		if line.contains(text):
			return
	_fail("'%s'를 포함한 줄이 없다: %s" % [text, str(lines)], msg)


func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		return float(a) == float(b)
	return typeof(a) == typeof(b) and a == b


func _fail(what: String, msg: String) -> void:
	failures.append(what if msg == "" else "%s — %s" % [msg, what])
