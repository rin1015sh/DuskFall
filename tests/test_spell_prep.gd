extends "res://tests/test_case.gd"
## 주문 준비·교체·주문서 학습(spell_prep.gd, 룰북 6단계): 긴 휴식 뒤 교체 창(클래스 swap), 전투가 시작되면 닫힘,
## 레인저 1개 교체(빈 칸 채우기는 공짜), 위저드 주문서 안에서만 준비, 두루마리 학습(BG3식: 두루마리 소모 + 레벨 × 50gp),
## 반응 주문 목록 동기화, 주문 암기(짧은 휴식 1개), 의식(탐험 중 슬롯 없이)·의식 숙련, 레벨 업·명세 유지.

const Builder := preload("res://scripts/rules/character_builder.gd")
const SpellPrep := preload("res://scripts/rules/spell_prep.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Actions := preload("res://scripts/rules/actions.gd")


func _pc(class_id: String, lv: int, extra: Dictionary = {}) -> Node:
	var spec := Builder.default_spec(class_id, lv)
	spec.merge(extra, true)
	var r := Builder.build(spec)
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func test_cleric_swaps_all_after_long_rest_until_combat() -> void:
	var w := {}
	var c := _pc("cleric", 3)
	assert_eq(c.prepared.size(), SpellPrep.max_prepared(c), "준비 수만큼 준비")
	assert_eq(c.prep_swaps, -1, "새 캐릭터는 막 쉰 것처럼 전부 바꿀 수 있다")
	var p := SpellPrep.pool(c)
	assert_true(p.size() > c.prepared.size(), "클래스 주문 목록 전체에서 고른다")
	var newer: Array = p.filter(func(s: String) -> bool: return not s in c.prepared).slice(0, 2)
	var list: Array = c.prepared.slice(2) + newer
	assert_true(SpellPrep.set_prepared(w, c, list)["ok"])
	assert_true(c.spells.has(newer[0]) and not c.spells.has(c.prep_base[0]), "시전 목록도 바뀐다")
	assert_true(c.spells.has("sacred_flame"), "소마법은 그대로")
	assert_eq(c.get_meta("spec")["spells"].slice(0, list.size()), list, "명세에 남는다(레벨 업·불러오기)")
	SpellPrep.close_window(c)
	assert_true(SpellPrep.change_blocked(w, c) != "", "전투가 시작되면 닫힌다")
	assert_false(SpellPrep.toggle(w, c, c.prepared[0])["ok"])
	SpellPrep.open_window(c, "long")
	assert_eq(SpellPrep.change_blocked(w, c), "", "긴 휴식 뒤 다시 열린다")


func test_ranger_one_swap_and_free_empty_slot() -> void:
	var w := {}
	var r := _pc("ranger", 2, {"spells": ["cure_wounds"]})
	assert_eq(r.prepared, ["cure_wounds"])
	assert_eq(SpellPrep.max_prepared(r), 3)
	assert_true(SpellPrep.toggle(w, r, "goodberry")["ok"], "빈 칸 채우기는 공짜")
	assert_true(SpellPrep.toggle(w, r, "entangle")["ok"], "빈 칸 채우기는 공짜")
	assert_eq(SpellPrep.swaps_left(r), 1, "레인저: 긴 휴식 뒤 1개")
	var full := _pc("ranger", 2, {"spells": ["cure_wounds", "goodberry", "entangle"]})
	assert_true(SpellPrep.set_prepared(w, full, ["cure_wounds", "goodberry", "ensnaring_strike"])["ok"], "1개 교체")
	assert_eq(SpellPrep.swaps_left(full), 0)
	assert_false(SpellPrep.set_prepared(w, full, ["cure_wounds", "fog_cloud", "ensnaring_strike"])["ok"], "두 번째 교체는 안 된다")
	assert_true(SpellPrep.set_prepared(w, full, ["cure_wounds", "goodberry", "entangle"])["ok"], "되돌리기는 공짜(창이 열릴 때와 비교)")
	assert_false("barkskin" in SpellPrep.pool(full), "슬롯이 없는 레벨은 고를 수 없다")
	assert_false("hunters_mark" in SpellPrep.pool(full), "항상 준비 주문은 목록에 없다")


func test_wizard_spellbook_scroll_learning_and_reactions() -> void:
	var w := {}
	var wz := _pc("wizard", 1, {"spells": ["shield", "sleep", "burning_hands"]})
	wz.inventory = {"gold": 120, "spell_scroll_magic_missile": 1}
	assert_eq(wz.spellbook, ["shield", "sleep", "burning_hands"])
	assert_false("magic_missile" in SpellPrep.pool(wz), "주문서에 없는 주문은 준비할 수 없다")
	assert_true("shield" in wz.known_reactions)
	assert_true(SpellPrep.toggle(w, wz, "shield")["ok"])
	assert_false("shield" in wz.known_reactions, "준비에서 빼면 반응 목록에서도 빠진다")
	assert_eq(SpellPrep.learn_blocked(w, wz, "spell_scroll_cure_wounds"), "두루마리가 없다")
	assert_true(SpellPrep.learn_from_scroll(w, wz, "spell_scroll_magic_missile")["ok"])
	assert_eq(int(wz.inventory["gold"]), 70, "1레벨 × 50gp(배우는 캐릭터의 금화)")
	assert_false(wz.inventory.has("spell_scroll_magic_missile"), "두루마리는 사라진다(BG3식)")
	assert_true("magic_missile" in wz.spellbook and "magic_missile" in SpellPrep.pool(wz))
	assert_true(SpellPrep.toggle(w, wz, "magic_missile")["ok"])
	assert_true(SpellPrep.toggle(w, wz, "shield")["ok"])
	assert_true("shield" in wz.known_reactions)
	# 레벨 업(명세 다시 적용)에도 주문서·준비가 남는다
	var spec: Dictionary = wz.get_meta("spec").duplicate(true)
	spec["level"] = 2
	Builder.apply(wz, spec)
	assert_true("magic_missile" in wz.spellbook and wz.spells.has("magic_missile"), "배운 주문 유지")
	wz.inventory["spell_scroll_magic_missile"] = 1
	assert_eq(SpellPrep.learn_blocked(w, wz, "spell_scroll_magic_missile"), "이미 주문서에 있다")


func test_memorize_spell_short_rest() -> void:
	var w := {}
	var wz := _pc("wizard", 5)
	SpellPrep.close_window(wz)
	SpellPrep.open_window(wz, "short")
	assert_eq(SpellPrep.swaps_left(wz), 1, "주문 암기: 짧은 휴식 뒤 1개")
	var c3 := _pc("cleric", 3)
	SpellPrep.close_window(c3)
	SpellPrep.open_window(c3, "short")
	assert_eq(c3.prep_swaps, 0, "태그가 없으면 짧은 휴식으로 열리지 않는다")


func test_ritual_casting_and_ritual_adept() -> void:
	var w := make_world(["......"])
	var wz := _pc("wizard", 1, {"spells": ["shield", "sleep"], "spellbook": ["detect_magic"]})
	w["grid"].place(wz, Vector2i(0, 0))
	assert_false(wz.spells.has("detect_magic"), "준비하지 않았다")
	var was: bool = EventBus.realtime
	EventBus.realtime = true
	wz.reset_turn()
	assert_true("spell:detect_magic" in Actions.list_for(w, wz, true)["spells"], "의식 숙련: 주문서의 의식 주문이 탐험 단축 막대에")
	var slots: int = wz.resource("spell_slot_1")
	var r: Dictionary = Spellcasting.cast(w, wz, "detect_magic", Vector2i(0, 0))
	assert_true(r.get("ok", false), str(r))
	assert_eq(wz.resource("spell_slot_1"), slots, "탐험 중 의식은 슬롯 없이")
	EventBus.realtime = false
	wz.break_concentration("시험")
	wz.reset_turn()
	assert_eq(Spellcasting.can_cast(w, wz, "detect_magic", Vector2i(0, 0)), "모르는 주문", "전투 중에는 준비한 주문만")
	EventBus.realtime = was


func test_save_restore_keeps_prepared_and_spellbook() -> void:
	var SaveGame := preload("res://scripts/rules/save_game.gd")
	var w := make_world(["....."])
	var wz := _pc("wizard", 1, {"spells": ["shield", "sleep", "burning_hands"]})
	wz.inventory = {"gold": 100, "spell_scroll_magic_missile": 1}
	wz.name = "wz"
	w["grid"].place(wz, Vector2i(0, 0))
	SpellPrep.learn_from_scroll(w, wz, "spell_scroll_magic_missile")
	SpellPrep.set_prepared(w, wz, ["magic_missile", "sleep"])
	SpellPrep.close_window(wz)
	var text := JSON.stringify(SaveGame.snapshot(w))
	SpellPrep.open_window(wz, "long")
	SpellPrep.set_prepared(w, wz, ["shield"])
	wz.spellbook.erase("magic_missile")
	assert_true(SaveGame.restore(w, JSON.parse_string(text)))
	assert_eq(wz.prepared, ["magic_missile", "sleep"], "준비 주문 복원")
	assert_true("magic_missile" in wz.spellbook and wz.spells.has("magic_missile"), "주문서·시전 목록 복원")
	assert_eq(wz.prep_swaps, 0, "교체 창 상태 복원")
	assert_false("shield" in wz.known_reactions, "반응 목록 복원")


## 방출 학자(grants.spellbook_school): 주문서 크기 + 방출학파 2개 + 3레벨 뒤 새 슬롯 레벨마다 1개(5레벨 = +3).
func test_evocation_savant_spellbook_bonus() -> void:
	var wz := _pc("wizard", 5)
	assert_eq(SpellPrep.learn_cost("fireball", wz), 75, "BG3 방출학파: 방출학파 주문 옮겨 적기 절반(25gp × 3)")
	assert_eq(SpellPrep.learn_cost("counterspell", wz), 150, "다른 학파는 50gp × 3")
