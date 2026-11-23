extends RefCounted
## 휴식·캠프(룰북 7단계). 상태 없음 — 파티 상태는 world에.
##   world["short_rests_left"]: 긴 휴식 사이 남은 짧은 휴식(기본 2)
##   world["party_resources"]["camp_supplies"]: 보급품 수치(Create Food and Water 등) + 소지품 음식의 camp_supplies
##   캠프 서비스(부활 200gp·재분배 100gp): 파티 금화를 모아 낸다(고른 캐릭터 먼저)
##   world["inspiration"]: 파티 공용 영감(최대 4)

const SpellPrep := preload("res://scripts/rules/spell_prep.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Interact := preload("res://scripts/rules/interact.gd")
const Stealth := preload("res://scripts/rules/stealth.gd")

const SHORT_RESTS := 2
const LONG_REST_SUPPLIES := 40
const SHORT_REST_TURNS := 600  # 1시간 = 600턴: 100턴 이하 지속 효과가 모두 끝난다
const REVIVE_GP := 200
const RESPEC_GP := 100
const INSPIRATION_MAX := 4


## 휴식할 수 없는 이유("" = 가능): 전투 중, 적이 의심 단계 이상.
static func blocked_reason(world: Dictionary, party: Array) -> String:
	if world.get("turns") != null and world["turns"].in_combat:
		return "전투 중에는 쉴 수 없다"
	for o: Node in world["grid"].creatures():
		if o.dead or o.team == "party":
			continue
		for p: Node in party:
			if o.awareness.get(p, {}).get("state", "") != "":
				return "적이 경계하고 있다"
	return ""


# ---------- 짧은 휴식 ----------

## 짧은 휴식: 긴 휴식 사이 2회, 활성 파티원 HP를 최대치 절반만큼 회복, 짧은 휴식 자원 회복, 1시간 경과.
static func short_rest(world: Dictionary, party: Array) -> Dictionary:
	var why := blocked_reason(world, party)
	if why == "" and int(world.get("short_rests_left", SHORT_RESTS)) <= 0:
		why = "짧은 휴식을 모두 썼다"
	if why != "":
		return {"ok": false, "reason": why}
	world["short_rests_left"] = int(world.get("short_rests_left", SHORT_RESTS)) - 1
	pass_time(world, SHORT_REST_TURNS)
	for c: Node in party:
		if c.dead:
			continue
		_heal_to(c, c.hp_max if c.has_cap("short_rest_full_heal") else mini(c.hp_max, c.hp + c.hp_max / 2))  # 회복 체질: 전부
		SpellPrep.open_window(c, "short")  # 주문 암기(능력 태그 prepare_swap_short_rest): 1개 교체
		for id: String in c.resources:
			var r: Dictionary = c.resources[id]
			match r.get("recharge", ""):
				"short":
					r["current"] = r["max"]
				"short_one":
					r["current"] = mini(r["max"], r["current"] + 1)
		# 능력 태그 sorcerous_restoration(소서러 마법 회복): 짧은 휴식 뒤 마법 점수를 레벨 절반까지, 긴 휴식마다 1회(자동)
		if c.has_cap("sorcerous_restoration") and c.resource("sorcerous_restoration") > 0 and c.resources.has("sorcery_points"):
			var sp: Dictionary = c.resources["sorcery_points"]
			if int(sp["current"]) < int(sp["max"]):
				sp["current"] = mini(int(sp["max"]), int(sp["current"]) + c.level / 2)
				c.spend_resource("sorcerous_restoration")
	EventBus.on_short_rest.emit()
	Dice.log_text("짧은 휴식(남은 %d회)" % world["short_rests_left"])
	return {"ok": true}


# ---------- 긴 휴식 ----------

## 보급품을 찾는 가방: 파티·쉬는 동료의 소지품과 캠프 보관함(BG3: 캠프에서는 모두의 음식을 쓴다).
static func _bags(world: Dictionary) -> Array:
	var out: Array = []
	for c: Variant in world.get("party", []) + world.get("roster", []):
		if c is Node and is_instance_valid(c):
			out.append(c.inventory)
	if not world.has("stash"):
		world["stash"] = {}
	out.append(world["stash"])
	return out


static func supplies(world: Dictionary) -> int:
	var total := int(world.get("party_resources", {}).get("camp_supplies", 0))
	for bag: Dictionary in _bags(world):
		for item: String in bag:
			total += int(RulesDB.get_entry("item", item).get("camp_supplies", 0)) * int(bag[item])
	return total


## 보급품을 쓴다: 주문으로 만든 보급품 → 음식(값이 작은 것부터, 보관함 먼저).
static func _spend_supplies(world: Dictionary, need: int) -> void:
	var pr: Dictionary = world.get("party_resources", {})
	var from_pool := mini(need, int(pr.get("camp_supplies", 0)))
	if from_pool > 0:
		pr["camp_supplies"] = int(pr["camp_supplies"]) - from_pool
		need -= from_pool
	var foods: Array = []
	var bags := _bags(world)
	bags.push_front(bags.pop_back())  # 보관함 먼저
	for bag: Dictionary in bags:
		for item: String in bag:
			var v := int(RulesDB.get_entry("item", item).get("camp_supplies", 0))
			if v > 0:
				foods.append([v, item, bag])
	foods.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for f: Array in foods:
		var bag: Dictionary = f[2]
		while need > 0 and int(bag.get(f[1], 0)) > 0:
			bag[f[1]] = int(bag[f[1]]) - 1
			if int(bag[f[1]]) <= 0:
				bag.erase(f[1])
			need -= int(f[0])


## 긴 휴식: 캠프 불가 구역이 아니어야 한다(Tiny Hut이면 가능). 보급품 40이면 전부 회복,
## 모자라면 부분 휴식(HP·슬롯 최대치 절반까지, 짧은 휴식 충전 없음). 쉬는 동료(roster)도 긴 휴식은 받는다.
## opts: {"tiny_hut": bool, "partial": bool(보급품이 있어도 부분 휴식을 고름), "roster": [쉬는 동료]}
static func long_rest(world: Dictionary, party: Array, opts: Dictionary = {}) -> Dictionary:
	var why := blocked_reason(world, party)
	if why != "":
		return {"ok": false, "reason": why}
	var grid: Node = world["grid"]
	# 긴 휴식 = 캠프로 이동. 캠프 불가 판정은 휴식을 부르는 리더의 칸으로 한다(파티는 함께 캠프로 간다).
	var hut: Dictionary = world.get("tiny_hut", {})
	if not hut.is_empty() and Spellcasting.instances.has(hut.get("instance", -1)):
		opts["tiny_hut"] = true  # Tiny Hut이 서 있으면 캠프 불가 구역에서도
	if not opts.get("tiny_hut", false):
		var caller: Node = opts.get("caller", world["explore"].leader if world.get("explore") != null else null)
		if caller == null or caller.dead:
			for p: Node in party:
				if not p.dead:
					caller = p
					break
		if caller != null and grid.has_flag(grid.cell_of(caller), "no_camp"):
			return {"ok": false, "reason": "여기서는 캠프를 칠 수 없다"}
	var full: bool = supplies(world) >= LONG_REST_SUPPLIES and not opts.get("partial", false)
	if full:
		_spend_supplies(world, LONG_REST_SUPPLIES)
	pass_time(world, -1)
	var everyone: Array = party.duplicate()
	everyone.append_array(opts.get("roster", world.get("roster", [])))  # 쉬는 동료도 긴 휴식은 받는다(7단계)
	for c: Node in everyone:
		if c.dead:
			continue
		c.temp_hp = 0
		c.death_saves = {"successes": 0, "failures": 0}
		SpellPrep.open_window(c, "long")  # 준비 주문 교체 창(다음 전투까지)
		for sk: String in c.get_meta("temp_skills", []):
			c.skill_bonuses.erase(sk)  # 시대의 지식(지식 영역): 긴 휴식까지
		c.set_meta("temp_skills", [])
		if c.has_meta("beast_form"):
			load("res://scripts/rules/effects/wild_shape.gd").revert(c)  # 야생 변신은 긴 휴식까지(레벨 절반 시간)
		if full:
			_heal_to(c, c.hp_max)
			for id: String in c.resources:
				c.resources[id]["current"] = c.resources[id]["max"]
		else:
			_heal_to(c, maxi(c.hp, c.hp_max / 2))
			for id: String in c.resources:
				var r: Dictionary = c.resources[id]
				if id.begins_with("spell_slot_") or id.begins_with("pact_slot_"):
					r["current"] = maxi(r["current"], int(r["max"]) / 2)
	if full:
		world["short_rests_left"] = SHORT_RESTS
	# 능력 태그 long_rest_inspiration(인간 '기지'): 긴 휴식 때 공용 영감 +1(5단계)
	for c: Node in party if full else []:
		if not c.dead and c.has_cap("long_rest_inspiration"):
			add_inspiration(world, 1)
	for f: Callable in world.get("on_long_rest", []):
		if f.is_valid():
			f.call()
	world["on_long_rest"] = []
	# 긴 휴식에 사라지는 아이템(아이템 데이터 expires: long_rest — 좋은열매)
	var bags := _bags(world)
	for c: Node in everyone:
		if not c.inventory in bags:
			bags.append(c.inventory)
	for inv: Dictionary in bags:
		for item: String in inv.keys():
			if str(RulesDB.get_entry("item", item).get("expires", "")) == "long_rest":
				inv.erase(item)
	EventBus.on_long_rest.emit()
	Dice.log_text("긴 휴식%s" % ("" if full else "(부분)"))
	return {"ok": true, "partial": not full}


static func _heal_to(c: Node, value: int) -> void:
	if value > c.hp:
		c.hp = value
		c.stable = false
		c.death_saves = {"successes": 0, "failures": 0}
		c.remove_condition("unconscious")


# ---------- 시간 경과 ----------

## turns만큼 시간이 흐른다(-1 = 긴 휴식까지). 그 안에 끝나는 상태·수정치·집중·주문을 걷어낸다.
## '긴 휴식까지' 주문은 긴 휴식에서만, '영구'는 끝나지 않는다.
static func pass_time(world: Dictionary, turns: int) -> void:
	for id: int in Spellcasting.instances.keys():
		var inst: Dictionary = Spellcasting.instances[id]
		if inst["world"] != world:
			continue
		var spell := RulesDB.get_entry("spell", inst["spell"])
		var t: String = spell.get("duration", {}).get("type", "instant")
		var ends := t == "turns" or t == "instant" or (turns < 0 and t == "until_long_rest")
		if t == "turns" and turns >= 0:
			ends = int(spell["duration"]["turns"]) <= turns
		if ends:
			Spellcasting.end_instance(id)
	for c: Node in world["grid"].creatures():
		for cond in c.conditions.duplicate():
			var left: int = int(cond["turns_left"])
			if (left > 0 and (turns < 0 or left <= turns)) or (turns < 0 and cond.get("until_long_rest", false)):
				c.remove_condition(cond["id"])
		for m in c.extra_modifiers.duplicate():
			var left: int = int(m.get("turns_left", -1))
			if (left > 0 and (turns < 0 or left <= turns)) or (turns < 0 and m.get("until_long_rest", false)):
				c.extra_modifiers.erase(m)
		if not c.concentration.is_empty():
			var left: int = int(c.concentration.get("turns_left", -1))
			if turns < 0 or (left > 0 and left <= turns):
				c.break_concentration("시간 경과")
	if world.get("surfaces") != null and turns != 0:
		world["surfaces"].expire_timed(turns)


# ---------- 영감 ----------

## 공용 영감(최대 4). 이미 가득이면 넘친 만큼 돌려준다(경험치로 바꿀 몫).
static func add_inspiration(world: Dictionary, n: int) -> int:
	var cur := int(world.get("inspiration", 0))
	var after := mini(INSPIRATION_MAX, cur + n)
	world["inspiration"] = after
	return n - (after - cur)


# ---------- 캠프 서비스 ----------

static func gold(world: Dictionary) -> int:
	return Interact.count(world, "gold")


## 캠프 부활(200gp, 시간 제한 없음): HP 1로 되살린다.
static func camp_revive(world: Dictionary, c: Node) -> Dictionary:
	if not c.dead:
		return {"ok": false, "reason": "죽지 않았다"}
	if not Interact.take(world, "gold", REVIVE_GP):
		return {"ok": false, "reason": "골드가 모자란다"}
	c.dead = false
	c.hp = 1
	c.stable = false
	c.death_saves = {"successes": 0, "failures": 0}
	c.remove_condition("unconscious")
	return {"ok": true}


## 재분배(100gp): 값을 치르고 캐릭터 만들기 화면을 다시 연다(화면 쪽에서).
static func pay_respec(world: Dictionary) -> Dictionary:
	if not Interact.take(world, "gold", RESPEC_GP):
		return {"ok": false, "reason": "골드가 모자란다"}
	return {"ok": true}
