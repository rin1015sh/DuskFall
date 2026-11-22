extends "res://tests/test_case.gd"
## 0단계 기반: 오토로드 등록, 훅 목록.


func test_autoloads_registered() -> void:
	for n in ["RulesDB", "Dice", "EventBus"]:
		assert_true(tree.root.has_node(n), "오토로드 %s" % n)


func test_event_bus_declares_every_hook_as_signal() -> void:
	var bus: Node = tree.root.get_node("EventBus")
	var names: PackedStringArray = bus.hook_names()
	# 룰북 8단계 이벤트 훅 표: 21행, '·'로 묶인 것을 풀면 25개.
	assert_eq(names.size(), 25, "훅 개수")
	for n in names:
		assert_true(bus.has_signal(n), "시그널 %s" % n)


func test_rules_db_empty_lookup() -> void:
	var db: Node = tree.root.get_node("RulesDB")
	assert_eq(db.get_entry("spell", "no_such_spell"), {}, "없는 항목은 빈 Dictionary")
