extends RefCounted
## 주문 시전(첫 판, 상태 없음). spells.json의 효과 모델을 그대로 읽는다: check(attack|save) → hit/fail/success, apply.
## 4단계 시험 전투에 필요한 만큼만: 공격·내성 피해, 회복, 상태 걸기, 범위(구·원기둥·원뿔·선·정육면체·발산),
## 범위 피해의 칸 반응(단일 대상은 칸 반응 없음 — 9단계 충돌 A). 스크립트 효과·업캐스트·집중은 5단계.

const Resolver := preload("res://scripts/rules/resolver.gd")
const Area := preload("res://scripts/rules/area.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Physics := preload("res://scripts/rules/physics.gd")


static func spell_mod(c: Node) -> int:
	return c.ability_mod(c.spellcasting_ability) if c.spellcasting_ability != "" else 0


static func spell_dc(c: Node) -> int:
	return 8 + c.proficiency_bonus + spell_mod(c)


static func spell_attack_bonus(c: Node) -> int:
	return c.proficiency_bonus + spell_mod(c)


## 소마법 피해 주사위(5레벨 강화 — cantrip_scaling).
static func _dice_for(c: Node, spell: Dictionary, dice: String) -> String:
	var best := dice
	var scaling: Dictionary = spell.get("upcast", {}).get("cantrip_scaling", {})
	var best_lv := 0
	for lv: String in scaling.keys():
		if c.level >= int(lv) and int(lv) > best_lv:
			best_lv = int(lv)
			best = scaling[lv]
	return best


static func _cost(spell: Dictionary) -> String:
	match spell["cast"]["cost"]:
		"bonus_action":
			return "bonus"
		"reaction":
			return "reaction"
	return "action"


static func range_tiles(spell: Dictionary) -> int:
	match spell["range"]["type"]:
		"tiles":
			return int(spell["range"]["tiles"])
		"touch":
			return 1
	return 0


## 범위 칸. 구·원기둥은 조준 칸 중심, 원뿔·선·정육면체는 시전자에서 조준 방향, 발산은 시전자 칸.
static func area_cells(world: Dictionary, caster: Node, spell: Dictionary, aim: Vector2i) -> Array[Vector2i]:
	var grid: Node = world["grid"]
	var a: Variant = spell.get("area")
	var out: Array[Vector2i] = []
	if a == null:
		return out
	var from: Vector2i = grid.cell_of(caster)
	var dir := Vector2i(signi(aim.x - from.x), signi(aim.y - from.y))
	match a["shape"]:
		"sphere", "cylinder":
			return Area.circle(grid, aim, int(a["radius_tiles"]))
		"emanation":
			return Area.circle(grid, from, int(a["radius_tiles"]))
		"cone":
			return Area.cone(grid, from, dir, int(a["length_tiles"]))
		"line":
			return Area.line(grid, from, aim, int(a["length_tiles"]))
		"cube":
			if spell["range"]["type"] == "self":
				return Area.cube_from(grid, from, dir, int(a["size_tiles"]))
			return Area.square(grid, aim - Vector2i(int(a["size_tiles"]) / 2, int(a["size_tiles"]) / 2), int(a["size_tiles"]), from)
		"square":
			return Area.square(grid, aim, int(a["size_tiles"]), from)
	return out


## 시전 가능 여부와 이유("" = 가능).
static func can_cast(world: Dictionary, caster: Node, spell_id: String, aim: Vector2i) -> String:
	var spell := RulesDB.get_entry("spell", spell_id)
	if spell.is_empty():
		return "모르는 주문"
	if spell.has("script"):
		return "스크립트 주문은 5단계"
	if not caster.spells.has(spell_id):
		return "모르는 주문"
	if not Combat.can_spend(caster, _cost(spell)):
		return "비용이 없다"
	if int(spell["level"]) > 0 and _slot(caster, int(spell["level"])) == "":
		return "주문 슬롯이 없다"
	var grid: Node = world["grid"]
	var rt := range_tiles(spell)
	if spell["range"]["type"] != "self" and grid.distance(grid.cell_of(caster), aim) > grid.effective_range(caster, aim, rt):
		return "사거리 밖"
	if spell["range"]["type"] != "self" and not grid.has_line_of_sight(grid.cell_of(caster), aim):
		return "보이지 않는다"
	return ""


static func _slot(c: Node, level: int) -> String:
	for lv in range(level, 10):
		if c.resource("spell_slot_%d" % lv) > 0:
			return "spell_slot_%d" % lv
	return ""


## 시전 미리보기: 대상별 명중·실패 확률, 범위 칸, 칸 반응 결과, 피해 범위.
static func preview(world: Dictionary, caster: Node, spell_id: String, aim: Vector2i) -> Dictionary:
	var spell := RulesDB.get_entry("spell", spell_id)
	var why := can_cast(world, caster, spell_id, aim)
	var out := {"valid": why == "", "reason": why, "cells": area_cells(world, caster, spell, aim), "targets": [],
		"reactions": []}
	if spell.is_empty():
		return out
	var check: Dictionary = spell["effects"].get("check", {})
	for t: Node in _targets(world, caster, spell, aim, out["cells"]):
		var row := {"creature": t}
		if check.get("type") == "attack":
			row["chance"] = Resolver.preview_attack(caster, t, _spell_attack(caster, spell), world["grid"].attack_context(caster, t)).get("hit_chance", 0.0)
		elif check.get("type") == "save":
			row["chance"] = Resolver.preview_save_fail(t, check["ability"], spell_dc(caster))
		out["targets"].append(row)
	var dtype := _area_damage_type(spell)
	if dtype != "" and not out["cells"].is_empty():
		out["reactions"] = world["surfaces"].preview_tile_damage(out["cells"], dtype)
	return out


static func _targets(world: Dictionary, caster: Node, spell: Dictionary, aim: Vector2i, cells: Array) -> Array:
	var grid: Node = world["grid"]
	if spell.get("area") != null:
		return Area.creatures_in(grid, cells).filter(func(c: Node) -> bool: return not c.dead and c != caster)
	var t: Node = grid.creature_at(aim)
	return [] if t == null else [t]


static func _spell_attack(caster: Node, spell: Dictionary) -> Dictionary:
	var hit: Array = []
	for e: Dictionary in spell["effects"].get("hit", []):
		if e["type"] == "damage":
			hit.append({"dice": _dice_for(caster, spell, e["dice"]), "damage_type": e["damage_type"]})
	return {"name": spell["name"]["en"], "bonus": spell_attack_bonus(caster), "weapon": false,
		"kind": spell["effects"]["check"].get("kind", "ranged"), "damage": hit}


static func _area_damage_type(spell: Dictionary) -> String:
	if spell.get("area") == null:
		return ""
	for e: Dictionary in spell["effects"].get("fail", []) + spell["effects"].get("apply", []):
		if e["type"] == "damage":
			return e["damage_type"]
	return ""


## 시전. 결과: {"ok", "reason", "results": [...]}
static func cast(world: Dictionary, caster: Node, spell_id: String, aim: Vector2i) -> Dictionary:
	var why := can_cast(world, caster, spell_id, aim)
	if why != "":
		return {"ok": false, "reason": why}
	var spell := RulesDB.get_entry("spell", spell_id)
	Combat.spend(caster, _cost(spell))
	if int(spell["level"]) > 0:
		caster.spend_resource(_slot(caster, int(spell["level"])))
	EventBus.on_spell_cast.emit({"caster": caster, "spell": spell_id, "aim": aim})
	Dice.log_text("%s: %s" % [caster.label(), spell["name"]["en"]])
	var grid: Node = world["grid"]
	var cells := area_cells(world, caster, spell, aim)
	var targets := _targets(world, caster, spell, aim, cells)
	var eff: Dictionary = spell["effects"]
	var check: Dictionary = eff.get("check", {})
	var results: Array = []
	if check.get("type") == "attack":
		for t: Node in targets:
			var atk := _spell_attack(caster, spell)
			var ctx: Dictionary = grid.attack_context(caster, t)
			if atk["kind"] == "ranged" and Combat.is_threatened(world, caster):
				ctx["disadvantage"].append("근접 위협")
			var r := Resolver.attack(caster, t, atk, ctx)
			if r["hit"]:
				for e: Dictionary in eff.get("hit", []):
					if e["type"] == "apply_condition":
						t.apply_condition(e["id"], int(e.get("turns", 0)), caster)
			results.append(r)
	elif check.get("type") == "save":
		var rolled := {}
		var fail := _scaled(caster, spell, eff.get("fail", []))
		var success := _scaled(caster, spell, eff.get("success", []))
		results = Resolver.save_effect(targets, {"ability": check["ability"], "dc": spell_dc(caster)},
			fail, success, {"source": caster, "rolled": rolled})
		for r: Dictionary in results:
			if not r["save"]["success"]:
				for e: Dictionary in fail:
					if e["type"] == "push" and not r["target"].dead:
						Combat._push_up_to(world, caster, r["target"], int(e["tiles"]))
		var dtype := _area_damage_type(spell)
		if dtype != "" and not cells.is_empty():
			var amount := 0
			for k: String in rolled.keys():
				amount = maxi(amount, int(rolled[k]))
			world["surfaces"].tile_damage(cells, dtype, amount, caster)
	for e: Dictionary in eff.get("apply", []):
		for t: Node in (targets if not targets.is_empty() else [caster]):
			match e["type"]:
				"heal":
					var dice: String = e["dice"]
					var add: Variant = e.get("add")
					var amount: int = Dice.roll(dice, spell["name"]["en"])["total"]
					if add == "spell_mod":
						amount += spell_mod(caster)
					Resolver.heal(t, amount, caster)
				"temp_hp":
					Resolver.grant_temp_hp(t, Dice.roll(e["dice"], spell["name"]["en"])["total"])
				"apply_condition":
					t.apply_condition(e["id"], int(e.get("turns", 0)), caster)
	if world.get("turns") != null:
		world["turns"].notify_hostile_action(caster)
	return {"ok": true, "results": results, "cells": cells}


static func _scaled(caster: Node, spell: Dictionary, effects: Array) -> Array:
	var out: Array = []
	for e: Dictionary in effects:
		var c := e.duplicate()
		if c["type"] == "damage":
			c["dice"] = _dice_for(caster, spell, c["dice"])
		out.append(c)
	return out
