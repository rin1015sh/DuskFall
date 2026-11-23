extends Node
## 턴 관리. 룰북 3단계 '턴 진행 순서', '턴 자원·이니셔티브·전투 전환'.
## 탐험 중에는 실시간 6초 틱(tick)마다 한 턴이 흐르고, 전투 구역에서 전투가 시작되면 턴제로 바뀐다.
## 순서가 이어진 아군(party)은 공유 턴으로 묶여 원하는 순서로 행동한다.
## 턴은 바깥(화면·AI·테스트)이 end_turn으로 끝낸다.

const SpellPrep := preload("res://scripts/rules/spell_prep.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")

var world: Dictionary = {}
var in_combat := false
## "realtime" | "combat" | "manual"(적 없는 수동 턴제)
var mode := "realtime"
var round_number := 0
var zone := ""
## 이니셔티브 순서
var order: Array = []
## 공유 턴 묶음(배열의 배열)
var groups: Array = []
var group_index := 0
var _done := {}
var _pending: Array = []
var _tiebreak := {}
## 마지막 전투 결과: "" | "victory" | "defeat"(활성 파티 전원이 죽거나 쓰러짐 — 7단계 게임 오버) | "fled"
var result := ""


func setup(w: Dictionary) -> Node:
	world = w
	world["turns"] = self
	if not EventBus.on_enter_tile.is_connected(_on_enter_tile):
		EventBus.on_enter_tile.connect(_on_enter_tile)
	if not EventBus.on_after_attack_roll.is_connected(_on_attacked):
		EventBus.on_after_attack_roll.connect(_on_attacked)
	if not EventBus.on_damage_taken.is_connected(_on_damaged):
		EventBus.on_damage_taken.connect(_on_damaged)
	return self


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if EventBus.on_enter_tile.is_connected(_on_enter_tile):
			EventBus.on_enter_tile.disconnect(_on_enter_tile)
		if EventBus.on_after_attack_roll.is_connected(_on_attacked):
			EventBus.on_after_attack_roll.disconnect(_on_attacked)
		if EventBus.on_damage_taken.is_connected(_on_damaged):
			EventBus.on_damage_taken.disconnect(_on_damaged)


## 참가자에게 공격받거나 피해를 입은 구역 밖 생물은 다음 라운드에 합류한다
## (구역 밖으로 쫓아 나간 적에게 맞는 파티원이 턴을 못 받던 문제 — changes.md).
func _on_attacked(res: Dictionary) -> void:
	if res.get("preview", false):
		return
	_join_if_hit(res.get("attacker"), res.get("target"))


func _on_damaged(info: Dictionary) -> void:
	_join_if_hit(info.get("opts", {}).get("attacker"), info.get("target"))


func _join_if_hit(attacker: Variant, target: Variant) -> void:
	if mode != "combat" or not (attacker is Node) or not (target is Node):
		return
	if attacker in order and not target in order and not target in _pending and not target.dead:
		_pending.append(target)


# ======================================================================
# 이니셔티브
# ======================================================================

## d20 + 민첩 수정치. 투명이면 유리, 무력화면 불리(상태 데이터의 initiative 수정치).
func roll_initiative(c: Node) -> int:
	var res := {"advantage": [], "disadvantage": [], "distance": 1}
	for m in c.modifier_entries():
		Resolver._add_adv(m, "initiative", "self", c, null, res)
	var d := Dice.d20(Resolver.mode_of(res["advantage"], res["disadvantage"]), "%s 이니셔티브" % c.label())
	c.initiative = d["natural"] + c.ability_mod("dex") + c.initiative_bonus
	_tiebreak[c] = Dice.die(1000)
	_uncanny_metabolism(c)
	return c.initiative


## 능력 태그 uncanny_metabolism(몽크 신비한 대사): 이니셔티브를 굴릴 때 기가 모자라면 긴 휴식마다 1회 —
## 기를 전부 되찾고 몽크 레벨 + 무술 주사위만큼 회복.
func _uncanny_metabolism(c: Node) -> void:
	if not c.has_cap("uncanny_metabolism") or c.resource("uncanny_metabolism") <= 0 or not c.resources.has("focus"):
		return
	var f: Dictionary = c.resources["focus"]
	if int(f["current"]) >= int(f["max"]):
		return
	c.spend_resource("uncanny_metabolism")
	f["current"] = f["max"]
	var n: int = Dice.roll(load("res://scripts/rules/combat.gd").martial_arts_die(c), "신비한 대사")["total"] + c.level
	Resolver.heal(c, n, c)
	Dice.log_text("%s 신비한 대사: 기 회복, HP +%d" % [c.label(), n])


