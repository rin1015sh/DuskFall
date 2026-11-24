extends RefCounted
## 위치·물리 상호작용(상태 없음). 룰북 3단계 밀치기, 4단계 '위치·물리 상호작용', 2단계 낙하 피해.

const Resolver := preload("res://scripts/rules/resolver.gd")

## 밀 수 있는 무게 = 근력 점수 × 12kg(3단계).
const SHOVE_KG_PER_STR := 12
## 무게 비율 → 밀리는 칸: 25% 이하 4, 50% 이하 3, 75% 이하 2, 그 이상 1.
const SHOVE_BANDS := [[0.25, 4], [0.5, 3], [0.75, 2]]
## 낙하(BG3 — bg3.wiki Falling damage): 높이 1단계 = 1.5m. 4m 미만은 피해 없음,
## 그 이상은 (최대 HP + 임시 HP) × (높이 − 4) / 17 + 1, 최대 HP의 25%를 넘는 피해면 넘어진다.
const FALL_STEP_M := 1.5
const FALL_SAFE_M := 4.0
const FALL_PRONE_RATIO := 0.25


# ---------- 밀치기 ----------

## 밀치기 계획(굴림 없음). 결과: {"valid", "reason", "distance", "path", "landing", "fall_levels", "dc"}
static func plan_shove(grid: Node, shover: Node, target: Node, limit_mult: float = 1.0) -> Dictionary:
	# BG3 판정: 미는 쪽 운동 판정 vs 대상 수동 운동·곡예 중 높은 쪽(10 + 기능, 유리 +5·불리 −5)
	var dc := maxi(Resolver.passive_skill(target, "str", "athletics"), Resolver.passive_skill(target, "dex", "acrobatics"))
	var out := {"valid": false, "reason": "", "distance": 0, "path": [], "landing": grid.cell_of(target),
		"fall_levels": 0, "dc": dc}
	var limit: float = shover.abilities["str"] * SHOVE_KG_PER_STR * limit_mult  # limit_mult: 거인의 발길질 두 배
	if target.weight_kg > limit:
		out["reason"] = "너무 무겁다(%.0fkg > %.0fkg)" % [target.weight_kg, limit]
		return out
	var ratio: float = target.weight_kg / limit
	var dist := 1
	for band: Array in SHOVE_BANDS:
		if ratio <= band[0]:
			dist = band[1]
			break
	out["distance"] = dist
	var from: Vector2i = grid.cell_of(shover)
	var at: Vector2i = grid.cell_of(target)
	var dir := Vector2i(signi(at.x - from.x), signi(at.y - from.y))
	if dir == Vector2i.ZERO:
		out["reason"] = "방향을 정할 수 없다"
		return out
	var path: Array[Vector2i] = []
	var cur := at
	for i in dist:
		var nxt := cur + dir
		var why := _push_step_blocked(grid, target, cur, nxt)
		if why != "":
			out["reason"] = why  # 중간이 막혀도 밀리지 않는다(changes.md 2026-11-22)
			return out
		path.append(nxt)
		cur = nxt
	out["valid"] = true
	out["path"] = path
	out["landing"] = cur
	out["fall_levels"] = maxi(grid.height(at) - grid.height(cur), 0)
	return out


static func _push_step_blocked(grid: Node, target: Node, cur: Vector2i, nxt: Vector2i) -> String:
	if grid.blocks_movement(nxt):
		return "경로가 막혔다"
	var d := nxt - cur
	if d.x != 0 and d.y != 0:
		if grid._corner_blocks(cur + Vector2i(d.x, 0)) or grid._corner_blocks(cur + Vector2i(0, d.y)):
			return "벽 모서리"
	var other: Node = grid.creature_at(nxt)
	if other != null and other != target:
		return "다른 생물이 있다"
	if grid.height(nxt) > grid.height(cur):
		return "더 높은 칸으로는 밀 수 없다"
	return ""


## 밀치기 미리보기: 성공 확률, 착지 칸, 낙하 단계. 아군은 판정 없이 성공.
static func preview_shove(grid: Node, shover: Node, target: Node, ally: bool = false) -> Dictionary:
	var plan := plan_shove(grid, shover, target)
	if not plan["valid"]:
		plan["chance"] = 0.0
		return plan
	if ally:
		plan["chance"] = 1.0
		return plan
	var bonus: float = shover.ability_mod("str") + Resolver._skill_bonus(shover, "athletics") + Resolver.avg_bonus_dice(shover, "ability_check")
	var p := clampf((21.0 - (plan["dc"] - bonus)) / 20.0, 0.05, 1.0)  # 밀치기는 치명적 실패가 없다
	var mode := 1 if _hidden(shover) else Resolver.check_mode(shover, "str")
	plan["chance"] = Resolver.apply_mode(p, mode)
	return plan


