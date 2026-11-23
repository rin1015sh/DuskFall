extends "res://tests/test_case.gd"
## 콘텐츠 자동 점검(새 콘텐츠 자동 포함): 포함된(included) 주문을 모두 시험 장면에서 실제로 시전해 본다.
## 실패해도 되는 것: 조건이 안 맞아 시전이 거절됨(can_cast 이유). 안 되는 것: 스크립트 오류.
## 오류가 나면 어느 주문인지 이름으로 알려 준다(주문마다 오류를 따로 센다).

const Builder := preload("res://scripts/rules/character_builder.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")


class SpellErrors extends Logger:
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


func _db() -> Node:
	return tree.root.get_node("RulesDB")


## 시전자(위저드 5레벨 + 슬롯 넉넉히), 아군 1, 적 2(사람형·언데드), 시체 1을 놓은 작은 전장
func _arena() -> Dictionary:
	var w := make_world(["..........", "..........", "..........", ".........."])
	var c: Node = own(Builder.build(Builder.default_spec("wizard", 5))["creature"])
	for lv in range(1, 10):
		c.resources["spell_slot_%d" % lv] = {"current": 9, "max": 9, "recharge": "long"}
	var ally := make_creature({"team": "party", "hp_max": 30})
	ally.hp = 10
	var foe := make_creature({"team": "enemy", "hp_max": 60})
	var undead := make_creature({"team": "enemy", "hp_max": 40})
	undead.creature_type = "undead"
	w["grid"].place(c, Vector2i(2, 1))
	w["grid"].place(ally, Vector2i(3, 1))
	w["grid"].place(foe, Vector2i(6, 1))
	w["grid"].place(undead, Vector2i(7, 2))
	c.inventory = {"gold": 1000}
	return {"world": w, "caster": c, "ally": ally, "foe": foe}


func test_every_included_spell_casts_without_script_errors() -> void:
	var log := SpellErrors.new()
	OS.add_logger(log)
	var broken := []
	var cast_ok := 0
	var ids: Array = _db().ids("spell")
	for sid: String in ids:
		var sp: Dictionary = _db().get_entry("spell", sid)
		if str(sp.get("game_status", "included")) != "included":
			continue
		var a := _arena()
		var w: Dictionary = a["world"]
		var c: Node = a["caster"]
		if not c.spells.has(sid):
			c.spells.append(sid)
		var before := log.count
		var tried := false
		# 조준 후보: 적 → 아군 → 자신 → 빈 칸 — 처음으로 시전 가능한 곳에
		for cell: Vector2i in [w["grid"].cell_of(a["foe"]), w["grid"].cell_of(a["ally"]), w["grid"].cell_of(c), Vector2i(4, 3)]:
			c.reset_turn()
			w["turns"].in_combat = false
			if Spellcasting.can_cast(w, c, sid, cell) != "":
				continue
			var r: Dictionary = Spellcasting.cast(w, c, sid, cell)
			tried = true
			if r.get("ok", false):
				cast_ok += 1
			break
		if log.count > before:
			broken.append("%s: %s" % [sid, log.last])
		var Sp: Variant = Spellcasting
		for inst_id: Variant in Sp.instances.keys():
			Sp.end_instance(inst_id)
		Sp.instances.clear()
		if not tried:
			pass  # 이 장면에서 조건이 안 맞는 주문(시체·물체 필요 등) — 오류만 아니면 된다
	OS.remove_logger(log)
	assert_eq(broken.size(), 0, "스크립트 오류가 난 주문 %d개: %s" % [broken.size(), "; ".join(PackedStringArray(broken.slice(0, 5)))])
	assert_true(cast_ok >= 140, "시험 장면에서 실제로 시전된 주문 %d개" % cast_ok)


## 쓰는 아이템(물약·두루마리·모험 장비)은 모두 행동 목록에 뜨고 써도 오류가 없다
func test_every_usable_item_works() -> void:
	var Actions := load("res://scripts/rules/actions.gd")
	var log := SpellErrors.new()
	OS.add_logger(log)
	var broken := []
	for iid: String in _db().ids("item"):
		var item: Dictionary = _db().get_entry("item", iid)
		var cat := str(item.get("category", ""))
		if not cat in ["potion", "scroll", "gear"]:
			continue
		var a := _arena()
		var w: Dictionary = a["world"]
		var c: Node = a["caster"]
		if cat == "scroll":
			# 그 주문 목록을 가진 클래스로
			var list: String = str(_db().get_entry("spell", str(item["spell"])).get("classes", ["wizard"])[0])
			var cid := ""
			for k: String in _db().ids("class"):
				if str(_db().get_entry("class", k).get("spellcasting", {}).get("list", "")) == list:
					cid = k
			if cid == "":
				continue
			var nc: Node = own(Builder.build(Builder.default_spec(cid, 3))["creature"])
			w["grid"].remove(c)
			w["grid"].place(nc, Vector2i(2, 1))
			c = nc
		c.inventory[iid] = 3
		var before := log.count
		var keys: Array = Actions.list_for(w, c)["items"]
		var used := 0
		for key: String in keys:
			if not key.ends_with(":" + iid):
				continue
			c.reset_turn()
			var target: Vector2i = w["grid"].cell_of(a["foe"]) if key.begins_with("read_scroll") or key.begins_with("throw") else w["grid"].cell_of(a["ally"])
			if key.begins_with("spread"):
				target = w["grid"].cell_of(c) + Vector2i(0, 1)  # 뿌리기: 바로 옆 칸
			if key.begins_with("drink"):
				target = w["grid"].cell_of(c)
			Actions.execute(w, c, key, target)
			used += 1
		if used == 0:
			broken.append("%s: 행동 목록에 없다" % iid)
		if log.count > before:
			broken.append("%s: %s" % [iid, log.last])
	OS.remove_logger(log)
	assert_eq(broken.size(), 0, "문제 아이템: %s" % "; ".join(PackedStringArray(broken)))
