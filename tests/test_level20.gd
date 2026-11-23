extends "res://tests/test_case.gd"
## 레벨 상한 20(1단계 — SRD 클래스 표): 슬롯·준비 수·소마법·자원·레벨표 주사위·능력치 향상 레벨.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Actions := preload("res://scripts/rules/actions.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const SpellPrep := preload("res://scripts/rules/spell_prep.gd")


func _pc(cid: String, lv: int) -> Node:
	var r := Builder.build(Builder.default_spec(cid, lv))
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func test_tables_at_high_levels() -> void:
	var wz := _pc("wizard", 20)
	var slots: Array = []
	for i in range(1, 10):
		slots.append(wz.resource("spell_slot_%d" % i))
	assert_eq(slots, [4, 3, 3, 3, 3, 2, 2, 1, 1], "위저드 20레벨 슬롯")
	assert_eq(SpellPrep.max_prepared(wz), 25)
	assert_eq(wz.proficiency_bonus, 6)
	assert_eq(Actions.sneak_dice(_pc("rogue", 19)), 10, "급소 공격 10d6")
	var monk := _pc("monk", 17)
	assert_eq(Combat.martial_arts_die(monk), "1d12")
	assert_eq(monk.resource("focus"), 17)
	assert_eq(monk.speed_tiles, 6 + 5, "맨몸 이동 +25피트(14레벨~)")
	var bar := _pc("barbarian", 16)
	bar.apply_condition("raging", 10, bar)
	assert_eq(Resolver.rage_bonus(bar), 4, "분노 피해 +4")
	assert_eq(bar.resource("rage"), 5)
	var wl := _pc("warlock", 11)
	assert_eq(wl.resource("spell_slot_5"), 3, "워락 11레벨: 5레벨 계약 슬롯 3")
	assert_eq(_pc("fighter", 17).resource("action_surge"), 2)
	assert_eq(_pc("paladin", 20).resource("lay_on_hands"), 100)
	assert_eq(_pc("cleric", 18).resource("channel_divinity"), 4)
	assert_true(_pc("warlock", 18).feature_data.has("eldritch_invocations_18"), "영창 18레벨 추가")
