extends RefCounted
## 주문 시전(룰북 6단계 공통 변환 + 주문 변환표). spells.json의 효과 모델을 읽는다:
## check(attack | save) → hit / fail / success, 그리고 apply. 표현이 안 되는 주문은 "script"로 넘긴다.
##
## 시전 하나 = 주문 인스턴스 하나. 그 시전이 남긴 효과(상태·수정치·표면·구름·광원·값 변경)를 기록해 두었다가
## 집중이 깨지거나 지속시간이 끝나면 end_instance로 한꺼번에 걷어낸다.
## 지속: 즉시 = 1턴(상태가 있을 때), N턴, 긴 휴식까지 = -1(7단계 휴식이 끝낸다).

const Resolver := preload("res://scripts/rules/resolver.gd")
const Area := preload("res://scripts/rules/area.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const DiceExpr := preload("res://scripts/rules/dice_expr.gd")

static var _next_id := 1
## 인스턴스 ID → {"id", "spell", "caster", "world", "slot", "targets": [], "reverts": [], "auras": []}
static var instances := {}


static func spell_mod(c: Node) -> int:
	var ab := str(c.get_meta("casting_ability", c.spellcasting_ability))  # 멀티클래스: 시전 중인 주문의 클래스 능력
	return c.ability_mod(ab) if ab != "" else 0


## 그 주문을 준비한 클래스의 시전 능력(멀티클래스 — 없으면 주 시전 능력).
static func ability_for(c: Node, spell_id: String) -> String:
	var cid := str(c.spell_class.get(spell_id, ""))
	if cid == "" and c.get_meta("spell_ability", {}).has(spell_id):
		return str(c.get_meta("spell_ability")[spell_id])  # 재주 주문(마법 입문 목록 능력, 의식 주문가·주문 저격)
	if cid != "":
		var ab := str(RulesDB.get_entry("class", cid).get("spellcasting", {}).get("ability", ""))
		if ab != "":
			return ab
	return c.spellcasting_ability


static func spell_dc(c: Node) -> int:
	if c.has_meta("scroll_cast"):
		return int(c.get_meta("scroll_cast")["dc"])  # 주문 두루마리: 두루마리 DC(SRD)
	var add := 0
	for m in c.modifier_entries():
		if m["effect"]["type"] == "modify" and m["effect"]["stat"] == "spell_dc":
			add += int(m["effect"].get("add", 0))  # 타고난 마법(소서러) +1
	return 8 + c.proficiency_bonus + spell_mod(c) + add


static func spell_attack_bonus(c: Node) -> int:
	if c.has_meta("scroll_cast"):
		return int(c.get_meta("scroll_cast")["attack"])
	return c.proficiency_bonus + spell_mod(c)


## 타고난 시전(재주·종족 주문): 슬롯 없이 긴 휴식마다 1회 — 자원 innate_<주문 id>
static func innate_id(spell_id: String) -> String:
	return "innate_" + spell_id


static func duration_turns(spell: Dictionary) -> int:
	match spell["duration"]["type"]:
		"turns":
			return int(spell["duration"]["turns"])
		"instant":
			return 1
	return -1


static func _cost(spell: Dictionary) -> String:
	match spell["cast"]["cost"]:
		"bonus_action":
			return "bonus"
		"reaction":
			return "reaction"
		"explore":
			return "explore"
		"attack":
			return "attack"  # 강타(BG3): 공격 행동의 공격 하나 — 스크립트가 Combat.attack으로 쓴다
	return "action"


## 주문 변형(소서러 메타매직, 설정 options.metamagic — 다음 주문 한 번에 쓰고 꺼진다). 값 = 마법 점수.
## 능력 태그 metamagic_<id>(고른 변형)가 있어야 한다. 점수는 BG3(bg3.wiki Metamagic, 2026-11-24): 빠른·고양 3, 나머지 1,
## 쌍둥이는 슬롯 레벨(소마법 1 — metamagic_points). 추적은 일반 선택지가 아니다(장비·기능 태그로만).
const METAMAGIC := {"quickened": 3, "distant": 1, "heightened": 3, "extended": 1, "careful": 1, "subtle": 1, "seeking": 1, "twinned": 1}


## 변형에 드는 마법 점수(쌍둥이: 슬롯 레벨, 소마법 1).
static func metamagic_points(m: String, spell: Dictionary, slot: int) -> int:
	if m == "twinned":
		return 1 if int(spell.get("level", 0)) == 0 else maxi(1, slot)
	return int(METAMAGIC.get(m, 0))


static func metamagic_for(caster: Node, spell: Dictionary) -> String:
	var m := str(caster.options.get("metamagic", "none"))
	if not METAMAGIC.has(m) or not caster.has_cap("metamagic_" + m) \
			or caster.resource("sorcery_points") < metamagic_points(m, spell, int(spell.get("level", 0))):
		return ""
	match m:
		"twinned":
			# 한 생물만 노리는 주문(범위·자신·여러 대상 주문 제외)
			return m if spell.get("area") == null and str(spell["range"]["type"]) in ["tiles", "touch"] \
				and max_targets(spell, int(spell.get("level", 0))) == 1 else ""
		"quickened":
			return m if str(spell["cast"]["cost"]) == "action" else ""
		"distant":
			return m if str(spell["range"]["type"]) in ["tiles", "touch"] else ""
		"heightened":
			return m if str(spell.get("effects", {}).get("check", {}).get("type", "")) == "save" else ""
		"extended":
			return m if str(spell["duration"]["type"]) == "turns" and int(spell["duration"].get("turns", 0)) >= 10 else ""
		"careful":
			return m if str(spell.get("effects", {}).get("check", {}).get("type", "")) == "save" and spell.get("area") != null else ""
		"subtle":
			return m if spell.get("components", {}).get("verbal", false) or spell.get("components", {}).get("somatic", false) else ""
		"seeking":
			return m if str(spell.get("effects", {}).get("check", {}).get("type", "")) == "attack" else ""
	return ""


## 신중한 주문(BG3): 범위 안 아군 모두(시전자 제외) 자동 성공.
static func _careful_targets(caster: Node, targets: Array) -> Array:
	return targets.filter(func(t: Node) -> bool: return t != caster and not t.is_hostile_to(caster))


## 쌍둥이 주문의 두 번째 대상: opts.targets[1](직접 고름) 또는 첫 대상과 같은 편 중 첫 대상에 가장 가까운 생물
## (여러 대상 고르기 화면이 없어 자동 — 룰북 6단계 [변형]). 사거리·시야 안이어야 한다. 없으면 null.
static func _twin_target(world: Dictionary, caster: Node, spell: Dictionary, aim: Vector2i, opts: Dictionary) -> Node:
	var grid: Node = world["grid"]
	var given: Array = opts.get("targets", [])
	var first: Node = given[0] if not given.is_empty() else grid.creature_at(aim)
	if first == null:
		return null
	var rt := range_tiles(spell)
	var ok := func(o: Node) -> bool:
		return o != first and not o.dead and o.is_hostile_to(caster) == first.is_hostile_to(caster) \
			and grid.distance_between(caster, o) <= grid.effective_range(caster, grid.cell_of(o), rt) \
			and (o == caster or grid.has_line_of_sight(grid.cell_of(caster), grid.cell_of(o)) or spell.get("no_sight", false))
	if given.size() >= 2:
		return given[1] if ok.call(given[1]) else null
	var best: Node = null
	for o: Node in grid.creatures():
		if ok.call(o) and (best == null or grid.distance_between(o, first) < grid.distance_between(best, first)):
			best = o
	return best


## 내성 효과에서 보호할 아군: 신중한 주문(소서러) + 주문 조각(능력 태그 sculpt_spells — 방출학파 6레벨: 방출학파 주문, 1 + 주문 레벨명).
static func _protected_targets(caster: Node, spell: Dictionary, targets: Array, opts: Dictionary) -> Array:
	var out: Array = _careful_targets(caster, targets) if opts.get("metamagic", "") == "careful" else []
	if caster.has_cap("sculpt_spells") and str(spell.get("school", "")) == "evocation":
		var allies: Array = targets.filter(func(t: Node) -> bool: return not t in out and (t == caster or not t.is_hostile_to(caster)))
		out.append_array(allies)  # 주문 조각(BG3): 방출학파 주문의 아군 모두 자동 성공·피해 없음
	return out


## 빠른 주문이면 행동 → 보너스 행동.
static func _mm_cost(caster: Node, spell: Dictionary) -> String:
	if metamagic_for(caster, spell) == "quickened":
		return "bonus"
	if str(spell.get("id", "")) in caster.get_meta("bonus_action_spells", []):
		return "bonus"  # 향상된 하급 환영(환영학파): 보너스 행동
	return _cost(spell)


static func _dur(spell: Dictionary, opts: Dictionary) -> int:
	var d := duration_turns(spell)
	return d * int(opts.get("duration_mult", 1)) if d > 0 else d


static func range_tiles(spell: Dictionary) -> int:
	match spell["range"]["type"]:
		"tiles":
			return int(spell["range"]["tiles"])
		"touch":
			return 1
	return 0


## 소마법 강화(BG3 5·10레벨)와 상위 슬롯(레벨당 dice_add)을 반영한 주사위.
static func scaled_dice(c: Node, spell: Dictionary, dice: String, slot: int) -> String:
	var out := dice
	var cs: Dictionary = spell.get("upcast", {}).get("cantrip_scaling", {})
	var best_lv := 0
	for lv: String in cs.keys():
		if c.level >= int(lv) and int(lv) > best_lv:
			best_lv = int(lv)
			out = cs[lv]
	var psl: Dictionary = spell.get("upcast", {}).get("per_slot_level", {})
	var extra: int = slot - int(spell["level"])
	if extra > 0 and psl.has("dice_add") and int(spell["level"]) > 0:
		var add := DiceExpr.parse(psl["dice_add"])
		var base := DiceExpr.parse(out)
		if not add.is_empty() and not base.is_empty() and not base["dice"].is_empty() \
				and base["dice"][0]["sides"] == add["dice"][0]["sides"]:
			var n: int = base["dice"][0]["count"] + add["dice"][0]["count"] * extra
			out = "%dd%d%s" % [n, base["dice"][0]["sides"], ("%+d" % base["flat"]) if base["flat"] != 0 else ""]
	return out


## 주문 피해 주사위 = 올려 쓴 주사위 + 기능 보너스(강력한 주문 시전: 소마법 + 주문 능력, 강화된 방출: 방출학파 + 주문 능력).
static func damage_dice(c: Node, spell: Dictionary, dice: String, slot: int, dtype: String = "") -> String:
	var out := scaled_dice(c, spell, dice, slot)
	var b := damage_bonus(c, spell, dtype)
	return out + ("%+d" % b) if b != 0 else out


## 기능 cast_trigger {spells, aura_condition, turns}: 그 주문을 시전하면 오라 안 자신·아군에게 상태.
static func _cast_triggers(world: Dictionary, caster: Node, spell_id: String) -> void:
	for f: Dictionary in caster.feature_data.values():
		var ct: Dictionary = f.get("cast_trigger", {})
		if ct.is_empty() or not spell_id in ct.get("spells", []) or not world.has("grid"):
			continue
		var grid: Node = world["grid"]
		var rng: int = maxi(1, load("res://scripts/rules/auras.gd").range_of(caster))
		for o: Node in grid.creatures():
			if not o.dead and not o.is_hostile_to(caster) and (o == caster or grid.distance_between(caster, o) <= rng):
				o.apply_condition(str(ct["aura_condition"]), int(ct.get("turns", 1)), caster)


## 원소 친화(소서러 용의 혈통 6레벨 — 생물 meta spell_type_bonus): 그 피해 종류 주문 + 주문 능력 수정치.
static func damage_bonus(c: Node, spell: Dictionary, dtype: String = "") -> int:
	var n := 0
	if dtype != "" and dtype in c.get_meta("spell_type_bonus", []):
		n += spell_mod(c)
	if int(spell.get("level", 0)) == 0 and c.has_cap("cantrip_add_mod"):
		n += spell_mod(c)
	if str(spell.get("school", "")) == "evocation" and c.has_cap("evocation_add_mod"):
		n += spell_mod(c)
	return n


## 여러 대상 고르기(BG3식 — 대상을 하나씩 클릭해 모으고, 다 차면 바로 시전, 그 전에는 확정으로 시전).
## 결과 {"count": 고를 수(0 = 확정할 때까지 — 수면처럼 총량으로 제한), "kind": "creature" | "cell", "repeat": 같은 생물 여러 번}.
## count 1이면 보통 시전(한 번 클릭). opts.targets(생물 목록) / opts.second_cell(칸 둘째)로 cast에 넘긴다.
static func target_plan(caster: Node, spell_id: String, slot: int = -1) -> Dictionary:
	var spell := RulesDB.get_entry("spell", spell_id)
	var one := {"count": 1, "kind": "creature", "repeat": false}
	if spell.is_empty() or spell.get("area") != null or str(spell["range"]["type"]) == "self":
		return one
	if slot < 0:
		slot = int(spell["level"])
	match str(spell.get("script", "")):
		"split_darts":
			return {"count": 3 + maxi(slot - 1, 0), "kind": "creature", "repeat": true}
		"split_rays":
			return {"count": 3 + maxi(slot - 2, 0), "kind": "creature", "repeat": true}
		"eldritch_blast":
			return {"count": 3 if caster.level >= 10 else (2 if caster.level >= 5 else 1), "kind": "creature", "repeat": true}
		"twin_gate":
			return {"count": 2, "kind": "cell", "repeat": false}
		"hp_pool":
			return {"count": 0, "kind": "creature", "repeat": false}
	var n := max_targets(spell, slot)
	if metamagic_for(caster, spell) == "twinned":
		n += 1
	return {"count": n, "kind": "creature", "repeat": false} if n > 1 else one


static func max_targets(spell: Dictionary, slot: int) -> int:
	var n := int(spell.get("targets_max", 1))
	var extra: int = int(spell.get("upcast", {}).get("per_slot_level", {}).get("extra_targets", 0))
	return n + extra * maxi(slot - int(spell["level"]), 0)


# ======================================================================
# 범위·대상
# ======================================================================

## 범위 칸. 구·원기둥은 조준 칸 중심, 원뿔·선·정육면체는 시전자에서 조준 방향, 발산은 시전자 칸.
## 범위 칸: 매끄러운 도형에 PARTIAL 이상 덮인 칸(걸친 칸도 그냥 맞는다 — 엄폐 보너스 없음).
static func area_cells(world: Dictionary, caster: Node, spell: Dictionary, aim: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Vector2i in area_coverage(world, caster, spell, aim):
		out.append(c)
	return out


## 칸 → 덮인 비율(원·원뿔·선은 매끄러운 도형, 정육면체·정사각형은 칸 그대로 1.0)
static func area_coverage(world: Dictionary, caster: Node, spell: Dictionary, aim: Vector2i) -> Dictionary:
	var grid: Node = world["grid"]
	var a: Variant = spell.get("area")
	if a == null:
		return {}
	var from: Vector2i = grid.cell_of(caster)
	var aim_pt := Vector2(aim) + Vector2(0.5, 0.5)
	match a["shape"]:
		"sphere", "cylinder":
			return Area.cov_circle(grid, aim, int(a["radius_tiles"]))
		"emanation":
			return Area.cov_circle(grid, from, int(a["radius_tiles"]))
		"cone":
			return Area.cov_cone(grid, from, aim_pt, int(a["length_tiles"]))
		"line":
			return Area.cov_line(grid, from, aim_pt, int(a["length_tiles"]), 0.5 * int(a.get("width_tiles", 1)))
	var out := {}
	for c: Vector2i in _area_cells_grid(world, caster, spell, aim):
		out[c] = 1.0
	return out


## 미리보기용 도형(화면이 매끄러운 윤곽을 그린다). 칸 좌표(칸 가운데 = +0.5).
static func area_shape(world: Dictionary, caster: Node, spell: Dictionary, aim: Vector2i) -> Dictionary:
	var a: Variant = spell.get("area")
	if a == null:
		return {}
	var from := Vector2(world["grid"].cell_of(caster)) + Vector2(0.5, 0.5)
	var aim_pt := Vector2(aim) + Vector2(0.5, 0.5)
	match a["shape"]:
		"sphere", "cylinder":
			return {"type": "circle", "center": aim_pt, "r": int(a["radius_tiles"]) + 0.5}
		"emanation":
			return {"type": "circle", "center": from, "r": int(a["radius_tiles"]) + 0.5}
		"cone":
			return {"type": "cone", "apex": from, "dir": (aim_pt - from).normalized(), "len": int(a["length_tiles"]) + 0.5, "half": Area.CONE_HALF}
		"line":
			return {"type": "line", "a": from, "dir": (aim_pt - from).normalized(), "len": int(a["length_tiles"]) + 0.5, "half_w": 0.5 * int(a.get("width_tiles", 1))}
	return {}


static func _area_cells_grid(world: Dictionary, caster: Node, spell: Dictionary, aim: Vector2i) -> Array[Vector2i]:
	var grid: Node = world["grid"]
	var a: Variant = spell.get("area")
	var out: Array[Vector2i] = []
	var from: Vector2i = grid.cell_of(caster)
	var dir := Vector2i(signi(aim.x - from.x), signi(aim.y - from.y))
	match a["shape"]:
		"cube":
			if spell["range"]["type"] == "self":
				return Area.cube_from(grid, from, dir, int(a["size_tiles"]))
			return Area.square(grid, aim - Vector2i(int(a["size_tiles"]) / 2, int(a["size_tiles"]) / 2), int(a["size_tiles"]), from)
		"square":
			return Area.square(grid, aim, int(a["size_tiles"]), from)
	return out


## 대상: 범위 주문은 범위 안 생물, 아니면 opts.targets(여러 대상) 또는 조준 칸의 생물, '자신'이면 시전자.
static func targets_for(world: Dictionary, caster: Node, spell: Dictionary, aim: Vector2i, cells: Array, opts: Dictionary, slot: int) -> Array:
	var grid: Node = world["grid"]
	if spell.get("area") != null:
		var hostile_only: bool = spell["effects"].has("check")
		var allies_only: bool = str(spell.get("area_targets", "")) == "allies"  # 아군만(생명의 오라·집단 상처 치료)
		var enemies_only: bool = str(spell.get("area_targets", "")) == "enemies"  # 적만(분쇄의 파동 — BG3)
		var found: Array = Area.creatures_in(grid, cells).filter(func(c: Node) -> bool:
			return not c.dead and (c != caster or not hostile_only) and (not allies_only or not c.is_hostile_to(caster)) \
				and (not enemies_only or c.is_hostile_to(caster)))
		return found.slice(0, max_targets(spell, slot)) if spell.has("targets_max") and allies_only else found
	if spell["range"]["type"] == "self":
		return [caster]
	var list: Array = opts.get("targets", [])
	if list.is_empty():
		var t: Node = grid.creature_at(aim)
		if t != null:
			list = [t]
	return list.slice(0, max_targets(spell, slot))


# ======================================================================
# 시전 가능·미리보기
# ======================================================================

## 의식(룰북 6단계 공통 변환): 의식 주문은 탐험 중(실시간, 전투 밖)에 슬롯 없이 즉시 시전, 전투 중에는 슬롯을 쓴다.
static func ritual_free(world: Dictionary, spell: Dictionary, opts: Dictionary = {}) -> bool:
	return bool(spell.get("cast", {}).get("ritual", false)) and int(spell.get("level", 0)) > 0 and not opts.has("slot") \
		and EventBus.realtime and not (world.get("turns") != null and world["turns"].in_combat)


## 능력 태그 ritual_from_spellbook(의식 숙련): 주문서의 의식 주문은 준비하지 않아도 의식으로 시전한다.
static func ritual_from_book(world: Dictionary, caster: Node, spell_id: String) -> bool:
	var spell := RulesDB.get_entry("spell", spell_id)
	return caster.has_cap("ritual_from_spellbook") and spell_id in caster.spellbook and ritual_free(world, spell)


## 다시 쓸 수 있는 살아 있는 인스턴스(주문 데이터 recast {"cost"}) — 같은 시전자·같은 주문. 없으면 {}.
static func recast_instance(caster: Node, spell_id: String) -> Dictionary:
	var spell := RulesDB.get_entry("spell", spell_id)
	if not spell.has("recast"):
		return {}
	_prune()
	for inst: Dictionary in instances.values():
		if inst["spell"] == spell_id and inst["caster"] == caster:
			if inst.get("concentration", false) and int(caster.concentration.get("instance", -1)) != int(inst["id"]):
				continue
			return inst
	return {}


static func can_cast(world: Dictionary, caster: Node, spell_id: String, aim: Vector2i, opts: Dictionary = {}) -> String:
	var spell := RulesDB.get_entry("spell", spell_id)
	if not opts.get("fresh", false) and not recast_instance(caster, spell_id).is_empty():
		var rc := str(spell["recast"].get("cost", "action")).replace("bonus_action", "bonus")
		if caster.has_condition("incapacitated"):
			return "무력화"
		return "" if Combat.can_spend(caster, rc) else "비용이 없다"
	if spell.is_empty() or not (caster.spells.has(spell_id) or ritual_from_book(world, caster, spell_id) or opts.get("granted", false)):
		return "모르는 주문"  # granted: 기능이 주는 한 번의 시전(전투 시전자 기회 공격 — 전격 손길)
	if ritual_free(world, spell, opts) or spell_id in caster.get_meta("at_will", []) or free_cast_feature(caster, spell) != "":
		opts = opts.duplicate()
		opts["no_slot"] = true
	if spell["game_status"] != "included":
		return "1차 제외 주문"
	if spell.has("script"):
		var inst: Object = load("res://scripts/rules/features.gd").script_for(spell["script"])
		if inst == null or not inst.is_implemented():
			return "아직 구현하지 않은 주문"
	var cost := _mm_cost(caster, spell)
	if opts.get("free", false):
		pass  # 불러오기로 다시 거는 주문(저장된 지속 주문) — 비용·슬롯 없음
	elif cost == "explore":
		if world.get("turns") != null and world["turns"].in_combat:
			return "탐험 중에만"
	elif cost == "attack":
		if int(caster.turn.get("attacks_left", 0)) <= 0 and not Combat.can_spend(caster, "action"):
			return "비용이 없다"
	elif not Combat.can_spend(caster, cost):
		return "비용이 없다"
	if cost == "action" and not opts.get("free", false) and int(caster.turn.get("action", 0)) <= int(caster.turn.get("surge_actions", 0)):
		return "행동 연쇄로 얻은 행동은 주문에 쓸 수 없다"
	if int(spell["level"]) > 0 and not opts.get("no_slot", false) and not opts.get("free", false) and _slot(caster, int(opts.get("slot", spell["level"]))) == "" \
			and caster.resource(innate_id(spell_id)) <= 0:
		return "주문 슬롯이 없다"
	if caster.has_condition("incapacitated"):
		return "무력화"
	if caster.has_flag("no_spellcasting") and not _beast_spells(caster):
		return "지금은 주문을 쓸 수 없다(숙련 없는 갑옷·분노·야생 변신)"
	if spell.get("components", {}).get("verbal", false) and metamagic_for(caster, spell) != "subtle" and world.has("grid") and world["grid"].creatures().has(caster) \
			and world["grid"].has_flag(world["grid"].cell_of(caster), "silence"):
		return "침묵 구역에서는 음성 구성 요소 주문을 쓸 수 없다"
	var grid: Node = world["grid"]
	if spell["range"]["type"] in ["tiles", "touch"]:
		var rt := range_tiles(spell)
		if metamagic_for(caster, spell) == "distant":
			rt = 6 if spell["range"]["type"] == "touch" else rt + rt / 2  # 원거리 주문(BG3): 사거리 +50%, 접촉·근접은 9m(6칸)
		if grid.distance(grid.cell_of(caster), aim) > grid.effective_range(caster, aim, rt):
			return "사거리 밖"
		if not grid.has_line_of_sight(grid.cell_of(caster), aim) and not spell.get("no_sight", false):
			return "보이지 않는다"  # no_sight: 보이지 않는 곳도(차원 문)
	return ""


## 주문 금지 상태 검사: 상태 데이터 lifted_by_cap의 능력 태그가 있으면 그 상태의 금지는 무시한다.
static func _beast_spells(c: Node) -> bool:
	for a in c.active_conditions():
		if a["def"].get("flags", {}).get("no_spellcasting", false) and not c.has_cap(str(a["def"].get("lifted_by_cap", "-"))):
			return false
	return true


## 능력 태그 free_cast_class_spell(신성 개입 — 클레릭 10레벨): 설정을 켜 두면 다음 그 클래스 주문(1 ~ max_spell_level, 반응 주문 제외)을
## 슬롯 없이 자원 1회로 시전하고 설정이 꺼진다(BG3식 토글 — 주문 변형과 같은 방식). 해당 기능 id, 없으면 "".
static func free_cast_feature(c: Node, spell: Dictionary) -> String:
	if int(spell.get("level", 0)) < 1 or _cost(spell) == "reaction":
		return ""
	for fid: String in c.feature_data:
		var f: Dictionary = c.feature_data[fid]
		if not "free_cast_class_spell" in f.get("caps", []) or str(c.options.get(fid, "off")) != "on":
			continue
		if c.resource(str(f.get("resource", ""))) <= 0 or int(spell["level"]) > int(f.get("max_spell_level", 5)):
			continue
		if str(f.get("free_cast_from", "")) == "subclass":
			if spell["id"] in c.get_meta("subclass_spells", []):
				return fid  # 자연 회복(대지 회합 6레벨): 회합 주문 하나
			continue
		var cls := RulesDB.get_entry("class", str(c.feature_class.get(fid, c.class_id)))
		if str(cls.get("spellcasting", {}).get("list", "")) in spell.get("classes", []):
			return fid
	return ""


## 그 레벨 이상에서 가장 낮은 남은 슬롯(주문 슬롯, 멀티클래스면 계약 마법 슬롯 pact_slot_N도 — SRD).
static func _slot(c: Node, level: int) -> String:
	for lv in range(maxi(level, 1), 10):
		for key: String in ["spell_slot_%d", "pact_slot_%d"]:
			if c.resource(key % lv) > 0:
				return key % lv
	return ""


## 미리보기: 대상별 명중·실패 확률, 범위 칸, 칸 반응.
static func preview(world: Dictionary, caster: Node, spell_id: String, aim: Vector2i, opts: Dictionary = {}) -> Dictionary:
	var spell := RulesDB.get_entry("spell", spell_id)
	var why := can_cast(world, caster, spell_id, aim, opts)
	var out := {"valid": why == "", "reason": why, "cells": [] as Array[Vector2i], "targets": [], "reactions": []}
	if spell.is_empty():
		return out
	var cov := area_coverage(world, caster, spell, aim)
	out["cells"] = area_cells(world, caster, spell, aim)
	out["partial"] = cov.keys().filter(func(c: Vector2i) -> bool: return float(cov[c]) < Area.FULL)
	out["shape"] = area_shape(world, caster, spell, aim)
	var slot := int(opts.get("slot", spell["level"]))
	var check: Dictionary = spell["effects"].get("check", {})
	for t: Node in targets_for(world, caster, spell, aim, out["cells"], opts, slot):
		var row := {"creature": t}
		if check.get("type") == "attack":
			row["chance"] = Resolver.preview_attack(caster, t, _spell_attack(caster, spell, slot), world["grid"].attack_context(caster, t)).get("hit_chance", 0.0)
		elif check.get("type") == "save":
			row["chance"] = Resolver.preview_save_fail(t, check["ability"], spell_dc(caster))
		out["targets"].append(row)
	var dtype := _area_damage_type(spell)
	if dtype != "" and not out["cells"].is_empty() and world.get("surfaces") != null:
		out["reactions"] = world["surfaces"].preview_tile_damage(out["cells"], dtype)
	return out


static func _spell_attack(caster: Node, spell: Dictionary, slot: int) -> Dictionary:
	var hit: Array = []
	for e: Dictionary in spell["effects"].get("hit", []):
		if e["type"] == "damage":
			hit.append({"dice": damage_dice(caster, spell, e["dice"], slot, str(e["damage_type"])), "damage_type": e["damage_type"]})
	return {"name": spell["name"]["en"], "bonus": spell_attack_bonus(caster), "weapon": false, "spell": spell["id"],
		"kind": spell["effects"]["check"].get("kind", "ranged"), "damage": hit}


static func _area_damage_type(spell: Dictionary) -> String:
	if spell.get("area") == null:
		return ""
	for e: Dictionary in spell["effects"].get("fail", []) + spell["effects"].get("apply", []):
		if e["type"] == "damage":
			return e["damage_type"]
	return ""


# ======================================================================
# 시전
# ======================================================================

## opts: {"targets": [생물], "slot": 슬롯 레벨, "choice": 선택(피해 유형 등), "mode": ...}
static func cast(world: Dictionary, caster: Node, spell_id: String, aim: Vector2i, opts: Dictionary = {}) -> Dictionary:
	# 시전하는 동안 그 주문 클래스의 능력으로 DC·공격·수정치를 계산한다(멀티클래스)
	var had := caster.has_meta("casting_ability")
	var prev: Variant = caster.get_meta("casting_ability", "")
	caster.set_meta("casting_ability", str(opts.get("ability", ability_for(caster, spell_id))))  # opts ability: 기 주문(몽크 — 지혜)
	caster.set_meta("casting_spell", spell_id)  # 섬뜩한 수확: 이 주문으로 쓰러뜨렸나
	caster.set_meta("casting_slot", int(opts.get("slot", RulesDB.get_entry("spell", spell_id).get("level", 0))))
	var r := _cast(world, caster, spell_id, aim, opts)
	if is_instance_valid(caster) and not opts.get("reaper", false):
		load("res://scripts/rules/sorcery.gd").after_cast(world, caster, RulesDB.get_entry("spell", spell_id), r)  # 소서러 하위 클래스(BG3)
	if is_instance_valid(caster):
		caster.remove_meta("casting_spell")
		caster.remove_meta("casting_slot")
	if r.get("ok", false) and int(RulesDB.get_entry("spell", spell_id).get("level", 0)) == 0 and caster.has_cap("war_magic") and not opts.get("granted", false):
		caster.turn["war_magic_ready"] = true  # 전쟁 마법(엘드리치 나이트형): 소마법을 쓴 턴에 보너스 행동 무기 공격
	if r.get("ok", false) and (caster.has_cap("reaper") or caster.has_cap("split_enchantment")) and not opts.get("reaper", false) and world.has("grid"):
		_reaper(world, caster, spell_id, aim)
	if r.get("ok", false) and int(RulesDB.get_entry("spell", spell_id).get("level", 0)) > 0:
		var sch := str(RulesDB.get_entry("spell", spell_id).get("school", ""))
		if sch == "abjuration" and caster.has_cap("arcane_ward") and caster.resources.has("arcane_ward"):
			caster.resources["arcane_ward"]["current"] = int(caster.resources["arcane_ward"]["current"]) + int(opts.get("slot", RulesDB.get_entry("spell", spell_id)["level"]))  # 비전 결계: 방호학파 주문 레벨만큼
		if sch == "conjuration" and caster.resources.has("benign_transposition"):
			caster.resources["benign_transposition"]["current"] = caster.resources["benign_transposition"]["max"]  # 선한 자리바꿈: 소환학파 주문으로 되찾음
	if had:
		caster.set_meta("casting_ability", prev)
	elif is_instance_valid(caster):
		caster.remove_meta("casting_ability")
	return r


static func world_of(inst: Dictionary) -> Dictionary:
	return inst.get("world", {})


## 별자리 성배(별 회합): 슬롯을 쓴 회복 주문을 쓰면 6칸 안 가장 다친 생물(자신 포함) 1d8(10레벨 2d8) + 지혜 회복.
static func _chalice(world: Dictionary, caster: Node) -> void:
	if not world.has("grid"):
		return
	var grid: Node = world["grid"]
	var best: Node = caster
	for o: Node in grid.creatures():
		if not o.dead and not o.is_hostile_to(caster) and grid.distance_between(caster, o) <= 6 and float(o.hp) / o.hp_max < float(best.hp) / best.hp_max:
			best = o
	var n := 2 if caster.has_cap("twinkling_constellations") else 1
	Resolver.heal(best, Dice.roll("%dd8" % n, "성배 회복")["total"] + caster.ability_mod("wis"), caster)


## 수확자(죽음 영역, 능력 태그 reaper): 한 생물만 노리는 사령술 소마법은 한 생물을 더 — 원래 대상에 가장 가까운 다른 적에게 한 번 더(무료).
static func _reaper(world: Dictionary, caster: Node, spell_id: String, aim: Vector2i) -> void:
	var sp := RulesDB.get_entry("spell", spell_id)
	if sp.get("area") != null or sp.get("range", {}).get("type", "") == "self":
		return
	var reap: bool = caster.has_cap("reaper") and int(sp.get("level", 1)) == 0 and str(sp.get("school", "")) == "necromancy"
	var split: bool = caster.has_cap("split_enchantment") and str(sp.get("school", "")) == "enchantment"  # 갈라진 환혹(환혹학파 10레벨): 한 생물 주문을 둘에게
	if not reap and not split:
		return
	var grid: Node = world["grid"]
	var best: Node = null
	for o: Node in grid.creatures():
		if o.dead or not caster.is_hostile_to(o) or grid.cell_of(o) == aim:
			continue
		if grid.distance(grid.cell_of(caster), grid.cell_of(o)) > range_tiles(sp):
			continue
		if best == null or grid.distance(grid.cell_of(o), aim) < grid.distance(grid.cell_of(best), aim):
			best = o
	if best != null:
		cast(world, caster, spell_id, grid.cell_of(best), {"free": true, "reaper": true})


static func _cast(world: Dictionary, caster: Node, spell_id: String, aim: Vector2i, opts: Dictionary = {}) -> Dictionary:
	var why := can_cast(world, caster, spell_id, aim, opts)
	if why != "":
		return {"ok": false, "reason": why}
	var spell := RulesDB.get_entry("spell", spell_id)
	var level := int(spell["level"])
	var rinst := recast_instance(caster, spell_id) if not opts.get("fresh", false) else {}
	if not rinst.is_empty():  # 다시 쓰기: 슬롯·집중 없이 인스턴스로 발동(BG3 번개 부르기 등)
		Combat.spend(caster, str(spell["recast"].get("cost", "action")).replace("bonus_action", "bonus"))
		Dice.log_text("%s: %s 다시 쓰기" % [caster.label(), spell["name"]["en"]])
		var rctx := {"world": world, "self": caster, "spell": spell, "aim": aim, "opts": opts, "instance": rinst, "slot": int(rinst["slot"])}
		var rr: Dictionary = load("res://scripts/rules/features.gd").script_for(str(spell["script"])).recast(rctx)
		rr["ok"] = rr.get("ok", true)
		rr["recast"] = true
		return rr
	if ritual_free(world, spell, opts):
		opts = opts.duplicate()
		opts["no_slot"] = true
		Dice.log_text("%s: 의식으로 시전(슬롯 없음)" % caster.label())
	if spell_id in caster.get_meta("at_will", []):
		opts = opts.duplicate()
		opts["no_slot"] = true  # 영창의 무료 시전(그림자 갑옷 등)
	var free_fid := free_cast_feature(caster, spell) if not opts.get("no_slot", false) and not opts.get("free", false) else ""
	if free_fid != "":
		opts = opts.duplicate()
		opts["no_slot"] = true
	# 무료 횟수(타고난 시전 innate_<주문> — 선호하는 적·마법 입문)가 남아 있으면 먼저 쓴다(사용자 결정 2026-11-23)
	var use_innate: bool = level > 0 and not opts.get("no_slot", false) and not opts.get("free", false) and not opts.has("slot") \
		and caster.resource(innate_id(spell_id)) > 0
	var slot_id := _slot(caster, int(opts.get("slot", level))) if level > 0 and not use_innate and not opts.get("no_slot", false) and not opts.get("free", false) else ""
	var slot: int = int(slot_id.get_slice("_", 2)) if slot_id != "" else int(opts.get("slot", level))
	var cost := _mm_cost(caster, spell)
	if cost != "explore" and cost != "attack" and not opts.get("free", false):
		Combat.spend(caster, cost)
	var mm := metamagic_for(caster, spell)
	if mm == "twinned" and not opts.get("free", false):
		var twin := _twin_target(world, caster, spell, aim, opts) if world.has("grid") else null
		if twin == null or caster.resource("sorcery_points") < metamagic_points(mm, spell, slot):
			mm = ""  # 두 번째 대상이 없거나 점수가 모자라면 쓰지 않는다(설정은 켜 둔 채)
		else:
			var given: Array = opts.get("targets", [])
			var first: Node = given[0] if not given.is_empty() else world["grid"].creature_at(aim)
			opts = opts.duplicate()
			opts["targets"] = [first, twin]
			spell = spell.duplicate(true)
			spell["targets_max"] = int(spell.get("targets_max", 1)) + 1  # 쌍둥이: 한 생물 더(스크립트 주문도 max_targets로 읽는다)
	if mm != "" and not opts.get("free", false):
		caster.resources["sorcery_points"]["current"] = caster.resource("sorcery_points") - metamagic_points(mm, spell, slot)
		caster.options["metamagic"] = "none"  # 한 번 쓰면 꺼진다(BG3식)
		opts = opts.duplicate()
		opts["metamagic"] = mm
		if mm == "extended":
			opts["duration_mult"] = 2
		Dice.log_text("%s: 주문 변형 — %s" % [caster.label(), mm])
	# 시전 시작(on_spell_cast): Counterspell 같은 반응이 끊을 수 있다. 끊기면 슬롯은 쓰지 않는다(원문).
	var cast_ctx := {"caster": caster, "spell": spell_id, "aim": aim, "slot": slot, "countered": false, "world": world,
		"subtle": opts.get("metamagic", "") == "subtle"}  # 은밀한 주문: 침묵 속에서도 시전(BG3 — 주문 방해는 받는다)
	EventBus.on_spell_cast.emit(cast_ctx)
	_end_on_cast(caster)
	if cast_ctx["countered"]:
		Dice.log_text("%s의 %s가 끊겼다" % [caster.label(), spell["name"]["en"]])
		return {"ok": true, "countered": true}
	if free_fid != "":
		caster.spend_resource(str(caster.feature_data[free_fid]["resource"]))
		caster.options[free_fid] = "off"  # 한 번 쓰면 꺼진다
		Dice.log_text("%s: %s — 슬롯 없이 시전" % [caster.label(), caster.feature_data[free_fid]["name"]["ko"]])
	if slot_id != "":
		caster.spend_resource(slot_id)
	elif use_innate:
		caster.spend_resource(innate_id(spell_id))  # 타고난 시전 1회
	Dice.log_text("%s: %s%s" % [caster.label(), spell["name"]["en"], " (%d레벨 슬롯)" % slot if slot > level else ""])
	_cast_triggers(world, caster, spell_id)
	var inst := new_instance(world, caster, spell, slot)
	if spell["concentration"]:
		caster.start_concentration(spell_id, {"instance": inst["id"], "turns_left": _dur(spell, opts),
			"advantage": opts.get("metamagic", "") == "extended"})  # 연장된 주문: 집중 유지 내성 유리
	if world.get("turns") != null:
		world["turns"].notify_hostile_action(caster)
	var ctx := {"world": world, "self": caster, "spell": spell, "aim": aim, "opts": opts, "instance": inst, "slot": slot}
	if spell.has("script"):
		var r: Dictionary = load("res://scripts/rules/features.gd").run(spell["script"], ctx)
		r["ok"] = r.get("ok", true)
		_finish_instance(inst)
		return r
	var r2 := resolve_effects(ctx)
	_finish_instance(inst)
	return r2


## 효과 모델 처리(스크립트 주문도 일부를 이 함수로 처리할 수 있다).
static func resolve_effects(ctx: Dictionary) -> Dictionary:
	var world: Dictionary = ctx["world"]
	var caster: Node = ctx["self"]
	var spell: Dictionary = ctx["spell"]
	var aim: Vector2i = ctx["aim"]
	var opts: Dictionary = ctx.get("opts", {})
	var inst: Dictionary = ctx["instance"]
	var slot: int = ctx["slot"]
	var grid: Node = world["grid"]
	var cells := area_cells(world, caster, spell, aim)
	var targets: Array = ctx.get("targets", targets_for(world, caster, spell, aim, cells, opts, slot))
	var eff: Dictionary = spell["effects"]
	var check: Dictionary = eff.get("check", {})
	var results: Array = []
	var affected: Array = []
	if check.get("type") == "attack":
		for t: Node in targets:
			var atk := _spell_attack(caster, spell, slot)
			var actx: Dictionary = grid.attack_context(caster, t)
			if atk["kind"] == "ranged" and Combat.is_threatened(world, caster):
				actx["disadvantage"].append("근접 위협")
			var r := Resolver.attack(caster, t, atk, actx)
			if not r["hit"] and r.get("valid", true) and opts.get("metamagic", "") == "seeking" and int(r.get("natural", 0)) != 20:
				Dice.log_text("%s: 추적 주문 — 다시 굴린다" % caster.label())
				r = Resolver.attack(caster, t, atk, actx)
			if r["hit"]:
				affected.append(t)
				for e: Dictionary in eff.get("hit", []):
					if e["type"] != "damage":
						apply_effect(ctx, t, e)
			elif r["valid"] and level_of(spell) == 0 and caster.has_cap("cantrip_half_on_miss"):
				# 강력한 소마법(방출학파 3레벨): 빗나가도 절반 피해, 추가 효과 없음
				var half: Array = []
				for p: Dictionary in atk["damage"]:
					half.append({"amount": Dice.roll(p["dice"], "강력한 소마법")["total"], "damage_type": p["damage_type"], "multiplier": 0.5})
				r["potent"] = Resolver.apply_damage(t, half, {"attacker": caster})
			results.append(r)
	elif check.get("type") == "save":
		var rolled := {}
		var fail := _scaled(caster, spell, eff.get("fail", []), slot, opts)
		var success := _scaled(caster, spell, eff.get("success", []), slot, opts)
		if level_of(spell) == 0 and (caster.has_cap("cantrip_half_on_miss") or caster.has_cap("cantrip_half_on_save")) and success.is_empty():
			for e: Dictionary in fail:
				if e["type"] == "damage":
					var h := e.duplicate()
					h["scale"] = 0.5
					success.append(h)
		var cparams := {"instance": inst["id"]}
		if spell.get("repeat_save", false):
			cparams["repeat_save"] = {"ability": check["ability"], "dc": spell_dc(caster)}
		results = Resolver.save_effect(targets, {"ability": check["ability"], "dc": spell_dc(caster)},
			fail, success, {"source": caster, "rolled": rolled, "duration": _dur(spell, opts), "condition_params": cparams, "magic": true,
				"disadvantage": ["고양된 주문"] if opts.get("metamagic", "") == "heightened" else [],
				"careful": _protected_targets(caster, spell, targets, opts)})
		for r: Dictionary in results:
			var t: Node = r["target"]
			if not r["save"]["success"]:
				affected.append(t)
			for e: Dictionary in (success if r["save"]["success"] else fail):
				if not e["type"] in ["damage", "apply_condition"]:
					apply_effect(ctx, t, e)
		var dtype := _area_damage_type(spell)
		if dtype != "" and not cells.is_empty() and world.get("surfaces") != null:
			var amount := 0
			for k: String in rolled.keys():
				amount = maxi(amount, int(rolled[k]))
			world["surfaces"].tile_damage(cells, dtype, amount, caster)
	for e: Dictionary in eff.get("apply", []):
		var who: Array = targets if not targets.is_empty() or spell.get("area") != null else [caster]  # 범위 주문은 범위 안 생물만(빈 범위면 없음)
		if e["type"] in ["create_surface", "create_cloud", "light", "teleport", "resource", "dialogue_unlock"]:
			who = [caster]  # 칸·세계에 거는 효과는 한 번만
		for t: Node in who:
			apply_effect(ctx, t, e)
	for t: Node in targets:
		if not t in inst["targets"]:
			inst["targets"].append(t)
	return {"ok": true, "results": results, "cells": cells, "affected": affected}


static func level_of(spell: Dictionary) -> int:
	return int(spell["level"])


## 효과 하나를 대상에 건다(룰북 8단계 효과 종류).
static func apply_effect(ctx: Dictionary, t: Node, e: Dictionary) -> void:
	var world: Dictionary = ctx["world"]
	var caster: Node = ctx["self"]
	var spell: Dictionary = ctx["spell"]
	var inst: Dictionary = ctx["instance"]
	var slot: int = ctx["slot"]
	var opts: Dictionary = ctx.get("opts", {})
	var dur := _dur(spell, opts)
	match e["type"]:
		"damage":
			var dtype: String = e["damage_type"] if e["damage_type"] != "chosen" else opts.get("choice", "fire")
			var r := Dice.roll(damage_dice(caster, spell, e["dice"], slot, dtype), spell["name"]["en"], false,
				2 if dtype in Resolver.adept_types(caster) else 0)  # 원소 통달: 1 → 2
			if Resolver.destructive_max(caster, dtype):
				r["total"] = int(DiceExpr.stats(damage_dice(caster, spell, e["dice"], slot, dtype))["max"])  # 파괴의 분노
			Resolver.apply_damage(t, [{"amount": r["total"], "damage_type": dtype}], {"attacker": caster})
		"heal":
			var amount: int = Dice.roll(scaled_dice(caster, spell, e["dice"], slot), spell["name"]["en"])["total"]
			if e.get("add") == "spell_mod":
				amount += spell_mod(caster)
			if level_of(spell) > 0 and caster.has_cap("spell_heal_bonus"):
				amount += 2 + slot  # 생명의 제자: 2 + 슬롯 레벨
			if has_max_healing(t):
				amount = _max_heal(caster, spell, e, slot)  # Beacon of Hope
			Resolver.heal(t, amount, caster)
			if slot > 0 and caster.has_condition("starry_chalice") and not inst.get("chalice", false):
				inst["chalice"] = true
				_chalice(world_of(inst), caster)
			if level_of(spell) > 0 and t != caster and caster.has_cap("blessed_healer") and not inst.get("blessed_healer", false):
				inst["blessed_healer"] = true  # 축복받은 치유자(생명 영역 6레벨): 남을 치유하면 나도 2 + 슬롯 레벨
				Resolver.heal(caster, 2 + slot, caster)
		"temp_hp":
			Resolver.grant_temp_hp(t, Dice.roll(scaled_dice(caster, spell, e["dice"], slot), spell["name"]["en"])["total"])
		"apply_condition":
			var cparams := {"instance": inst["id"]}
			if e.get("escape", false):
				cparams["escape_dc"] = spell_dc(caster)  # 행동으로 판정해 풀 수 있다(Entangle 등)
			t.apply_condition(e["id"], int(e.get("turns", dur)), caster, cparams)
		"remove_condition":
			t.remove_condition(e["id"])
		"modify", "advantage":
			_add_modifier(ctx, t, e)
		"light":
			var src := {"id": "spell_%d" % inst["id"], "cell": world["grid"].cell_of(t), "creature": t,
				"bright": int(e.get("bright_tiles", 0)), "dim": int(e.get("dim_tiles", 0)), "instance": inst["id"]}
			if e.has("dispels"):
				for c in Area.circle(world["grid"], world["grid"].cell_of(t), int(e.get("bright_tiles", 0))):
					if world["grid"].cloud_id(c) == e["dispels"]:
						world["grid"].set_cloud(c, null)
			world["grid"].light_sources.append(src)
		"teleport":
			var grid: Node = world["grid"]
			var to: Vector2i = ctx["aim"]
			if grid.distance(grid.cell_of(caster), to) <= int(e["tiles"]) and not grid.blocks_movement(to) \
					and grid.creature_at(to) == null and (e.get("no_los", false) or grid.has_line_of_sight(grid.cell_of(caster), to)):
				grid.remove(caster)
				grid.place(caster, to)
				EventBus.on_enter_tile.emit(caster, to)
		"create_surface", "create_cloud":
			var cells: Array = area_cells(world, caster, spell, ctx["aim"])
			if cells.is_empty():
				cells = [ctx["aim"]]
			var sopts := {"turns": dur, "source": "spell_%d" % inst["id"], "dc": spell_dc(caster)}
			if e["type"] == "create_surface":
				world["surfaces"].place_surface(cells, e["id"], sopts)
			else:
				world["surfaces"].place_cloud(cells, e["id"], sopts)
		"push":
			Combat._push_up_to(world, caster, t, int(e["tiles"]))
		"dialogue_unlock":
			if not world.has("dialogue_tags"):
				world["dialogue_tags"] = {}
			world["dialogue_tags"][e["tag"]] = true
		"resource":
			if not world.has("party_resources"):
				world["party_resources"] = {}
			world["party_resources"][e["id"]] = int(world["party_resources"].get(e["id"], 0)) + int(e.get("add", 0))
		"grant_action":
			_add_modifier(ctx, t, e)


static func has_max_healing(t: Node) -> bool:
	for m in t.modifier_entries():
		if m["effect"]["type"] == "modify" and m["effect"]["stat"] == "max_healing":
			return true
	return false


static func _max_heal(caster: Node, spell: Dictionary, e: Dictionary, slot: int) -> int:
	var s := DiceExpr.stats(scaled_dice(caster, spell, e["dice"], slot))
	var v := int(s["max"])
	if e.get("add") == "spell_mod":
		v += spell_mod(caster)
	if level_of(spell) > 0 and caster.has_cap("spell_heal_bonus"):
		v += 2 + slot
	return v


## 수정치 효과 → 대상의 extra_modifiers(인스턴스·지속 기록). 일부 값은 대상에 바로 바꾸고 되돌릴 값을 기록한다.
static func _add_modifier(ctx: Dictionary, t: Node, e: Dictionary) -> void:
	var caster: Node = ctx["self"]
	var inst: Dictionary = ctx["instance"]
	var opts: Dictionary = ctx.get("opts", {})
	var effect := e.duplicate()
	if effect.get("type") == "modify":
		match effect["stat"]:
			"resistance":
				effect = {"type": "modify", "stat": "damage_resistance",
					"damage_types": [opts.get("choice", "fire") if e.get("damage_type") == "chosen" else e.get("damage_type", "")]}
			"hp_max":
				t.hp_max += int(e["add"])
				inst["reverts"].append({"creature": t, "field": "hp_max", "add": -int(e["add"])})
				return
			"darkvision_tiles":
				inst["reverts"].append({"creature": t, "field": "darkvision_tiles", "value": t.darkvision_tiles, "senses": t.senses.duplicate()})
				t.darkvision_tiles = maxi(t.darkvision_tiles, int(e["set"]))
				if not t.senses.has("darkvision"):
					t.senses.append("darkvision")
				return
			"sees_invisible":
				inst["reverts"].append({"creature": t, "field": "senses", "value": t.senses.duplicate()})
				t.senses.append("see_invisible")
				return
	var m := {"effect": effect, "source": "spell", "instance": inst["id"], "turns_left": duration_turns(ctx["spell"])}
	match e.get("until", ""):
		"start_of_caster_next_turn":
			m["until_turn_start_of"] = caster
			m.erase("turns_left")
		"end_of_caster_next_turn":
			m["expires_after_turn_end_of"] = caster
			m["turn_end_count"] = 2
			m.erase("turns_left")
		"start_of_next_turn":
			m["until_turn_start_of"] = t
			m.erase("turns_left")
	if e.get("consume", "") == "attacked":
		m["consume_on_attacked"] = true
	if typeof(e.get("ability")) == TYPE_STRING and e.get("ability") == "chosen":
		effect["ability"] = [opts.get("choice", "str")]
	t.extra_modifiers.append(m)


static func _scaled(caster: Node, spell: Dictionary, effects: Array, slot: int, opts: Dictionary) -> Array:
	var out: Array = []
	for e: Dictionary in effects:
		var c := e.duplicate()
		if c["type"] == "damage":
			if c["damage_type"] == "chosen":
				c["damage_type"] = opts.get("choice", "fire")
			c["dice"] = damage_dice(caster, spell, c["dice"], slot, str(c["damage_type"]))
		out.append(c)
	return out


# ======================================================================
# 인스턴스
# ======================================================================

static func new_instance(world: Dictionary, caster: Node, spell: Dictionary, slot: int) -> Dictionary:
	var inst := {"id": _next_id, "spell": spell["id"], "caster": caster, "world": world, "slot": slot,
		"targets": [], "reverts": [], "auras": [], "concentration": spell.get("concentration", false)}
	_next_id += 1
	instances[inst["id"]] = inst
	return inst


## 즉시 주문이고 남은 효과가 없으면 기록을 지운다(집중·지속 주문은 남긴다).
static func _finish_instance(inst: Dictionary) -> void:
	var spell := RulesDB.get_entry("spell", inst["spell"])
	if spell["duration"]["type"] == "instant" and inst["reverts"].is_empty() and inst["auras"].is_empty():
		var used := false
		for t: Node in inst["targets"]:
			if is_instance_valid(t) and _has_instance_effects(t, inst["id"]):
				used = true
		if not used:
			instances.erase(inst["id"])


static func _has_instance_effects(t: Node, id: int) -> bool:
	for c in t.conditions:
		if c.get("params", {}).get("instance") == id:
			return true
	for m in t.extra_modifiers:
		if m.get("instance") == id:
			return true
	return false


## 주문 인스턴스를 끝낸다: 상태·수정치·표면·구름·광원·바꾼 값을 걷어낸다.
static func end_instance(id: int) -> void:
	if not instances.has(id):
		return
	var inst: Dictionary = instances[id]
	instances.erase(id)
	var world: Dictionary = inst["world"]
	var everyone: Array = inst["targets"].duplicate()
	if world.has("grid"):
		everyone.append_array(world["grid"].creatures())
	for t: Node in everyone:
		if not is_instance_valid(t):
			continue
		for c in t.conditions.duplicate():
			if c.get("params", {}).get("instance") == id:
				t.remove_condition(c["id"])
		for m in t.extra_modifiers.duplicate():
			if m.get("instance") == id:
				t.extra_modifiers.erase(m)
	for r: Dictionary in inst["reverts"]:
		var t: Node = r["creature"]
		if not is_instance_valid(t):
			continue
		match r["field"]:
			"hp_max":
				t.hp_max += int(r["add"])
				t.hp = mini(t.hp, t.hp_max)
			"darkvision_tiles":
				t.darkvision_tiles = r["value"]
				t.senses = r["senses"]
			"senses":
				t.senses = r["value"]
			_:
				t.set(r["field"], r["value"])  # 고도·편(team)·무게 등 그대로 되돌림
	if world.has("grid"):
		var grid: Node = world["grid"]
		var key := "spell_%d" % id
		for c in grid.all_cells():
			var s: Variant = grid.surface(c)
			if s != null and s.get("source") == key:
				grid.set_surface(c, null)
			var cl: Variant = grid.cloud(c)
			if cl != null and cl.get("source") == key:
				grid.set_cloud(c, null)
		for src in grid.light_sources.duplicate():
			if src.get("instance") == id:
				grid.light_sources.erase(src)
	if inst.has("on_end"):
		inst["on_end"].call()
	# 람다가 인스턴스를 붙잡는 순환 참조를 끊는다
	inst.erase("on_end")
	inst["auras"] = []
	Dice.log_text("%s 효과가 끝났다" % RulesDB.get_entry("spell", inst["spell"])["name"]["en"])


## 주문을 시전하면 끝나는 상태(Invisibility·Sanctuary — params.ends_on_cast).
static func _end_on_cast(c: Node) -> void:
	for cond in c.conditions.duplicate():
		if cond.get("params", {}).get("ends_on_cast", false):
			_end_for(c, cond)


static func _end_for(t: Node, cond: Dictionary) -> void:
	var id: Variant = cond.get("params", {}).get("instance")
	t.remove_condition(cond["id"])
	if id != null and instances.has(id) and not instances[id]["concentration"]:
		# 대상 하나만 끝나면 그 대상의 이 인스턴스 효과만 걷는다
		for m in t.extra_modifiers.duplicate():
			if m.get("instance") == id:
				t.extra_modifiers.erase(m)


# ======================================================================
# 턴 처리(TurnManager가 부른다)
# ======================================================================

## 턴 끝: 반복 내성(성공하면 그 대상에게서 주문이 끝난다 — 원문), 집중 지속시간 감소.
## 시전자가 사라진(메모리에서 지워진) 인스턴스를 정리한다.
static func _prune() -> void:
	for id: Variant in instances.keys():
		if not is_instance_valid(instances[id]["caster"]):
			instances.erase(id)


static func on_turn_end(world: Dictionary, c: Node) -> void:
	_prune()
	for cond in c.conditions.duplicate():
		var rs: Dictionary = cond.get("params", {}).get("repeat_save", {})
		if rs.is_empty() or not c.conditions.has(cond):
			continue
		var s := Resolver.saving_throw(c, rs["ability"], int(rs["dc"]))
		if not s["success"] and rs.has("on_fail_apply"):
			# 두 번째 내성도 실패하면 다음 상태로(Sleep: 무력화 → 무의식)
			var p: Dictionary = cond["params"].duplicate(true)
			p.erase("repeat_save")
			c.apply_condition(rs["on_fail_apply"], int(cond.get("turns_left", -1)), cond.get("source"), p)
			c.remove_condition(cond["id"])
			continue
		if s["success"]:
			var id: Variant = cond["params"].get("instance")
			for other in c.conditions.duplicate():
				if other.get("params", {}).get("instance") == id:
					c.remove_condition(other["id"])
			for m in c.extra_modifiers.duplicate():
				if m.get("instance") == id:
					c.extra_modifiers.erase(m)
	if not c.concentration.is_empty() and int(c.concentration.get("turns_left", -1)) > 0:
		c.concentration["turns_left"] -= 1
		if c.concentration["turns_left"] <= 0:
			c.break_concentration("지속시간 끝")
	for inst: Dictionary in instances.values().duplicate():
		for aura: Dictionary in inst["auras"]:
			if aura.has("on_turn_end"):
				aura["on_turn_end"].call(world, c)


## 턴 시작(Blink 복귀 등).
static func on_turn_start(world: Dictionary, c: Node) -> void:
	_prune()
	for inst: Dictionary in instances.values().duplicate():
		for aura: Dictionary in inst["auras"]:
			if aura.has("on_turn_start"):
				aura["on_turn_start"].call(world, c)


## 이동 한 걸음 뒤(오라 진입 등).
static func on_moved(world: Dictionary, c: Node) -> void:
	_prune()
	for inst: Dictionary in instances.values().duplicate():
		for aura: Dictionary in inst["auras"]:
			if aura.has("on_enter"):
				aura["on_enter"].call(world, c)
