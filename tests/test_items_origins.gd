extends "res://tests/test_case.gd"
## 아이템·출신 데이터 연결: 주문 두루마리(SRD 원문 — 클래스 주문 목록, DC 13·+5, 소모), 마법 입문(재주 주문·긴 휴식 1회 타고난 시전).

const Builder := preload("res://scripts/rules/character_builder.gd")
const Actions := preload("res://scripts/rules/actions.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")


func _pc(spec: Dictionary) -> Node:
	var r := Builder.build(spec)
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func test_spell_scroll_reads_only_class_list_and_is_consumed() -> void:
	var w := make_world(["......"])
	var wiz := _pc(Builder.default_spec("wizard", 1))
	var fighter := _pc(Builder.default_spec("fighter", 1))
	var foe := make_creature({"team": "enemy", "hp_max": 40})
	w["grid"].place(wiz, Vector2i(0, 0))
	w["grid"].place(fighter, Vector2i(1, 0))
	w["grid"].place(foe, Vector2i(4, 0))
	wiz.inventory = {"spell_scroll_magic_missile": 1}
	fighter.inventory = {"spell_scroll_magic_missile": 1}
	var keys: Array = Actions.list_for(w, wiz)["items"]
	assert_true("read_scroll:spell_scroll_magic_missile" in keys, "위저드는 마법 화살 두루마리를 읽는다")
	assert_false("read_scroll:spell_scroll_magic_missile" in Actions.list_for(w, fighter)["items"], "전사는 못 읽는다(클래스 주문 목록)")
	for k: String in wiz.resources.keys():
		if k.begins_with("spell_slot_"):
			wiz.resources[k]["current"] = 0
	wiz.reset_turn()
	var hp: int = foe.hp
	var r: Dictionary = Actions.execute(w, wiz, "read_scroll:spell_scroll_magic_missile", Vector2i(4, 0))
	assert_true(r.get("ok", false), "슬롯 없이 두루마리로 시전 %s" % str(r))
	assert_true(foe.hp < hp, "마법 화살 피해")
	assert_eq(int(wiz.inventory.get("spell_scroll_magic_missile", 0)), 0, "두루마리는 사라진다")
	assert_false(wiz.has_meta("scroll_cast"), "두루마리 DC 설정은 시전 뒤 지운다")


func test_magic_initiate_grants_spells_and_innate_cast() -> void:
	var spec := Builder.default_spec("fighter", 4)
	spec["asi"] = {"4": {"feat": "magic_initiate_wizard"}}  # 재주는 능력치 향상 칸에서(출신 재주 없음 — BG3식)
	spec["magic_initiate_wizard"] = {"cantrips": ["fire_bolt", "light"], "spells": ["magic_missile"]}
	var c := _pc(spec)
	assert_true(c.spells.has("fire_bolt") and c.spells.has("magic_missile"), "재주 주문")
	assert_eq(c.resource("innate_magic_missile"), 1, "1레벨 주문은 긴 휴식마다 1회")
	var w := make_world(["....."])
	var foe := make_creature({"team": "enemy", "hp_max": 40})
	w["grid"].place(c, Vector2i(0, 0))
	w["grid"].place(foe, Vector2i(3, 0))
	c.reset_turn()
	var r: Dictionary = Spellcasting.cast(w, c, "magic_missile", Vector2i(3, 0))
	assert_true(r.get("ok", false), "슬롯 없는 전사가 타고난 시전으로 %s" % str(r))
	assert_eq(c.resource("innate_magic_missile"), 0, "1회 썼다")
	var bad := Builder.default_spec("fighter", 4)
	bad["asi"] = {"4": {"feat": "magic_initiate_wizard"}}
	bad["magic_initiate_wizard"] = {"cantrips": ["sacred_flame"], "spells": []}
	assert_true(Array(Builder.validate(bad)).any(func(e: String) -> bool: return e.contains("sacred_flame")), "다른 목록 주문은 오류")