## 숨었거나 투명하면 밀치기 판정 유리(BG3).
static func _hidden(c: Node) -> bool:
	return c.has_condition("invisible")


## 밀치기: 대상이 근력·민첩 중 나은 쪽으로 내성(2단계, 엔진이 자동으로 고른다). 실패하면 밀린다.
static func shove(grid: Node, shover: Node, target: Node, ally: bool = false, limit_mult: float = 1.0) -> Dictionary:
	var plan := plan_shove(grid, shover, target, limit_mult)
	plan["success"] = false
	if not plan["valid"]:
		Dice.log_text("%s → %s 밀치기 불가: %s" % [shover.label(), target.label(), plan["reason"]])
		return plan
	if not ally:
		var r := Resolver.ability_check(shover, "str", int(plan["dc"]), {"skill": "athletics", "other": target,
			"advantage": ["숨음·투명"] if _hidden(shover) else []})
		plan["check"] = r
		if not r["success"] and int(r["total"]) < int(plan["dc"]):
			return plan  # 자연 1이어도 합이 DC 이상이면 성공(밀치기는 치명적 실패가 없다)
	plan["success"] = true
	grid.move_creature(target, plan["landing"])
	if plan["fall_levels"] > 0:
		plan["fall"] = fall(target, plan["fall_levels"])
	return plan


static func _best_save(target: Node) -> String:
	return "str" if target.save_bonus("str") >= target.save_bonus("dex") else "dex"


# ---------- 낙하 ----------

## 낙하. on_fall 훅을 먼저 보내고(리스너가 ctx["prevented"] = true로 막는다), 높이 2단계마다 1d6 타격.
## 피해를 받으면 넘어진다(SRD Falling).
static func fall(creature: Node, levels: int) -> Dictionary:
	var meters := levels * FALL_STEP_M
	var ctx := {"creature": creature, "levels": levels, "meters": meters, "prevented": false}
	for m in creature.modifier_entries():  # 깃털 낙하(BG3 보너스 행동 강화): 낙하 피해 면역
		var e: Dictionary = m["effect"]
		if e.get("type") == "modify" and e.get("stat") == "fall_damage" and int(e.get("set", 1)) == 0:
			ctx["prevented"] = true
	if not ctx["prevented"] and meters >= FALL_SAFE_M:
		EventBus.on_fall.emit(ctx)
	var out := {"levels": levels, "meters": meters, "damage": 0, "prevented": ctx["prevented"]}
	if ctx["prevented"] or meters < FALL_SAFE_M:
		return out
	var amount := fall_damage(creature, levels)
	Dice.log_text("%s 낙하 %.1fm: %d" % [creature.label(), meters, amount])
	if creature.has_cap("slow_fall") and creature.can_react() and creature.reaction_setting("slow_fall") != "off":
		creature.turn["reaction"] = int(creature.turn.get("reaction", 1)) - 1  # 몽크 느린 낙하: 반응, 몽크 레벨 × 5 줄이기
		amount = maxi(0, amount - 5 * creature.feature_level("slow_fall"))
		Dice.log_text("%s 느린 낙하: 낙하 피해 −%d" % [creature.label(), 5 * creature.feature_level("slow_fall")])
	if creature.has_cap("fall_resistance"):
		amount = amount / 2  # 2층 작업(BG3): 낙하 피해 저항
	var dmg := Resolver.apply_damage(creature, [{"amount": amount, "damage_type": "bludgeoning"}], {"in_combat": not EventBus.realtime})
	out["damage"] = dmg["total"]
	if float(dmg["total"]) > FALL_PRONE_RATIO * creature.hp_max and not creature.dead:
		creature.apply_condition("prone", -1)  # BG3: 최대 HP 25%를 넘는 낙하 피해면 넘어진다
	return out