## 정렬: 이니셔티브 → 민첩 점수 → 아군 우선 → 무작위(2단계 동률 처리).
func _sort_order() -> void:
	order.sort_custom(func(a: Node, b: Node) -> bool:
		if a.initiative != b.initiative:
			return a.initiative > b.initiative
		if a.abilities["dex"] != b.abilities["dex"]:
			return a.abilities["dex"] > b.abilities["dex"]
		if (a.team == "party") != (b.team == "party"):
			return a.team == "party"
		return _tiebreak.get(a, 0) > _tiebreak.get(b, 0))
	groups.clear()
	for c: Node in order:
		if c.team == "party" and not groups.is_empty() and groups.back()[0].team == "party":
			groups.back().append(c)
		else:
			groups.append([c])


# ======================================================================
# 전투 시작·끝
# ======================================================================

## 전투 시작: 전투 구역 안의 생물만 참가한다. surprised = 상대를 감지하지 못한 생물(첫 턴 이동·행동·반응 불가).
## extra: 구역 밖이어도 참가하는 생물(발견된 캐릭터, 구역 밖에서 적대 행동을 한 공격자 — 3단계 전투 시작·참가).
func start_combat(zone_id: String, surprised: Array = [], extra: Array = []) -> void:
	zone = zone_id
	in_combat = true
	EventBus.realtime = false
	mode = "combat"
	round_number = 1
	order.clear()
	_pending.clear()
	var grid: Node = world["grid"]
	for c: Node in grid.creatures():
		if not c.dead and (_in_zone(c) or c in extra):
			order.append(c)
	for c: Node in order:
		roll_initiative(c)
		c.refresh_reaction()
		SpellPrep.close_window(c)  # 준비 주문 교체 창은 전투가 시작되면 닫힌다
		if c in surprised:
			c.apply_condition("surprised", -1, "combat_start")
	_sort_order()
	EventBus.on_combat_start.emit()
	EventBus.on_round_start.emit()
	group_index = 0
	_begin_group()


## 수동 턴제: 적 없이 파티만 순서대로(3단계).
func start_manual(party: Array) -> void:
	zone = ""
	in_combat = true
	mode = "manual"
	round_number = 1
	order = party.duplicate()
	for c: Node in order:
		roll_initiative(c)
	_sort_order()
	group_index = 0
	_begin_group()


func end_combat(outcome: String = "victory") -> void:
	in_combat = false
	mode = "realtime"
	result = outcome
	EventBus.realtime = world.get("explore") != null
	# 이기면 쓰러진 캐릭터는 안정 상태로 HP 1이 되어 일어난다(7단계 안정 상태·전투 밖 쓰러짐).
	# 전멸이면 게임 오버라 일으키지 않는다.
	for c: Node in order:
		if outcome != "defeat" and c.is_player_character and c.is_down():
			c.stable = true
			Resolver.heal(c, 1, "combat_end")
		c.remove_condition("surprised")
	if outcome == "victory" and world.has("xp"):
		load("res://scripts/rules/progression.gd").award_defeated(world, order)
	order.clear()
	groups.clear()
	EventBus.on_round_end.emit()


## 적대 생물이 모두 쓰러지거나 이탈하면 끝난다.
func check_end() -> bool:
	if mode != "combat":
		return false
	var party_alive := false
	var foes_alive := false
	for c: Node in order:
		if c.dead or c.is_down():
			continue
		if c.team == "party":
			party_alive = true
		elif c.team == "enemy":
			foes_alive = true
	# 전멸은 활성 파티 전원이 죽거나 쓰러졌을 때(7단계). 구역 밖 파티원이 서 있으면 전투가 이어진다.
	for c: Node in world.get("party", []):
		if not c.dead and not c.is_down():
			party_alive = true
	if not party_alive:
		end_combat("defeat")
		return true
	if not foes_alive:
		end_combat("victory")
		return true
	return false


func _in_zone(c: Node) -> bool:
	var grid: Node = world["grid"]
	for cell in grid.occupied_cells(c):
		if zone in grid.zones(cell):
			return true
	return false


## 구역 밖 파티원이 구역에 들어오면 다음 라운드에 합류. 참가한 적이 구역을 벗어나면 이탈.
func _on_enter_tile(c: Object, _cell: Vector2i) -> void:
	if mode != "combat" or not world["grid"].creatures().has(c):
		return
	if c in order:
		# 이탈은 도주하는 적만(메타 fleeing). 쫓아 나가는 적은 구역 밖에서도 참가자다(9단계 악용 5).
		if c.team == "enemy" and c.get_meta("fleeing", false) and not _in_zone(c):
			leave(c)
	elif _in_zone(c) and c.team == "party" and not c in _pending:
		_pending.append(c)


## 구역 밖에서 공격하는 등 적대 행동을 하면 참가한다(다음 라운드부터).
func notify_hostile_action(c: Node) -> void:
	if mode == "combat" and not c in order and not c in _pending:
		_pending.append(c)


## 전투 중 새로 나타난 생물(소환체 등)은 다음 라운드부터 참가한다.
func add_participant(c: Node) -> void:
	if in_combat and not c in order and not c in _pending:
		_pending.append(c)


