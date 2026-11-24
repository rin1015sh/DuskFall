extends RefCounted
## 분노 변형·원초의 길 장치(바바리안 하위 클래스 BG3 — 능력 태그·상태 플래그로만 본다).
## - attack_context: 늑대의 심장(상태 플래그 ally_melee_advantage_adjacent — 그 생물 1칸 안 적을 아군이 근접 공격하면 유리),
##   독수리의 심장(oa_disadvantage_against — 나를 노리는 기회 공격 불리), 보호의 빛(protective_lights — 2칸 안 아군 AC +1),
##   광란의 긴장(frenzied_strain params.n — 명중 −n), 짐승의 면모: 호랑이(aspect_tiger — 출혈·중독 대상 명중 + 근력 수정치),
##   짐승의 면모: 울버린(aspect_wolverine — 출혈·중독 대상을 공격하면 불구).
## - turn_start: 짐승의 면모 엘크(aspect_elk — 12칸 안 아군 이동 +1칸), 벌꿀오소리(aspect_honey_badger — 중독·공포·매혹이면 50% 무료 분노),
##   악어(aspect_crocodile — 물 표면에서 이동 +2칸).
## - surge: 야생 마법 분노 효과(d8 — 이전 효과를 바꾼다).

const Resolver := preload("res://scripts/rules/resolver.gd")
const SURGES := ["wm_bolt_of_light", "wm_dark_tendrils", "wm_intangible_spirit", "wm_magic_retribution",
	"wm_protective_lights", "wm_teleport", "wm_vine_growth", "wm_weapon_infusion"]


static func attack_context(world: Dictionary, attacker: Node, target: Node, atk: Dictionary, ctx: Dictionary) -> void:
	var grid: Node = world["grid"]
	var melee := str(atk.get("kind", "")) == "melee"
	for o: Node in grid.creatures():
		if o.dead or o.hp <= 0:
			continue
		if melee and o != attacker and o.has_flag("ally_melee_advantage_adjacent") and not o.is_hostile_to(attacker) \
				and o.is_hostile_to(target) and grid.distance_between(o, target) <= 1:
			ctx["advantage"].append("늑대의 심장")
		if o.has_flag("protective_lights") and not o.is_hostile_to(target) and grid.distance_between(o, target) <= 2 \
				and not ctx.has("_lights"):
			ctx["_lights"] = true
			ctx["ac_add"] = int(ctx.get("ac_add", 0)) + 1  # 보호의 빛: 2칸 안 아군(나 포함) AC +1
	if atk.get("opportunity", false) and target.has_flag("oa_disadvantage_against"):
		ctx["disadvantage"].append("독수리의 심장")
	if target.has_cap("multiattack_defense") and attacker != target:
		# 다중 공격 방어(사냥꾼 방어 전술 7레벨, BG3): 나를 공격한 적은 다음 턴 시작까지 나에 대한 다음 공격 −4
		var key := "mad_%d" % target.get_instance_id()
		if attacker.turn.get(key, false):
			ctx["attack_add"] = int(ctx.get("attack_add", 0)) - 4
		elif not ctx.get("preview", false):
			attacker.turn[key] = true
	var rc: Dictionary = attacker.condition_instance("righteous_clarity")
	if not rc.is_empty():
		ctx["attack_add"] = int(ctx.get("attack_add", 0)) + int(rc.get("params", {}).get("bonus", 2))  # 올바른 명료함(왕관): 명중 + 숙련
	var strain: Dictionary = attacker.condition_instance("frenzied_strain")
	if not strain.is_empty():
		ctx["attack_add"] = int(ctx.get("attack_add", 0)) - int(strain.get("params", {}).get("n", 1))
	if attacker.has_condition("life_of_the_party") and target.has_condition("drunk"):
		ctx["attack_add"] = int(ctx.get("attack_add", 0)) + maxi(attacker.ability_mod("wis"), 0)  # 파티의 주인공: 취한 대상 명중 + 지혜
	if target.has_condition("life_of_the_party") and attacker.has_condition("drunk"):
		ctx["ac_add"] = int(ctx.get("ac_add", 0)) + 1  # 취한 공격자에게 AC +1
	var weak: bool = target.has_condition("bleeding") or target.has_condition("poisoned")
	if weak and attacker.has_cap("aspect_tiger"):
		ctx["attack_add"] = int(ctx.get("attack_add", 0)) + maxi(attacker.ability_mod("str"), 0)
	if weak and attacker.has_cap("aspect_wolverine") and not ctx.get("preview", false):
		target.apply_condition("crippled", 2, attacker)  # 울버린: 공격하면 불구(BG3 — 명중과 상관없이)


