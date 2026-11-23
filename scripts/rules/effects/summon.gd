extends "res://scripts/rules/effect_script.gd"
## 소환 주문: Find Familiar(올빼미 사역마, 긴 휴식까지), Find Steed(이계의 탈것, 긴 휴식까지 — 올라타기 없음), Animate Dead(쓰러진 휴머노이드 시체 → 좀비, 없으면 해골, 긴 휴식까지), Spiritual Weapon(떠 있는 무기 — 시전 때 1d8+주문 수정치 역장 근접 주문 공격, 이후 보너스 행동으로 4칸 움직여 다시), Flaming Sphere(불구체 — 1칸 안에서 턴을 마치면 민첩 내성 2d6, 보너스 행동으로 6칸 굴림, 지나간 가연성 칸 점화), Mage Hand(유령 손 — 6칸 안 상자 열기·함정 미리 발동). 소환 생물은 시전자 편, AI가 움직인다.

const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var sid: String = ctx["spell"]["id"]
	match sid:
		"find_familiar":
			return _creature(ctx, "owl", true)
		"find_steed":
			return _steed(ctx)
		"animate_dead":
			return _animate(ctx)
		"spiritual_weapon":
			return _spiritual_weapon(ctx)
		"flaming_sphere":
			return _flaming_sphere(ctx)
		"mage_hand":
			U.entity(ctx, "mage_hand", U.aim_cell(ctx))
			return {"ok": true}
	return {"ok": false, "reason": "모르는 소환"}


static func _free_cell_near(g: Node, cell: Vector2i) -> Vector2i:
	for r in range(0, 4):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := cell + Vector2i(dx, dy)
				if g.in_bounds(c) and not g.blocks_movement(c) and g.creature_at(c) == null:
					return c
	return Vector2i(-1, -1)


static func _creature(ctx: Dictionary, monster: String, flying: bool, at: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	var g := U.grid(ctx)
	var caster: Node = ctx["self"]
	var cell := at if at.x >= 0 else _free_cell_near(g, U.aim_cell(ctx))
	if cell.x < 0:
		return {"ok": false, "reason": "놓을 자리가 없다"}
	var m: Node = load("res://scripts/rules/monster_factory.gd").spawn(monster, caster.team)
	m.name = "%s_%s_%d" % [monster, caster.name, ctx["instance"]["id"]]
	m.set_meta("summoner", caster)
	m.set_meta("summon_until", "long_rest")
	m.faction = caster.faction
	g.place(m, cell, int(m.get_meta("cells", 1)))
	if flying:
		m.apply_condition("flying", -1, caster)
		m.altitude = 1
	if caster.get_parent() != null:
		caster.get_parent().add_child(m)  # 화면에서는 새 그림을 만든다(battle_scene이 world.summons를 본다)
	var w: Dictionary = ctx["world"]
	if w.get("turns") != null:
		w["turns"].add_participant(m)
	if not w.has("summons"):
		w["summons"] = []
	w["summons"].append(m)
	if not w.has("on_long_rest"):
		w["on_long_rest"] = []
	w["on_long_rest"].append(func() -> void:
		if is_instance_valid(m) and g.creatures().has(m):
			g.remove(m)
			m.dead = true)  # 소환은 긴 휴식까지
	Dice.log_text("%s가 %s를 불러냈다" % [caster.label(), m.label()])
	return {"ok": true, "summon": m}


## 탈것 찾기: 이계의 탈것(슬롯 레벨로 AC·HP·강타 피해, 명중 = 시전자 주문 공격). 이미 있으면 바꾼다.
static func _steed(ctx: Dictionary) -> Dictionary:
	var caster: Node = ctx["self"]
	var w: Dictionary = ctx["world"]
	for old: Variant in w.get("summons", []):
		if old is Node and is_instance_valid(old) and old.get_meta("summoner", null) == caster and str(old.get_meta("monster", {}).get("id", "")) == "otherworldly_steed" and not old.dead:
			U.grid(ctx).remove(old)
			old.dead = true
	var r := _creature(ctx, "otherworldly_steed", false)
	if not r.get("ok", false):
		return r
	var m: Node = r["summon"]
	var lv := int(ctx.get("slot", 2))
	m.ac_base = 10 + lv
	m.hp_max = 5 + 10 * lv
	m.hp = m.hp_max
	var data: Dictionary = m.get_meta("monster").duplicate(true)
	data["actions"][0]["bonus"] = load("res://scripts/rules/spellcasting.gd").spell_attack_bonus(caster)
	data["actions"][0]["damage"] = [{"dice": "1d8+%d" % lv, "damage_type": "radiant"}]
	m.set_meta("monster", data)
	m.proficiency_bonus = caster.proficiency_bonus
	return r


static func _animate(ctx: Dictionary) -> Dictionary:
	var g := U.grid(ctx)
	var corpse: Node = g.creature_at(U.aim_cell(ctx))
	if corpse != null and corpse.dead and corpse.creature_type == "humanoid":
		var at: Vector2i = g.cell_of(corpse)
		g.remove(corpse)
		return _creature(ctx, "zombie", false, at)
	return _creature(ctx, "skeleton", false)


static func _spiritual_weapon(ctx: Dictionary) -> Dictionary:
	var cell := U.aim_cell(ctx)
	U.entity(ctx, "spiritual_weapon", cell)
	var r := strike(ctx["world"], ctx["self"], ctx["instance"], cell)
	return {"ok": true, "attack": r}


## Spiritual Weapon 공격: 무기 칸 인접 적 하나에 근접 주문 공격, 1d8(+1d8/슬롯 2 초과) + 주문 수정치 역장.
static func strike(world: Dictionary, caster: Node, inst: Dictionary, cell: Vector2i, target: Node = null) -> Dictionary:
	var g: Node = world["grid"]
	var Sp := load("res://scripts/rules/spellcasting.gd")
	if target == null:
		for o: Node in g.creatures():
			if not o.dead and caster.is_hostile_to(o) and g.distance(cell, g.cell_of(o)) <= 1:
				target = o
				break
	if target == null:
		return {}
	var dice := "%dd8%+d" % [1 + maxi(int(inst.get("slot", 2)) - 2, 0), Sp.spell_mod(caster)]
	var atk := {"name": "Spiritual Weapon", "bonus": Sp.spell_attack_bonus(caster), "kind": "melee", "weapon": false,
		"damage": [{"dice": dice, "damage_type": "force"}], "properties": []}
	return Resolver.attack(caster, target, atk, g.attack_context(caster, target))


static func _flaming_sphere(ctx: Dictionary) -> Dictionary:
	var g := U.grid(ctx)
	var cell := _free_cell_near(g, U.aim_cell(ctx))
	var e := U.entity(ctx, "flaming_sphere", cell)
	var caster: Node = ctx["self"]
	var inst: Dictionary = ctx["instance"]
	var dc := U.dc(ctx)
	inst["auras"].append({"on_turn_end": func(w: Dictionary, who: Node) -> void:
		if who.dead or g.distance(g.cell_of(who), e["cell"]) > 1 or not g.creatures().has(who):
			return
		sphere_burn(w, who, inst, dc)})
	return {"ok": true}


static func sphere_burn(_w: Dictionary, t: Node, inst: Dictionary, dc: int) -> void:
	var dice := "%dd6" % (2 + maxi(int(inst.get("slot", 2)) - 2, 0))
	Resolver.save_effect([t], {"ability": "dex", "dc": dc}, [{"type": "damage", "dice": dice, "damage_type": "fire"}],
		[{"type": "damage", "dice": dice, "damage_type": "fire", "scale": 0.5}], {"source": inst["caster"]})