## 낙하 피해(굴림 없음, BG3 공식). 미리보기에도 쓴다.
static func fall_damage(creature: Node, levels: int) -> int:
	var meters := levels * FALL_STEP_M
	if meters < FALL_SAFE_M:
		return 0
	return int(floor(float(creature.hp_max + creature.temp_hp) * (meters - FALL_SAFE_M) / 17.0)) + 1


# ---------- 던지기 ----------

## 던질 수 있는 무게 = 0.2 × 근력 점수² kg(4단계).
static func max_throw_kg(thrower: Node) -> float:
	return 0.2 * thrower.abilities["str"] * thrower.abilities["str"]


## 던지기 사거리(BG3 — bg3.wiki Throw): round(3 + 15 × (근력²/5 − 무게) / (2 × 무게)) m를 3~18m로 자른 뒤
## 칸(1.5m)으로 내린다 → 2~12칸. 물건·투척 소모품·물약·던지는 무기가 모두 이 거리를 쓴다(룰북 3단계 던지기).
static func throw_range_tiles(thrower: Node, weight_kg: float) -> int:
	var s := float(thrower.abilities["str"])
	var w := maxf(weight_kg, 0.01)
	var meters := clampf(roundf(3.0 + 15.0 * (s * s / 5.0 - w) / (2.0 * w)), 3.0, 18.0)
	return int(floor(meters / 1.5 + 0.001))


## 무게 구간별 피해: 10kg 미만 1, 10~50kg 1d4, 50kg 초과 2d4 타격.
static func throw_damage_dice(weight_kg: float) -> String:
	if weight_kg < 10.0:
		return "1"
	if weight_kg <= 50.0:
		return "1d4"
	return "2d4"


## 던진 물체가 생물에 맞았을 때(명중 판정은 3단계 던지기 행동). 대상 무게의 절반을 넘으면 1칸 밀림,
## 대상보다 무거우면 넘어짐.
## deal_damage false: 피해는 공격 굴림(Combat.throw_object)이 이미 넣었다 — 밀림·넘어짐만.
static func throw_hit(grid: Node, thrower: Node, target: Node, weight_kg: float, deal_damage: bool = true) -> Dictionary:
	var out := {"damage": {}, "pushed": false, "prone": false}
	if deal_damage:
		var r := Dice.roll(throw_damage_dice(weight_kg), "던지기 피해")
		out["damage"] = Resolver.apply_damage(target, [{"amount": r["total"], "damage_type": "bludgeoning"}], {"attacker": thrower})
	if target.dead:
		return out
	if weight_kg > target.weight_kg / 2.0:
		var from: Vector2i = grid.cell_of(thrower)
		var at: Vector2i = grid.cell_of(target)
		var nxt := at + Vector2i(signi(at.x - from.x), signi(at.y - from.y))
		if nxt != at and _push_step_blocked(grid, target, at, nxt) == "":
			var drop := maxi(grid.height(at) - grid.height(nxt), 0)
			grid.move_creature(target, nxt)
			out["pushed"] = true
			if drop > 0:
				out["fall"] = fall(target, drop)
	if weight_kg > target.weight_kg:
		target.apply_condition("prone", -1)
		out["prone"] = true
	return out


## 물약 던지기(9단계, BG3): 착지 칸과 직교 인접 4칸 안 생물 모두에게 물약 전체 효과 + 연소 해제.
## 생물을 직접 노리면 그 생물은 던지기 피해 1도 받는다. effects: [{"type": "heal", "dice"}, ...]
## 효과 주사위는 한 번 굴려 모두에게 같게 준다.
static func throw_potion(grid: Node, landing: Vector2i, effects: Array, direct_target: Node = null) -> Array:
	var cells: Array[Vector2i] = [landing]
	for d in grid.DIRS_4:
		cells.append(landing + d)
	var Area := preload("res://scripts/rules/area.gd")
	var hit := Area.creatures_in(grid, cells)
	var rolled := {}
	if direct_target != null:
		Resolver.apply_damage(direct_target, [{"amount": 1, "damage_type": "bludgeoning"}])
	for cr: Node in hit:
		cr.remove_condition("burning")
		for e: Dictionary in effects:
			match e["type"]:
				"heal":
					if not rolled.has(e["dice"]):
						rolled[e["dice"]] = Dice.roll(e["dice"], "물약")["total"]
					Resolver.heal(cr, rolled[e["dice"]])
				"apply_condition":
					cr.apply_condition(e["id"])
				"remove_condition":
					cr.remove_condition(e["id"])
	return hit
