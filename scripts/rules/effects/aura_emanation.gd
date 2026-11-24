extends "res://scripts/rules/effect_script.gd"
## 지속 범위 피해(주문 데이터로): 적이 범위에 들어오거나 그 안에서 턴을 끝내면 내성(check), 실패 = effects.fail 피해, 성공 = success. 한 턴에 한 번.
## 사거리 self(발산): 시전자를 따라다닌다 — Spirit Guardians(3칸 지혜 3d8 광휘), Conjure Woodland Beings(2칸 지혜 5d8 역장).
## 사거리가 있으면 겨눈 칸에 고정 — Cloudkill(4칸 건강 5d8 독), Insect Plague(4칸 건강 4d10 관통). 시전할 때 범위 안 생물도 굴린다(효과 모델).
## 반경 = area.radius_tiles. 안의 적 속도 절반·가려짐은 생략(1차 — 피해만).
## effects.apply의 damage는 내성 없이 늘 들어간다(칼날 회오리·허공의 굶주림 냉기). check가 없으면 내성을 굴리지 않는다.
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Area := preload("res://scripts/rules/area.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var inst: Dictionary = ctx["instance"]
	var spell: Dictionary = ctx["spell"]
	var slot := int(ctx["slot"])
	var eff: Dictionary = spell["effects"]
	var fail: Array = Spellcasting._scaled(c, spell, eff.get("fail", []), slot, ctx.get("opts", {}))
	var success: Array = Spellcasting._scaled(c, spell, eff.get("success", []), slot, ctx.get("opts", {}))
	var ability := str(eff.get("check", {}).get("ability", ""))
	var always: Array = Spellcasting._scaled(c, spell, eff.get("apply", []).filter(func(e: Dictionary) -> bool: return e["type"] == "damage"), slot, ctx.get("opts", {}))
	var radius := int(spell.get("area", {}).get("radius_tiles", 3))
	var follow: bool = spell["range"]["type"] == "self"
	var anchor: Vector2i = ctx["aim"]
	var dc := Spellcasting.spell_dc(c)
	var hit_marks := {}
	var trigger := func(world: Dictionary, o: Node) -> void:
		if o.dead or o == c or not o.is_hostile_to(c) or c.dead:
			return
		var grid: Node = world["grid"]
		var center: Vector2i = grid.cell_of(c) if follow else anchor
		if not Area.circle(grid, center, radius).has(grid.cell_of(o)):
			return
		var key: String = "%d:%d" % [o.get_instance_id(), world["turns"].round_number if world.get("turns") != null else 0]
		if hit_marks.has(key):
			return
		hit_marks[key] = true
		for d: Dictionary in always:
			Resolver.apply_damage(o, [{"amount": Dice.roll(str(d["dice"]), str(spell["id"]))["total"], "damage_type": str(d["damage_type"])}], {"attacker": c})
		if ability != "" and not o.dead:
			Resolver.save_effect([o], {"ability": ability, "dc": dc}, fail, success, {"source": c})
	inst["auras"].append({"on_enter": trigger, "on_turn_end": trigger})
	if not follow:
		var r := Spellcasting.resolve_effects(ctx)  # 처음 나타날 때 범위 안 생물
		var grid: Node = ctx["world"]["grid"]
		var round_now: int = ctx["world"]["turns"].round_number if ctx["world"].get("turns") != null else 0
		for row: Dictionary in r.get("results", []):
			hit_marks["%d:%d" % [row["target"].get_instance_id(), round_now]] = true
		r["ok"] = true
		return r
	return {"ok": true}
