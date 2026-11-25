extends "res://tests/test_case.gd"
## 행동 설명(단축 막대 툴팁·아이패드 설명 카드): 데이터에서 레벨·사거리·내성·피해 주사위를 읽는다.

const ActionInfo := preload("res://scenes/ui/action_info.gd")
const UiText := preload("res://scenes/ui/ui_text.gd")


func test_spell_card_lines() -> void:
	UiText.lang = "ko"
	var i := ActionInfo.describe({}, null, "spell:burning_hands", false)
	assert_true(str(i["meta"]).contains("1레벨 주문"), "주문 레벨: " + str(i["meta"]))
	assert_true(str(i["dice"]).contains("민첩 내성"), "내성: " + str(i["dice"]))
	assert_true(str(i["dice"]).contains("3d6 화염"), "피해 주사위(절반 피해 줄은 뺀다): " + str(i["dice"]))
	var fb := ActionInfo.describe({}, null, "spell:fire_bolt", false)
	assert_true(str(fb["meta"]).contains("소마법") and str(fb["meta"]).contains("사거리 18m"), str(fb["meta"]))
	var cw := ActionInfo.describe({}, null, "spell:cure_wounds", false)
	assert_true(str(cw["meta"]).contains("접촉") and str(cw["dice"]).contains("회복 1d8"), str(cw))


func test_tooltip_has_title_and_cost() -> void:
	UiText.lang = "ko"
	var t := ActionInfo.tooltip({}, null, "shove", false)
	assert_true(t.begins_with("밀치기"), t)
	assert_true(t.contains("보너스 행동"), t)