func leave(c: Node) -> void:
	order.erase(c)
	for g: Array in groups:
		g.erase(c)
	check_end()


# ======================================================================
# 턴
# ======================================================================

func current_group() -> Array:
	if group_index >= groups.size():
		return []
	return groups[group_index].filter(func(c: Node) -> bool: return not c.dead and not _done.has(c))


func is_current(c: Node) -> bool:
	return c in current_group()


func _begin_group() -> void:
	_done.clear()
	while group_index < groups.size():
		var alive: Array = groups[group_index].filter(func(c: Node) -> bool: return not c.dead)
		if not alive.is_empty():
			for c: Node in alive:
				begin_turn(c)
			# 턴 시작 처리 중 모두 죽거나 끝났으면 다음 묶음으로
			if not current_group().is_empty() or not in_combat:
				return
		group_index += 1
	_end_round()


## 턴 시작(3단계 턴 순서 2): 반응 회복 → 턴 시작 효과(표면·연소) → 사망 내성 → 재충전 쿨다운 −1.
func begin_turn(c: Node) -> void:
	c.refresh_reaction()
	for other: Node in world["grid"].creatures():
		for m in other.extra_modifiers.duplicate():
			if m.get("until_turn_start_of") == c:
				other.extra_modifiers.erase(m)
	c.reset_turn()
	if world.get("surfaces") != null:
		world["surfaces"].creature_turn_start(c)
	Resolver.start_turn(c, {"in_combat": in_combat})
	load("res://scripts/rules/spellcasting.gd").on_turn_start(world, c)
	for k: String in c.cooldowns.keys():
		c.cooldowns[k] = maxi(int(c.cooldowns[k]) - 1, 0)
	if not c.has_flag("cannot_act"):
		c.reset_turn()  # 턴 시작 효과로 바뀐 상태(넘어짐·연소 등)를 반영
		c.turn["movement"] = c.speed()
		for m in c.modifier_entries():
			var e: Dictionary = m["effect"]
			if e["type"] == "grant_action" and e.get("action", "") == "haste_action" and not c.is_incapacitated():
				c.turn["action"] = int(c.turn.get("action", 0)) + 1  # Haste: 추가 행동(공격 1회·질주·이탈·숨기·활용)
				c.turn["surge_actions"] = int(c.turn.get("surge_actions", 0)) + 1


## 턴 끝(3단계 턴 순서 4): 턴 종료 효과 → 상태 지속시간 감소. 기습은 첫 턴이 끝나면 풀린다.
func end_turn(c: Node) -> void:
	EventBus.on_turn_end.emit(c)
	# 분노(원문): 이번 턴에 적을 공격·내성 강요·분노 연장을 하지 않았거나 무력화면 끝난다
	if c.has_condition("raging") and (not c.turn.get("rage_kept", false) or c.is_incapacitated()):
		c.remove_condition("raging")
		Dice.log_text("%s: 분노가 끝났다" % c.label())
	if c.dead and not c.has_meta("died_round"):
		c.set_meta("died_round", round_number)
	c.tick_conditions()
	c.remove_condition("surprised")
	for m in c.extra_modifiers.duplicate():
		if m.has("turn_ends_left"):
			m["turn_ends_left"] -= 1
			if m["turn_ends_left"] <= 0:
				c.extra_modifiers.erase(m)
	for other: Node in world["grid"].creatures():
		for m in other.extra_modifiers.duplicate():
			if m.get("expires_after_turn_end_of") == c:
				m["turn_end_count"] = int(m.get("turn_end_count", 1)) - 1
				if m["turn_end_count"] <= 0:
					other.extra_modifiers.erase(m)
	load("res://scripts/rules/spellcasting.gd").on_turn_end(world, c)
	_done[c] = true
	if not in_combat:
		return
	if mode == "combat" and check_end():
		return
	if current_group().is_empty():
		group_index += 1
		_begin_group()


func _end_round() -> void:
	EventBus.on_round_end.emit()
	if world.get("surfaces") != null:
		world["surfaces"].end_round()
	round_number += 1
	for c: Node in _pending:
		if not c.dead:
			roll_initiative(c)
			c.refresh_reaction()
			order.append(c)
	_pending.clear()
	order = order.filter(func(c: Node) -> bool: return not c.dead)
	_sort_order()
	if mode == "combat" and check_end():
		return
	EventBus.on_round_start.emit()
	group_index = 0
	_begin_group()


# ======================================================================
# 실시간
# ======================================================================

## 탐험 중 6초 틱: 모든 생물에게 턴 시작·끝 처리, 표면 라운드 끝(3단계 라운드 시간).
func tick() -> void:
	if in_combat:
		return
	EventBus.on_round_start.emit()
	for c: Node in world["grid"].creatures():
		if c.dead:
			continue
		begin_turn(c)
		EventBus.on_turn_end.emit(c)
		c.tick_conditions()
	if world.get("surfaces") != null:
		world["surfaces"].end_round()
	EventBus.on_round_end.emit()
