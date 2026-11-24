extends RefCounted
## 소서러 하위 클래스(BG3) 주문 시전 뒤 장치 — Spellcasting.cast 끝에서 부른다. 능력 태그로만 본다.
## - wild_magic_surge(야생 마법): 레벨 주문을 쓰면 d20 = 20(혼돈의 물결을 쓴 뒤에는 11 이상)이면 급증(표 10종 — SURGES).
## - tempestuous_magic(폭풍 마법): 레벨 주문 뒤 이번 턴 보너스 행동으로 6칸 날기(기회 공격 없음) — turn tempest_ready.
## - heart_of_the_storm(폭풍의 심장): 레벨 주문이 번개·천둥 피해면 4칸 안 적에게 소서러 레벨/2 그 피해.

const Resolver := preload("res://scripts/rules/resolver.gd")
const SURGES := ["action_surge", "blur", "burning", "entangle", "flight", "fog", "shield", "slow", "spike_growth", "teleport"]


static func after_cast(world: Dictionary, c: Node, spell: Dictionary, r: Dictionary) -> void:
	if not r.get("ok", false) or int(spell.get("level", 0)) <= 0:
		return
	if c.has_cap("tempestuous_magic"):
		c.turn["tempest_ready"] = true
	if c.has_cap("heart_of_the_storm") and world.has("grid"):
		var types: Array = []
		var effs: Dictionary = spell.get("effects", {})
		for e: Dictionary in effs.get("fail", []) + effs.get("hit", []) + effs.get("apply", []) + effs.get("on_hit", []):
			if e.get("type", "") == "damage" and str(e.get("damage_type", "")) in ["lightning", "thunder"]:
				types.append(str(e["damage_type"]))
		if not types.is_empty():
			var n := maxi(1, c.feature_level("heart_of_the_storm") / 2)
			for o: Node in world["grid"].creatures():
				if not o.dead and o.is_hostile_to(c) and world["grid"].distance_between(c, o) <= 4:
					Resolver.apply_damage(o, [{"amount": n, "damage_type": types[0]}], {"attacker": c})
	# 통제된 혼돈(야생 마법 11레벨, BG3 — 능력 태그 controlled_chaos): 4칸 안 적이 레벨 주문을 쓰면 25%로 그 적에게 해로운 급증
	if world.has("grid"):
		for o: Node in world["grid"].creatures():
			if o != c and not o.dead and o.has_cap("controlled_chaos") and o.is_hostile_to(c) and world["grid"].distance_between(o, c) <= 4:
				if Dice.roll("1d4", "통제된 혼돈")["total"] == 4:
					surge(world, c, ["burning", "slow"][Dice.roll("1d2", "통제된 혼돈")["total"] - 1])
				break
	if c.has_cap("wild_magic_surge"):
		var need := 11 if c.has_meta("tides_used") else 20
		if Dice.roll("1d20", "야생 마법 급증")["total"] >= need:
			c.remove_meta("tides_used")
			surge(world, c)


static func surge(world: Dictionary, c: Node, forced: String = "") -> String:
	var id: String = forced if forced != "" else SURGES[Dice.roll("1d%d" % SURGES.size(), "급증 표")["total"] - 1]
	Dice.log_text("%s 야생 마법 급증: %s" % [c.label(), id])
	var grid: Node = world.get("grid")
	match id:
		"action_surge":
			c.turn["action"] = int(c.turn.get("action", 0)) + 1
		"blur":
			if grid != null:
				for o: Node in grid.creatures():
					if not o.dead and grid.distance_between(c, o) <= 6:
						o.apply_condition("surge_blur", 2, c)
		"burning":
			if grid != null:
				for o: Node in grid.creatures():
					if o != c and not o.dead and grid.distance_between(c, o) <= 4:
						o.apply_condition("burning", 0, c)
		"entangle", "spike_growth", "fog":
			if grid != null and world.get("surfaces") != null:
				var me: Vector2i = grid.cell_of(c)
				var cells: Array = load("res://scripts/rules/area.gd").circle(grid, me, 2 if id == "fog" else 3)
				if id == "fog":
					world["surfaces"].place_cloud(cells, "fog", {"turns": 10, "source": c})
				else:
					world["surfaces"].place_surface(cells.filter(func(x: Vector2i) -> bool: return x != me), "vines" if id == "entangle" else "thorns", {"turns": 10, "source": c})
		"flight":
			c.apply_condition("flying", 1, c)
		"shield":
			c.apply_condition("surge_shield", 1, c)
		"slow":
			c.apply_condition("slowed", 2, c)
		"teleport":
			c.apply_condition("surge_teleport", 2, c)
	return id