static func turn_start(world: Dictionary, c: Node) -> void:
	if c.has_cap("stillness_of_mind") and (c.has_condition("charmed") or c.has_condition("frightened")):
		c.remove_condition("charmed")
		c.remove_condition("frightened")
		c.turn["action"] = 0  # 마음의 고요(몽크 7레벨, BG3): 자동으로 풀고 행동을 쓴다
		Dice.log_text("%s 마음의 고요: 매혹·공포 해제" % c.label())
	var grid: Node = world["grid"]
	if not grid.creatures().has(c):
		return
	for o: Node in grid.creatures():
		if o.has_cap("aspect_elk") and not o.dead and not o.is_hostile_to(c) and grid.distance_between(o, c) <= 12:
			c.turn["movement"] = int(c.turn.get("movement", 0)) + 1  # 엘크: 12칸 안 아군(나 포함) 이동 +1칸
			break
	if c.has_cap("aspect_crocodile"):
		var s: String = grid.surface_id(grid.cell_of(c))
		if s in ["water", "deep_water", "electrified_water", "mud"]:
			c.turn["movement"] = int(c.turn.get("movement", 0)) + 2  # 악어: 물 표면에서 이동 +2칸
	if c.has_cap("aspect_honey_badger") and not c.has_condition("raging") \
			and (c.has_condition("poisoned") or c.has_condition("frightened") or c.has_condition("charmed")):
		if Dice.roll("1d2", "벌꿀오소리")["total"] == 2:
			var f: Dictionary = c.feature_data.get("rage", {})
			if not f.is_empty():
				load("res://scripts/rules/features.gd").run(str(f["script"]), {"world": world, "self": c, "feature": f, "free": true})


## 야생 마법(분노에 들어갈 때·불안정한 반발): d8 효과 하나. 이전 효과는 끝난다. 효과 상태는 분노와 함께 끝난다(ends_with raging).
static func surge(world: Dictionary, c: Node, forced: String = "") -> String:
	for id: String in SURGES:
		c.remove_condition(id)
	var id: String = forced if forced != "" else SURGES[Dice.roll("1d8", "야생 마법")["total"] - 1]
	c.apply_condition(id, -1, c)
	Dice.log_text("%s 야생 마법: %s" % [c.label(), RulesDB.get_entry("condition", id).get("name", {}).get("ko", id)])
	var grid: Node = world.get("grid")
	var dc: int = 8 + c.proficiency_bonus + c.ability_mod("con")
	match id:
		"wm_dark_tendrils":
			if grid != null:
				for o: Node in grid.creatures():
					if o != c and not o.dead and o.is_hostile_to(c) and grid.distance_between(c, o) <= 6:
						if not Resolver.saving_throw(o, "con", dc, {"source": c, "magic": true})["success"]:
							Resolver.apply_damage(o, [{"amount": Dice.roll("1d12", "어둠의 덩굴손")["total"], "damage_type": "necrotic"}], {"attacker": c})
			Resolver.grant_temp_hp(c, Dice.roll("1d12", "어둠의 덩굴손")["total"])
		"wm_vine_growth":
			if grid != null and world.get("surfaces") != null:
				var me: Vector2i = grid.cell_of(c)
				var cells: Array = load("res://scripts/rules/area.gd").circle(grid, me, 3).filter(func(x: Vector2i) -> bool: return x != me)
				world["surfaces"].place_surface(cells, "vines", {"turns": 10, "source": c})
	return id
