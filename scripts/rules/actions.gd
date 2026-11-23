extends RefCounted
## 행동 목록(룰북 3단계 행동 경제 — BG3 단축 막대 구조 참고). 화면은 이 목록을 그리기만 한다.
##   공용 행동: data/rules/actions.json(이름·설명·비용·대상), 실행은 여기서 Combat·Physics·Interact로.
##   클래스 행동: 생물의 기능 중 스크립트가 있고 직접 쓰는 것(Features.use).
##   아이템: 소지품의 물약 → 마시기·먹이기·던지기.
##   주문: 생물의 주문(Spellcasting).
## 행동 키: 공용 = 행동 ID, 기능 = "feature:<id>", 아이템 = "<행동>:<아이템 ID>"(drink:potion_of_healing), 주문 = "spell:<id>".
## 탐험 중(explore)에는 행동 비용이 없다(5단계 '탐험 중 주문·소모품'): 실행 전에 턴 자원을 채운다.
## 탐험 중 적대 행동은 먼저 처리하고 전투를 시작한다(숨은 채 하면 알아채지 못한 적은 기습 — 5단계).

const Combat := preload("res://scripts/rules/combat.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Physics := preload("res://scripts/rules/physics.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Features := preload("res://scripts/rules/features.gd")
const Interact := preload("res://scripts/rules/interact.gd")
const SpellUtil := preload("res://scripts/rules/spell_util.gd")
## 소환 존재 조종(주문이 남긴 entity): 원문 비용·거리
const ENTITY_ACTIONS := {
	"spiritual_weapon": {"id": "entity:spiritual_weapon", "name": {"ko": "영체 무기 휘두르기", "en": "Spiritual Weapon Strike"},
		"desc": {"ko": "영체 무기를 4칸까지 옮겨 곁의 적을 친다(1d8 + 주문 수정치 역장).", "en": "Move the weapon up to 4 tiles and strike."},
		"cost": "bonus", "target": "enemy", "tab": "spells", "icon": "res://assets/statuses/whetted.webp", "explore": false},
	"flaming_sphere": {"id": "entity:flaming_sphere", "name": {"ko": "불구체 굴리기", "en": "Roll Flaming Sphere"},
		"desc": {"ko": "불구체를 6칸까지 굴린다. 생물 칸에 닿으면 민첩 내성 2d6 화염, 지나간 가연성 칸에 불이 붙는다.", "en": "Roll the sphere up to 6 tiles."},
		"cost": "bonus", "target": "cell", "tab": "spells", "icon": "res://assets/statuses/burn.webp", "explore": false},
	"mage_hand": {"id": "entity:mage_hand", "name": {"ko": "유령 손 쓰기", "en": "Use Mage Hand"},
		"desc": {"ko": "6칸 안에서 상자를 열어 꺼내 오거나, 찾은 함정을 멀리서 미리 터뜨린다.", "en": "Loot a container or trigger a found trap from afar."},
		"cost": "action", "target": "cell", "tab": "spells", "icon": "res://assets/statuses/shield_arm.webp", "explore": true},
}

const COST_NAME := {"action_": "action", "bonus_action": "bonus", "action": "action", "free": "free", "reaction": "reaction"}


static func defs() -> Dictionary:
	var out := {}
	for a: Dictionary in RulesDB.entries("action"):
		out[a["id"]] = a
	return out


static func def_of(key: String) -> Dictionary:
	if key.begins_with("spell:"):
		var sp := RulesDB.get_entry("spell", key.trim_prefix("spell:"))
		return {"id": key, "name": sp.get("name", {}), "desc": {"ko": sp.get("notes_ko", ""), "en": ""},
			"cost": Spellcasting._cost(sp) if not sp.is_empty() else "action", "target": "cell", "tab": "spells", "spell": sp}
	if key.begins_with("feature:"):
		var fid := key.trim_prefix("feature:")
		var f: Dictionary = {}
		for cls_f: Dictionary in all_features():
			if cls_f["id"] == fid:
				f = cls_f
		return {"id": key, "name": f.get("name", {"ko": fid, "en": fid}), "desc": f.get("desc", f.get("summary", {"ko": f.get("notes_ko", ""), "en": ""})),
			"cost": COST_NAME.get(str(f.get("kind", "free")), "free"), "target": str(f.get("target", "self")), "tab": "class",
			"icon": "res://assets/" + str(f.get("icon", "statuses/buff.webp")), "explore": bool(f.get("explore", false)),
			"resource": f.get("resource", "")}
	if key.begins_with("entity:"):
		var kind := key.trim_prefix("entity:")
		return ENTITY_ACTIONS.get(kind, {}).duplicate(true)
	if key.begins_with("wa_"):
		var wa := RulesDB.get_entry("weapon_action", key)
		if wa.is_empty():
			return {}
		var out := wa.duplicate(true)
		out["target"] = str(wa.get("target", "enemy"))
		out["cost"] = "free" if str(wa["cost"]) == "movement" else str(wa["cost"])
		out["tab"] = "class"
		out["explore"] = out["target"] == "enemy"
		out["resource"] = str(wa["resource"]) if wa.has("resource") else ("" if wa.get("unlimited", false) else key)
		if str(wa["cost"]) == "free" or str(wa["cost"]) == "passive":
			out["cost"] = "free"
		out["weapon_action"] = true
		return out
	var parts := key.split(":")
	var base: Dictionary = defs().get(parts[0], {})
	if parts.size() > 1 and not base.is_empty():
		base = base.duplicate(true)
		base["item"] = parts[1]
		var item := RulesDB.get_entry("item", parts[1])
		base["name"] = {"ko": "%s: %s" % [base["name"]["ko"], item.get("name", {}).get("ko", parts[1])],
			"en": "%s: %s" % [base["name"]["en"], item.get("name", {}).get("en", parts[1])]}
	return base


## 모든 클래스·하위 클래스·종족 기능(아이콘·이름 조회)
static func all_features() -> Array:
	var out: Array = []
	for cls: Dictionary in RulesDB.entries("class"):
		out.append_array(cls.get("features", []))
		for s: Dictionary in cls.get("subclasses", []):
			out.append_array(s.get("features", []))
	for sp: Dictionary in RulesDB.entries("species"):
		out.append_array(sp.get("features", []))
	return out


## 탭별 행동 키 목록: {"common": [...], "class": [...], "items": [...], "spells": [...]}
static func list_for(world: Dictionary, c: Node, explore: bool = false) -> Dictionary:
	var out := {"common": [], "class": [], "items": [], "spells": []}
	for id: String in defs():
		var d: Dictionary = defs()[id]
		if d["tab"] == "items":
			continue
		if str(d.get("requires", "")) != "" and not c.has_cap(str(d["requires"])):
			continue  # 행동 데이터 requires: 이 능력 태그가 있어야 뜬다(교활한 행동·급소 공격 등)
		if id == "offhand_attack" and c.weapon("off") == "":
			continue
		if explore and not d["explore"]:
			continue
		out[d["tab"]].append(id)
	for fid: String in c.feature_data:
		var f: Dictionary = c.feature_data[fid]
		if f.has("script") and (str(f.get("kind", "")) in ["action", "bonus_action", "free"] or bool(f.get("usable", false))):
			if explore and not def_of("feature:" + fid)["explore"]:
				continue
			out["class"].append("feature:" + fid)
	for wa: String in weapon_actions_for(c):
		if not str(RulesDB.get_entry("weapon_action", wa)["cost"]) in ["reaction", "passive"]:
			out["class"].append(wa)  # 반응(끈기·반격)·켜 두는 것(정밀 공격)은 상시 설정 — 단축 막대에 두지 않는다
	for kind: String in ENTITY_ACTIONS:
		if not SpellUtil.find_entity(c, kind).is_empty():
			out["spells"].append("entity:" + kind)
	for item: String in c.inventory:
		var e := RulesDB.get_entry("item", item)
		if e.get("category", "") == "potion" and Interact.count(world, item, c) > 0:
			for verb: String in ["drink", "feed", "throw_potion"]:
				if verb == "throw_potion" and not bool(e.get("throwable", true)):
					continue  # 던질 수 없는 것(좋은열매 등)
				out["items"].append("%s:%s" % [verb, item])
		elif e.get("category", "") == "gear" and Interact.count(world, item, c) > 0:
			if e.get("use", {}).has("throw"):
				out["items"].append("throw_item:" + item)  # 산·연금술사의 불·성수·기름
			if e.get("use", {}).has("spread"):
				out["items"].append("spread_item:" + item)  # 마름쇠·쇠구슬
		elif e.get("category", "") == "scroll" and Interact.count(world, item, c) > 0 and can_read_scroll(c, e):
			out["items"].append("read_scroll:" + item)
	for sid: String in c.spells:
		if not RulesDB.get_entry("spell", sid).is_empty():
			out["spells"].append("spell:" + sid)
	for sid: String in c.spellbook:
		if not sid in c.spells and Spellcasting.ritual_from_book(world, c, sid):
			out["spells"].append("spell:" + sid)  # 의식 숙련: 주문서의 의식 주문(탐험 중)
	return out


## 지금 쓸 수 없는 이유("" = 가능). 대상과 상관없는 검사만.
static func unavailable(world: Dictionary, c: Node, key: String, explore: bool = false) -> String:
	var d := def_of(key)
	if d.is_empty():
		return "모르는 행동"
	if c.dead or c.is_down():
		return "쓰러졌다"
	if key.begins_with("wa_"):
		if not key in weapon_actions_for(c):  # 무기 액션 자원(짧은 휴식 1회)도 여기서 만든다
			return "이 무기로는 쓸 수 없다"
	if not explore:
		var cost: String = d.get("cost", "action")
		if key in ["attack", "ranged_attack"] and int(c.turn.get("attacks_left", 0)) > 0:
			cost = "free"
		if key.begins_with("wa_") and cost == "action" and int(c.turn.get("attacks_left", 0)) > 0:
			cost = "free"  # 무기 액션은 공격 행동의 공격 하나(추가 공격과 이어진다 — BG3)
		if cost != "free" and not Combat.can_spend(c, cost):
			return {"action": "행동이 없다", "bonus": "보너스 행동이 없다", "reaction": "반응이 없다"}.get(cost, "비용이 없다")
	if d.get("resource", "") != "" and c.resource(d["resource"]) <= 0:
		return "남은 횟수가 없다"
	if key.begins_with("spell:"):
		var sp: Dictionary = d["spell"]
		if int(sp.get("level", 0)) > 0:
			var any := false
			for l in range(int(sp["level"]), 10):
				any = any or c.resource("spell_slot_%d" % l) > 0
			if not any:
				return "주문 슬롯이 없다"
	match key:
		"stand_up":
			if not c.has_condition("prone"):
				return "넘어지지 않았다"
		"jump":
			if not explore and int(c.turn.get("movement", 0)) < 2:
				return "이동력이 모자란다"
		"dip":
			if _dip_kind(world, c) == "":
				return "담글 표면이 없다"
		"throw":
			if _throwable(world, c).is_empty():
				return "옆에 던질 물체가 없다"
		"sneak_melee", "sneak_ranged":
			if c.turn.get("sneak_used", false) and not explore:
				return "이번 턴에 이미 급소 공격을 했다"
			if key == "sneak_ranged" and c.weapon_sets.get("ranged", {}).get("main", "") == "":
				return "원거리 무기가 없다"
		"offhand_attack":
			if not c.turn.get("light_attack_done", false) and not explore:
				return "먼저 가벼운 무기로 공격해야 한다"
	if key.begins_with("wa_") and not explore:
		var wa := RulesDB.get_entry("weapon_action", key)
		if str(wa["cost"]) == "movement" and int(c.turn.get("movement", 0)) < int(wa.get("move_tiles", 0)):
			return "이동력이 모자란다"
		if wa.has("requires_turn") and not (wa["requires_turn"] as Array).any(func(f: String) -> bool: return c.turn.get(f, false)):
			return "이번 턴에 질주나 이탈을 해야 한다"
	if key.begins_with("wa_") and c.has_flag("disarmed"):
		return "무기를 놓쳤다"
	if not explore:
		var rt: Array = d.get("requires_turn", [])
		if not rt.is_empty() and not rt.any(func(f: String) -> bool: return c.turn.get(f, false)):
			return "지금은 쓸 수 없다"  # 행동 데이터 requires_turn: 이번 턴 조건(강타 추가 공격·자루 공격)
		if str(d.get("also_costs", "")) != "" and not Combat.can_spend(c, str(d["also_costs"])):
			return "보너스 행동이 없다" if str(d["also_costs"]) == "bonus" else "행동이 없다"
	return ""


## 대상 칸에 대한 미리보기: {"valid", "lines": [..], "path", "area"}
static func preview(world: Dictionary, c: Node, key: String, cell: Vector2i, explore: bool = false) -> Dictionary:
	var grid: Node = world["grid"]
	var d := def_of(key)
	var why := unavailable(world, c, key, explore)
	if why != "":
		return {"valid": false, "lines": [why]}
	var t: Node = grid.creature_at(cell)
	var out := {"valid": true, "lines": []}
	if t != null:
		out["lines"].append_array(Resolver.lore_lines(c, t))  # 사냥꾼의 지식: 표식한 대상의 저항·면역·취약
	match d.get("target", "self"):
		"enemy":
			if t == null and key in ["attack", "ranged_attack"] and not grid.object_at(cell).is_empty():
				var obj: Dictionary = grid.object_at(cell)
				return {"valid": true, "lines": ["%s 공격(AC %d, HP %d)" % [obj.get("id", "물체"), int(obj.get("ac", 10)), int(obj.get("hp", 1))]], "object": true}
			if t == null or not c.is_hostile_to(t) or t.dead:
				return {"valid": false, "lines": ["적을 골라야 한다"]}
		"ally", "ally_down", "ally_help":
			if t == null or c.is_hostile_to(t) or t.dead:
				return {"valid": false, "lines": ["아군을 골라야 한다"]}
			if d["target"] == "ally_down" and not t.is_down():
				return {"valid": false, "lines": ["쓰러진 아군에게만"]}
			if d["target"] == "ally_help" and not t.is_down() and not t.active_conditions().any(func(a: Dictionary) -> bool:
					return a["def"].get("helpable", false) or str(a["id"]) == "prone"):
				return {"valid": false, "lines": ["쓰러졌거나 돕기로 풀 상태가 있는 아군에게만"]}
			if grid.distance_between(c, t) > 1 and key != "spell":
				return {"valid": false, "lines": ["인접해야 한다"]}
		"creature":
			if t == null or t.dead:
				return {"valid": false, "lines": ["생물을 골라야 한다"]}
	match key.get_slice(":", 0):  # 아이템 행동(throw_potion:물약 등)은 앞부분으로
		"attack", "ranged_attack", "offhand_attack", "sneak_melee", "sneak_ranged":
			var opts := {}
			if key == "ranged_attack" or key == "sneak_ranged":
				opts["weapon"] = c.weapon_sets.get("ranged", {}).get("main", "")
			elif key == "offhand_attack":
				opts["weapon"] = c.weapon("off")
			var p := Combat.preview_attack(world, c, t, opts)
			if not p.get("valid", false):
				return {"valid": false, "lines": [p.get("reason", "")]}
			out["lines"].append("명중 %d%%" % roundi(p["hit_chance"] * 100))
			out["lines"].append("피해 %d~%d" % [p["damage"]["min"], p["damage"]["max"]])
			out["chance"] = p["hit_chance"]
			if key.begins_with("sneak_"):
				out["lines"].append("급소 공격 +%dd6(조건이 맞으면)" % sneak_dice(c))
		"jump":
			var reach := Combat.jump_distance(c)
			var ok: bool = grid.distance(grid.cell_of(c), cell) <= reach and not grid.blocks_movement(cell) \
				and grid.creature_at(cell) == null and grid.height(cell) - grid.height(grid.cell_of(c)) <= 1
			out["valid"] = ok
			out["path"] = [cell]
			out["lines"].append("도약 %d칸까지" % reach)
			var drop: int = grid.height(grid.cell_of(c)) - grid.height(cell)
			if drop >= 2:
				out["lines"].append("낙하 %d단계" % drop)
		"shove":
			if grid.distance_between(c, t) > 1:
				return {"valid": false, "lines": ["인접한 대상만"]}
			var p := Physics.preview_shove(grid, c, t, not c.is_hostile_to(t))
			if not p["valid"]:
				return {"valid": false, "lines": [p.get("reason", "")]}
			out["path"] = p["path"]
			out["lines"].append("성공 %d%% · %d칸" % [roundi(p["chance"] * 100), p["distance"]])
			if p["fall_levels"] > 0:
				out["lines"].append("낙하 %d단계" % p["fall_levels"])
		"throw":
			var obj := _throwable(world, c)
			var w := float(obj.get("weight_kg", 10))
			if w > Physics.max_throw_kg(c):
				return {"valid": false, "lines": ["너무 무겁다"]}
			out["lines"].append("%s 던지기 · 피해 %s" % [obj.get("id", ""), Physics.throw_damage_dice(w)])
		"throw_item":
			var th: Dictionary = RulesDB.get_entry("item", key.get_slice(":", 1)).get("use", {}).get("throw", {})
			if grid.distance(grid.cell_of(c), cell) > int(th.get("range_tiles", 4)):
				return {"valid": false, "lines": ["4칸 안"]}
			out["lines"].append("민첩 내성 DC %d" % (8 + c.ability_mod("dex") + c.proficiency_bonus))
		"spread_item":
			var sp: Dictionary = RulesDB.get_entry("item", key.get_slice(":", 1)).get("use", {}).get("spread", {})
			var n := int(sp.get("size", 1))
			var cells2: Array = []
			for dy in n:
				for dx in n:
					cells2.append(cell + Vector2i(dx, dy))
			out["area"] = cells2
			if grid.distance(grid.cell_of(c), cell) > int(sp.get("range_tiles", 1)):
				return {"valid": false, "lines": ["너무 멀다"]}
		"throw_potion":
			var cells: Array = [cell]
			for dd: Vector2i in grid.DIRS_4:
				cells.append(cell + dd)
			out["area"] = cells
		_:
			if key.begins_with("wa_"):
				var wa := def_of(key)
				var wid := _wa_weapon(c, key)
				var p := Combat.preview_attack(world, c, t, {"weapon": wid})
				if not p.get("valid", false):
					return {"valid": false, "lines": [p.get("reason", "")]}
				out["lines"].append("명중 %d%%" % roundi(p["hit_chance"] * 100))
				if wa.has("save"):
					out["lines"].append("%s 내성 DC %d" % [str(wa["save"]).to_upper(), weapon_action_dc(c, wid)])
			elif key.begins_with("spell:"):
				var p := Spellcasting.preview(world, c, key.trim_prefix("spell:"), cell)
				out["valid"] = p["valid"]
				out["area"] = p["cells"]
				out["partial"] = p.get("partial", [])
				out["shape"] = p.get("shape", {})
				if not p["valid"]:
					out["lines"].append(p["reason"])
				for row: Dictionary in p["targets"]:
					if row.has("chance"):
						out["lines"].append("%s %d%%" % [row["creature"].label(), roundi(row["chance"] * 100)])
	return out


## 실행. 결과: {"ok", "reason"?, "hostile": 적대 행동이었나}
static func execute(world: Dictionary, c: Node, key: String, cell: Vector2i, explore: bool = false) -> Dictionary:
	var grid: Node = world["grid"]
	if explore:
		c.reset_turn()  # 탐험 중에는 행동 비용이 없다
	var why := unavailable(world, c, key, explore)
	if why != "":
		return {"ok": false, "reason": why}
	var t: Node = grid.creature_at(cell)
	var hostile: bool = t != null and c.is_hostile_to(t) and (key in ["attack", "ranged_attack", "offhand_attack", "shove", "throw", "sneak_melee", "sneak_ranged"] or key.begins_with("wa_"))
	if key.begins_with("spell:"):
		var sp := RulesDB.get_entry("spell", key.trim_prefix("spell:"))
		hostile = sp.get("effects", {}).has("check") and grid.creatures().any(func(o: Node) -> bool:
			return c.is_hostile_to(o) and grid.cell_of(o) == cell)
	# 탐험 중 숨은 채 하는 적대 행동: 알아채지 못한 적에게는 숨은 상태의 공격(유리 — 5단계 은신 공격)
	if explore and hostile and c.sneaking and t != null and t.awareness.get(c, {}).get("state", "") != "alerted":
		c.apply_condition("invisible", -1, "hide", {"stealth_total": int(c.get_meta("stealth_total", 10))})
	var r: Dictionary = _run(world, c, key, cell, t)
	r["hostile"] = hostile
	if explore and hostile and world.get("explore") != null and t != null:
		world["explore"].hostile_action(c, t)
	return r


static func _run(world: Dictionary, c: Node, key: String, cell: Vector2i, t: Node) -> Dictionary:
	var grid: Node = world["grid"]
	if key.begins_with("spell:"):
		return Spellcasting.cast(world, c, key.trim_prefix("spell:"), cell)
	if key.begins_with("feature:"):
		var tgt: Variant = cell if str(def_of(key).get("target", "self")) == "cell" else t  # 칸을 고르는 기능(땅의 도움)은 칸을
		return Features.use(world, c, key.trim_prefix("feature:"), tgt)
	if key.begins_with("wa_"):
		return _weapon_action(world, c, key, t)
	if key.begins_with("entity:"):
		return _entity_action(world, c, key.trim_prefix("entity:"), cell, t)
	match key:
		"bonus_weapon_attack":
			return _bonus_weapon_attack(world, c, t)
		"war_magic_attack":
			return _bonus_weapon_attack(world, c, t, "war_magic_ready")
		"haft_strike":
			return _haft_strike(world, c, t)
		"charger_attack", "charger_shove":
			return _charge(world, c, t, key == "charger_shove")
	var parts := key.split(":")
	match parts[0]:
		"attack":
			if c.active_set != "melee":
				Combat.switch_weapon_set(c)
			if t == null:
				return Combat.attack_object(world, c, cell)
			return Combat.attack(world, c, t)
		"ranged_attack":
			if c.active_set != "ranged":
				Combat.switch_weapon_set(c)
			if t == null:
				return Combat.attack_object(world, c, cell)
			return Combat.attack(world, c, t)
		"offhand_attack":
			return Combat.offhand_attack(world, c, t)
		"sneak_melee", "sneak_ranged":
			var want := "ranged" if parts[0] == "sneak_ranged" else "melee"
			if c.active_set != want:
				Combat.switch_weapon_set(c)
			c.turn["sneak_armed"] = true
			var r := Combat.attack(world, c, t)
			c.turn["sneak_armed"] = false
			return r
		"jump":
			if world.get("explore") != null and not world["turns"].in_combat:
				return {"ok": world["explore"].jump(c, cell)}
			return Combat.jump(world, c, cell)
		"shove":
			return Combat.shove(world, c, t)
		"throw":
			var obj := _throwable(world, c)
			var r := Combat.throw_object(world, c, t, float(obj.get("weight_kg", 10)))
			if r.get("ok", false):
				var at: Vector2i = obj["_cell"]
				grid.remove_object(at)
				if world.get("surfaces") != null and not obj.get("contents", {}).is_empty():
					grid.place_object(grid.cell_of(t), obj)
					world["surfaces"].break_object(grid.cell_of(t))  # 기름통 등은 맞은 자리에서 깨진다
			return r
		"dash":
			return Combat.dash(c)
		"disengage":
			return Combat.disengage(c)
		"hide":
			return Combat.hide(world, c)
		"cunning_dash", "cunning_disengage", "cunning_hide":
			return Combat.cunning_action(world, c, parts[0].trim_prefix("cunning_"))
		"help":
			return Combat.help(world, c, t)
		"dip":
			return Combat.dip(world, c)
		"stand_up":
			return Combat.stand_up(c)
		"switch_weapons":
			Combat.switch_weapon_set(c)
			return {"ok": true}
		"read_scroll":
			return read_scroll(world, c, parts[1], cell)
		"drink", "feed":
			var item := RulesDB.get_entry("item", parts[1])
			var who: Node = c if parts[0] == "drink" else t
			var r := Combat.drink_potion(c, item.get("effects", []), who, world)
			if r.get("ok", false):
				Interact.take(world, parts[1], 1, c)
			return r
		"throw_item":
			return Combat.throw_gear(world, c, parts[1], cell)
		"spread_item":
			return Combat.spread_gear(world, c, parts[1], cell)
		"throw_potion":
			var item := RulesDB.get_entry("item", parts[1])
			if not Combat.spend(c, "action"):
				return {"ok": false, "reason": "행동이 없다"}
			Interact.take(world, parts[1], 1, c)
			Physics.throw_potion(grid, cell, item.get("effects", []), t)
			return {"ok": true}
	return {"ok": false, "reason": "모르는 행동"}


static func _dip_kind(world: Dictionary, c: Node) -> String:
	var grid: Node = world["grid"]
	for cell in preload("res://scripts/rules/area.gd").circle(null, grid.cell_of(c), 1):
		var sid: String = grid.surface_id(cell)
		if sid == "fire" or (sid != "" and RulesDB.get_entry("surface", sid).get("coats", "") != ""):
			return sid
	return ""


## 옆 칸(또는 자기 칸)에 있는 던질 수 있는 물체(무게가 있는 것). 결과에 "_cell"을 붙인다.
static func _throwable(world: Dictionary, c: Node) -> Dictionary:
	var grid: Node = world["grid"]
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var cell: Vector2i = grid.cell_of(c) + Vector2i(dx, dy)
			var obj: Dictionary = grid.object_at(cell)
			if not obj.is_empty() and obj.has("weight_kg") and float(obj["weight_kg"]) <= Physics.max_throw_kg(c):
				var o := obj.duplicate(true)
				o["_cell"] = cell
				return o
	return {}


# ======================================================================
# 무기 액션(BG3 구조 참고 — data/rules/weapon_actions.json)
# ======================================================================

## 쥔 무기(근접·원거리 세트 주 무기)로 쓸 수 있는 무기 액션 ID. 그 무기에 숙련이 있어야 한다(BG3 — 보조 손 무기는 주지 않는다).
static func weapon_actions_for(c: Node) -> Array:
	var out: Array = []
	var learned: Array = c.get_meta("special_attacks", [])
	for wa: Dictionary in RulesDB.entries("weapon_action"):
		if wa.has("group") and not wa["id"] in learned:
			continue  # 기법·비전 사격은 배운 것만
		if _wa_weapon(c, wa["id"]) != "":
			out.append(wa["id"])
			if not wa.get("unlimited", false) and not wa.has("resource") and not c.resources.has(wa["id"]):
				c.resources[wa["id"]] = {"current": 1, "max": 1, "recharge": "short"}  # 짧은 휴식에 1회(캐릭터마다)
	return out


## 이 무기 액션에 쓸 무기(없으면 ""): 근접 세트 → 원거리 세트 순.
static func _wa_weapon(c: Node, key: String) -> String:
	var wa := RulesDB.get_entry("weapon_action", key)
	var wk := str(wa.get("weapon_kind", ""))
	if wa.has("group") and (wk == "" or str(wa.get("kind", "")) in ["self_buff", "ally_temp_hp", "passive", "command"]):
		return "-"  # 무기가 필요 없는 기법(회피 발놀림·재정비·반격·정밀·지휘)
	for set_name: String in ["melee", "ranged"]:
		var wid: String = c.weapon_sets.get(set_name, {}).get("main", "")
		if wid == "":
			continue
		if wk != "":
			var ranged: bool = Combat.is_ranged_weapon(Combat.weapon_data(wid))
			if wk == "any" or (wk == "melee" and not ranged) or (wk == "ranged" and ranged):
				return wid
			continue
		if _base_weapon(wid) in wa.get("weapons", []) and _proficient(c, wid):
			return wid
	return ""


## 기법·비전 사격 자원의 주사위(우월 주사위: 그 자원을 쓰는 기능의 dice_by_level 중 가장 큰 것 — 배틀 마스터 d8→d10, 전투 기법 입문 d6)
static func special_die(c: Node, resource_id: String) -> String:
	var best := "1d6"
	var best_avg := 0.0
	for fid: String in c.feature_data:
		var f: Dictionary = c.feature_data[fid]
		if str(f.get("resource", "")) != resource_id or not f.has("dice_by_level"):
			continue
		var lv: int = c.feature_level(fid)
		var pick := ""
		var pl := 0
		for k: String in f["dice_by_level"]:
			if lv >= int(k) and int(k) >= pl:
				pl = int(k)
				pick = str(f["dice_by_level"][k])
		var avg := float(pick.get_slice("d", 1)) if pick != "" else 0.0
		if avg > best_avg:
			best_avg = avg
			best = pick
	return best


## 마법 무기(items.json base)면 바탕 무기 ID
static func _base_weapon(wid: String) -> String:
	return str(Combat.weapon_data(wid).get("id", wid))


static func _proficient(c: Node, wid: String) -> bool:
	var w := Combat.weapon_data(wid)
	var cat: String = str(w.get("category", "")).get_slice("_", 0)
	return c.weapon_proficiencies.has(cat) or c.weapon_proficiencies.has(str(w.get("id", wid))) or c.has_meta("monster")


## 무기 액션 DC(BG3) = 8 + 숙련 보너스 + 근력·민첩 중 높은 수정치 + dc_bonus.
## dc "hybrid"면 (그것 + 2)와 주문 내성 DC 중 높은 쪽(울리는 일격).
static func weapon_action_dc(c: Node, key: String) -> int:
	var wa := RulesDB.get_entry("weapon_action", key)
	var dc: int = 8 + c.proficiency_bonus + maxi(c.ability_mod("str"), c.ability_mod("dex")) + int(wa.get("dc_bonus", 0))
	if str(wa.get("dc", "weapon")) == "int":
		return 8 + c.proficiency_bonus + c.ability_mod("int")  # 비전 사격: 지능
	if str(wa.get("dc", "weapon")) == "hybrid":
		var sdc: int = Spellcasting.spell_dc(c) if c.spellcasting_ability != "" else 0
		dc = maxi(dc + 2, sdc)
	return dc


static func _size_rank(s: String) -> int:
	return ["tiny", "small", "medium", "large", "huge", "gargantuan"].find(s)


## 무기를 든 대상인가(무기 쳐내기): 캐릭터는 쥔 무기, 몬스터는 무기 이름의 공격이 있으면.
static func _has_weapon(t: Node) -> bool:
	if t.has_meta("monster"):
		return preload("res://scripts/rules/monster_factory.gd").actions(t).any(func(a: Dictionary) -> bool:
			return a.get("type", "") == "attack" and RulesDB.has_entry("weapon", str(a["id"])))
	return t.weapon("main") != "" and t.weapon("main") != "unarmed"


static func _weapon_action(world: Dictionary, c: Node, key: String, t: Node) -> Dictionary:
	var wa := RulesDB.get_entry("weapon_action", key)
	var wid := _wa_weapon(c, key)
	if wid == "":
		return {"ok": false, "reason": "이 무기로는 쓸 수 없다"}
	if wa.has("group"):
		return _special_attack(world, c, key, wa, wid, t)
	var cost := str(wa["cost"])
	# 자세(버티기·조준·힘 모으기): 이동력을 쓰고 이번 턴 효과
	if wa.has("stance"):
		var mv := int(wa.get("move_tiles", 0))
		if int(c.turn.get("movement", 0)) < mv:
			return {"ok": false, "reason": "이동력이 모자란다"}
		c.turn["movement"] = int(c.turn["movement"]) - mv
		c.turn["stance_" + str(wa["stance"])] = true
		c.spend_resource(key)
		Dice.log_text("%s: %s" % [c.label(), wa["name"]["ko"]])
		return {"ok": true}
	if t == null or t.dead:
		return {"ok": false, "reason": "대상이 없다"}
	if wa.has("max_size") and _size_rank(str(t.size)) > _size_rank(str(wa["max_size"])):
		return {"ok": false, "reason": "너무 큰 대상"}
	if wa.get("needs_weapon", false) and not _has_weapon(t):
		return {"ok": false, "reason": "무기를 든 대상만"}
	var grid: Node = world["grid"]
	# 돌진: 6칸 안 적에게 달려가 붙는다(이동력을 쓴다 — 기회 공격은 그대로)
	if wa.has("charge_tiles") and grid.distance_between(c, t) > 1:
		if grid.distance_between(c, t) > int(wa["charge_tiles"]):
			return {"ok": false, "reason": "너무 멀다(%d칸까지)" % int(wa["charge_tiles"])}
		var best := Vector2i(-1, -1)
		var best_d := 999
		for dd: Vector2i in grid.DIRS_8:
			var cell: Vector2i = grid.cell_of(t) + dd
			if grid.in_bounds(cell) and not grid.blocks_movement(cell) and grid.creature_at(cell) == null:
				var d0: int = grid.distance(grid.cell_of(c), cell)
				if d0 < best_d:
					best_d = d0
					best = cell
		if best.x < 0 or not Combat.can_spend(c, "action") and int(c.turn.get("attacks_left", 0)) <= 0:
			return {"ok": false, "reason": "달려갈 곳이 없다"}
		var mres := Combat.move(world, c, best)
		if not mres.get("ok", false) or c.dead or c.is_down() or grid.distance_between(c, t) > 1:
			return {"ok": false, "reason": mres.get("reason", "닿지 못했다")}
	# 비용: action은 공격 행동의 공격 하나(남은 추가 공격이 있으면 그것을 쓴다), 나머지는 그 비용
	if cost == "action":
		if int(c.turn.get("attacks_left", 0)) <= 0:
			if not Combat.spend(c, "action"):
				return {"ok": false, "reason": "행동이 없다"}
			c.turn["attacks_left"] = c.attacks_per_action
		c.turn["attacks_left"] = int(c.turn["attacks_left"]) - 1
	elif not Combat.spend(c, cost):
		return {"ok": false, "reason": "비용이 없다"}
	var set_name := "ranged" if c.weapon_sets.get("ranged", {}).get("main", "") == wid else "melee"
	if c.active_set != set_name:
		Combat.switch_weapon_set(c)
	var atk := Combat.build_weapon_attack(c, wid)
	if wa.has("damage"):
		var dtype := str(wa.get("damage_type", atk["damage"][0]["damage_type"]))
		var mod := 0 if wa.get("no_mod", false) else int(atk["ability_mod"])
		atk["damage"] = [{"dice": "%s%+d" % [wa["damage"], mod] if mod != 0 else str(wa["damage"]), "damage_type": dtype}]
	if wa.get("half_damage", false):
		atk["half_damage"] = true
	atk["name"] = str(wa.get("name", {}).get("ko", wa["id"]))
	var res := Combat._do_attack(world, c, t, atk)
	if not res.get("ok", true):
		return res
	c.spend_resource(key)  # 빗나가도 쓴 것(BG3)
	_wa_condition(c, key, t, res)
	# 휩쓸기: 대상 곁(1칸)이면서 내 도달 안, 대상 쪽에 있는 적 최대 (cleave_targets - 1)명
	if int(wa.get("cleave_targets", 0)) > 1:
		var extra: Array = []
		var me: Vector2i = grid.cell_of(c)
		var dir: Vector2i = grid.cell_of(t) - me
		for o: Node in grid.creatures():
			if extra.size() >= int(wa["cleave_targets"]) - 1:
				break
			if o == t or o == c or o.dead or not c.is_hostile_to(o):
				continue
			var v: Vector2i = grid.cell_of(o) - me
			if grid.distance_between(o, t) <= 1 and grid.distance_between(c, o) <= Combat.reach_of(c) and v.x * dir.x + v.y * dir.y >= 0:
				extra.append(o)
		res["cleave"] = []
		for o: Node in extra:
			var atk2 := atk.duplicate(true)
			res["cleave"].append(Combat._do_attack(world, c, o, atk2))
	if world.get("turns") != null:
		world["turns"].notify_hostile_action(c)
	return res


## 기법(배틀 마스터)·비전 사격(아케인 아처): 배운 것만, 자원(우월 주사위·비전 화살)을 쓴다. kind별 장치.
static func _special_attack(world: Dictionary, c: Node, key: String, wa: Dictionary, wid: String, t: Node) -> Dictionary:
	var grid: Node = world["grid"]
	var res_id := str(wa.get("resource", ""))
	if res_id != "" and c.resource(res_id) <= 0:
		return {"ok": false, "reason": "남은 횟수가 없다"}
	var kind := str(wa.get("kind", ""))
	var die := special_die(c, res_id)
	var name := str(wa["name"]["ko"])
	match kind:
		"self_buff":
			c.spend_resource(res_id)
			c.apply_condition(str(wa["condition"]), int(wa.get("turns", 1)), c)
			Dice.log_text("%s: %s" % [c.label(), name])
			return {"ok": true}
		"ally_temp_hp":
			if t == null or t.dead or c.is_hostile_to(t) or grid.distance_between(c, t) > int(wa.get("range_tiles", 12)):
				return {"ok": false, "reason": "아군을 골라야 한다"}
			if not Combat.spend(c, str(wa["cost"])):
				return {"ok": false, "reason": "보너스 행동이 없다"}
			c.spend_resource(res_id)
			if t.is_down():
				Resolver.heal(t, 1, c)  # 쓰러진 아군은 먼저 HP 1로
			Resolver.grant_temp_hp(t, int(wa.get("temp_hp", 8)))
			Dice.log_text("%s %s → %s 임시 HP %d" % [c.label(), name, t.label(), int(wa.get("temp_hp", 8))])
			return {"ok": true}
		"passive":
			return {"ok": false, "reason": "상시 설정으로 쓴다"}
	if t == null or t.dead:
		return {"ok": false, "reason": "대상이 없다"}
	if wa.has("max_size") and _size_rank(str(t.size)) > _size_rank(str(wa["max_size"])):
		return {"ok": false, "reason": "너무 큰 대상"}
	if wa.get("needs_weapon", false) and not _has_weapon(t):
		return {"ok": false, "reason": "무기를 든 대상만"}
	# 지휘 일격: 대상 곁의 아군이 반응으로 근접 무기 공격(우월 주사위 피해) — 내 공격 하나 + 보너스 행동
	var helper: Node = null
	if kind == "command":
		for o: Node in grid.creatures():
			if o != c and not o.dead and not o.is_hostile_to(c) and o.can_react() and grid.distance_between(o, t) <= Combat.reach_of(o) \
					and o.active_set == "melee" and o.weapon("main") != "" and not Combat.is_ranged_weapon(Combat.weapon_data(o.weapon("main"))):
				helper = o
				break
		if helper == null:
			return {"ok": false, "reason": "대상 곁에 근접 무기를 든 아군이 없다"}
	if str(wa.get("also_costs", "")) != "" and not Combat.can_spend(c, str(wa["also_costs"])):
		return {"ok": false, "reason": "보너스 행동이 없다"}
	# 비용: 행동이면 공격 행동의 공격 하나
	if str(wa["cost"]) == "action":
		if int(c.turn.get("attacks_left", 0)) <= 0:
			if not Combat.spend(c, "action"):
				return {"ok": false, "reason": "행동이 없다"}
			c.turn["attacks_left"] = c.attacks_per_action
		c.turn["attacks_left"] = int(c.turn["attacks_left"]) - 1
	if str(wa.get("also_costs", "")) != "":
		Combat.spend(c, str(wa["also_costs"]))
	var out := {"ok": true}
	if kind == "command":
		c.spend_resource(res_id)
		helper.turn["reaction"] = int(helper.turn.get("reaction", 1)) - 1
		var hatk := Combat.build_weapon_attack(helper, helper.weapon("main"))
		hatk["damage"] = hatk["damage"] + [{"dice": die, "damage_type": hatk["damage"][0]["damage_type"]}]
		hatk["name"] = "%s(%s)" % [name, helper.label()]
		out = Combat._do_attack(world, helper, t, hatk)
		out["ok"] = true
		if world.get("turns") != null:
			world["turns"].notify_hostile_action(c)
		return out
	if wid != "-":
		var set_name := "ranged" if c.weapon_sets.get("ranged", {}).get("main", "") == wid else "melee"
		if c.active_set != set_name:
			Combat.switch_weapon_set(c)
	var atk := Combat.build_weapon_attack(c, wid)
	atk["name"] = name
	if atk["kind"] == "ranged" and c.has_cap("magic_ranged"):
		atk["magical"] = true
	for e: Dictionary in wa.get("extra_damage", []):
		var dice: String = die if str(e["dice"]) == "superiority" else str(e["dice"])
		var dt: String = atk["damage"][0]["damage_type"] if str(e["damage_type"]) == "weapon" else str(e["damage_type"])
		atk["damage"] = atk["damage"] + [{"dice": dice, "damage_type": dt}]
	if wa.get("advantage", false):
		atk["advantage_add"] = [name]
	match kind:
		"sweep":
			# 휩쓸어 치기: 앞쪽 호(대상 쪽, 내 도달 안)의 적 모두, 피해는 우월 주사위만
			c.spend_resource(res_id)
			atk["damage"] = [{"dice": die, "damage_type": atk["damage"][0]["damage_type"]}]
			atk["flat_damage"] = 0
			var me: Vector2i = grid.cell_of(c)
			var dir: Vector2i = grid.cell_of(t) - me
			out["sweep"] = []
			for o: Node in grid.creatures().duplicate():
				if o == c or o.dead or not c.is_hostile_to(o) or grid.distance_between(c, o) > Combat.reach_of(c):
					continue
				var v: Vector2i = grid.cell_of(o) - me
				if o == t or v.x * dir.x + v.y * dir.y > 0:
					out["sweep"].append(Combat._do_attack(world, c, o, atk.duplicate(true)))
		"line":
			# 관통 화살: 곧게 line_tiles 선 위 모두 민첩 내성 — 무기 피해, 실패하면 추가 피해(명중 굴림 없음)
			c.spend_resource(res_id)
			var from: Vector2i = grid.cell_of(c)
			var step := Vector2i(signi(grid.cell_of(t).x - from.x), signi(grid.cell_of(t).y - from.y))
			var hit_list: Array = []
			var cur := from
			for i in int(wa.get("line_tiles", 7)):
				cur += step
				if not grid.in_bounds(cur) or grid.has_flag(cur, "wall"):
					break
				var o: Node = grid.creature_at(cur)
				if o != null and o != c and not o in hit_list:
					hit_list.append(o)
			out["line"] = []
			for o: Node in hit_list:
				var sv := Resolver.saving_throw(o, str(wa["save"]), weapon_action_dc(c, key), {"source": c})
				var dmg: int = Dice.roll(atk["damage"][0]["dice"], name)["total"]
				var parts := [{"amount": dmg, "damage_type": atk["damage"][0]["damage_type"]}]
				if not sv["success"]:
					parts.append({"amount": Dice.roll(str(wa["line_extra"]["dice"]), name)["total"], "damage_type": str(wa["line_extra"]["damage_type"])})
				out["line"].append(Resolver.apply_damage(o, parts, {"attacker": c}))
		"auto_hit":
			# 추적 화살: 굴림 없이 맞는다
			c.spend_resource(res_id)
			var parts2: Array = []
			for p: Dictionary in atk["damage"]:
				parts2.append({"amount": Dice.roll(str(p["dice"]), name)["total"], "damage_type": p["damage_type"]})
			out["damage"] = Resolver.apply_damage(t, parts2, {"attacker": c})
			out["hit"] = true
			_wa_condition(c, key, t, out)
		_:
			out = Combat._do_attack(world, c, t, atk)
			if not out.get("ok", true):
				return out
			if out.get("hit", false) or str(wa.get("consume", "hit")) == "always":
				c.spend_resource(res_id)
			_wa_condition(c, key, t, out)
			if out.get("hit", false) and not t.dead:
				if int(wa.get("push_tiles", 0)) > 0:
					var sv2 := Resolver.saving_throw(t, str(wa["save"]), weapon_action_dc(c, key), {"source": c})
					if not sv2["success"]:
						out["push"] = Combat._push_up_to(world, c, t, int(wa["push_tiles"]))
				if wa.has("ally_condition"):
					var best: Node = null
					for o: Node in grid.creatures():
						if o != c and not o.dead and not o.is_hostile_to(c) and grid.distance_between(c, o) <= 6 \
								and (best == null or grid.distance_between(c, o) < grid.distance_between(c, best)):
							best = o
					if best != null:
						best.apply_condition(str(wa["ally_condition"]), int(wa.get("turns", 1)), c)
			if out.get("hit", false) and wa.has("burst_tiles"):
				var bd: Dictionary = wa["burst_damage"]
				var amount: int = Dice.roll(str(bd["dice"]), name)["total"]
				for o: Node in grid.creatures().duplicate():
					if not o.dead and grid.distance_between(o, t) <= int(wa["burst_tiles"]):
						Resolver.apply_damage(o, [{"amount": amount, "damage_type": str(bd["damage_type"])}], {"attacker": c})
	out["ok"] = true
	if world.get("turns") != null:
		world["turns"].notify_hostile_action(c)
	return out


static func _wa_condition(c: Node, key: String, t: Node, res: Dictionary) -> void:
	var wa := RulesDB.get_entry("weapon_action", key)
	if not res.get("hit", false) or not wa.has("condition") or t.dead or str(wa.get("kind", "")) == "self_buff":
		return
	if not wa.has("save"):
		t.apply_condition(str(wa["condition"]), int(wa.get("turns", 1)), c)  # 내성 없는 상태(주의 돌리기)
		return
	var sv := Resolver.saving_throw(t, str(wa["save"]), weapon_action_dc(c, key), {"source": c})
	res["wa_save"] = sv
	if not sv["success"]:
		var turns := int(wa.get("turns", 1))
		if wa.has("double_turns_cap") and c.has_cap(str(wa["double_turns_cap"])):
			turns *= 2  # 석궁 명수: 관통 사격 상처 2배
		t.apply_condition(str(wa["condition"]), turns, c)


## 끈기(무기 액션 반응, 횟수 제한 없음): 근접 무기 공격이 빗나가면 반응으로 근력 수정치(최소 1) 타격 피해.
## 상시 설정 options["wa_follow_through"](기본 켬). Combat._do_attack 뒤 빗나감에서 부른다.
static func follow_through(c: Node, t: Node, atk: Dictionary, res: Dictionary) -> void:
	if res.get("hit", true) or not res.get("valid", false) or t == null or t.dead or atk.get("kind", "") != "melee" or not atk.get("weapon", false):
		return
	if str(c.options.get("wa_follow_through", "on")) != "on" or not c.can_react():
		return
	var wid := str(atk.get("weapon_id", ""))
	if not "wa_follow_through" in weapon_actions_for(c) or _wa_weapon(c, "wa_follow_through") != wid:
		return
	c.turn["reaction"] = int(c.turn.get("reaction", 1)) - 1
	res["follow_through"] = Resolver.apply_damage(t, [{"amount": maxi(1, c.ability_mod("str")), "damage_type": "bludgeoning"}], {"attacker": c})
	Dice.log_text("%s 끈기: 빗나갔지만 %d" % [c.label(), maxi(1, c.ability_mod("str"))])


# ======================================================================
# 재주 행동(BG3 재주 묶음 B)
# ======================================================================

## 강타 추가 공격(대형 무기 강타): 치명타·처치 뒤 보너스 행동으로 쥔 근접 무기 공격 1회.
static func _bonus_weapon_attack(world: Dictionary, c: Node, t: Node, flag: String = "bonus_attack_ready") -> Dictionary:
	if t == null or not c.turn.get(flag, false):
		return {"ok": false, "reason": "지금은 쓸 수 없다"}
	if flag != "bonus_attack_ready":
		if not Combat.spend(c, "bonus"):
			return {"ok": false, "reason": "보너스 행동이 없다"}
		c.turn[flag] = false
		var watk := Combat.build_weapon_attack(c, c.weapon("main"))
		watk["name"] = "전쟁 마법 공격"
		return Combat._do_attack(world, c, t, watk)
	if c.active_set != "melee":
		Combat.switch_weapon_set(c)
	if not Combat.spend(c, "bonus"):
		return {"ok": false, "reason": "보너스 행동이 없다"}
	c.turn["bonus_attack_ready"] = false
	c.turn["bonus_attack_used"] = true
	var atk := Combat.build_weapon_attack(c, c.weapon("main"))
	atk["name"] = "강타 추가 공격"
	return Combat._do_attack(world, c, t, atk)


## 자루 공격(장병기 달인): 장병기로 공격한 턴에 보너스 행동 1d4 타격 + 근력·민첩 중 높은 수정치(턴당 1회).
static func _haft_strike(world: Dictionary, c: Node, t: Node) -> Dictionary:
	if t == null or not c.turn.get("haft_ready", false):
		return {"ok": false, "reason": "지금은 쓸 수 없다"}
	if not Combat.spend(c, "bonus"):
		return {"ok": false, "reason": "보너스 행동이 없다"}
	c.turn["haft_ready"] = false
	c.turn["haft_used"] = true
	var atk := Combat.build_weapon_attack(c, c.weapon("main"))
	var mod := maxi(c.ability_mod("str"), c.ability_mod("dex"))
	atk["damage"] = [{"dice": "1d4%+d" % mod if mod != 0 else "1d4", "damage_type": "bludgeoning"}]
	atk["flat_damage"] = int(atk.get("flat_damage", 0))
	atk["name"] = "자루 공격"
	return Combat._do_attack(world, c, t, atk)


## 돌격(돌격병): 행동 + 보너스 행동. 곧은 선으로 6칸까지 기회 공격 없이 달려가(이동력은 쓰지 않는다) 처음 만나는 적에게
## 무기 공격(피해 +5, 공격 행동의 공격 하나 — 추가 공격과 이어짐) 또는 밀치기.
static func _charge(world: Dictionary, c: Node, t: Node, shove: bool) -> Dictionary:
	var grid: Node = world["grid"]
	if t == null or t.dead or not c.is_hostile_to(t):
		return {"ok": false, "reason": "적을 골라야 한다"}
	var from: Vector2i = grid.cell_of(c)
	var goal: Vector2i = grid.cell_of(t)
	if grid.distance(from, goal) > 7:
		return {"ok": false, "reason": "너무 멀다(6칸까지)"}
	# 곧은 선: 한 칸씩 목표 쪽으로. 처음 만나는 적이 대상이 된다.
	var cur := from
	var hit: Node = null
	while true:
		var step := Vector2i(signi(goal.x - cur.x), signi(goal.y - cur.y))
		var nxt := cur + step
		var o: Node = grid.creature_at(nxt)
		if o != null and o != c:
			if c.is_hostile_to(o):
				hit = o
			break
		if not grid.can_step_sized(cur, nxt, grid.size_of(c), c, []) or grid.distance(from, nxt) > 6:
			break
		cur = nxt
	if hit == null:
		return {"ok": false, "reason": "가는 길에 적이 없다"}
	if not Combat.can_spend(c, "bonus") or (int(c.turn.get("attacks_left", 0)) <= 0 and not Combat.can_spend(c, "action")):
		return {"ok": false, "reason": "행동과 보너스 행동이 필요하다"}
	if cur != from:
		grid.move_creature(c, cur)  # 돌진: 기회 공격 없음, 이동력 쓰지 않음
	Combat.spend(c, "bonus")
	if int(c.turn.get("attacks_left", 0)) <= 0:
		Combat.spend(c, "action")
		c.turn["attacks_left"] = c.attacks_per_action
	c.turn["attacks_left"] = int(c.turn["attacks_left"]) - 1
	if shove:
		var plan := Physics.plan_shove(grid, c, hit)
		if not plan["valid"]:
			return {"ok": true, "reason": plan["reason"], "moved": cur != from}
		var r := Physics.shove(grid, c, hit, false)
		r["ok"] = true
		return r
	if c.active_set != "melee":
		Combat.switch_weapon_set(c)
	var atk := Combat.build_weapon_attack(c, c.weapon("main"))
	atk["flat_damage"] = int(atk.get("flat_damage", 0)) + 5
	atk["name"] = "돌격 공격"
	var res := Combat._do_attack(world, c, hit, atk)
	if world.get("turns") != null:
		world["turns"].notify_hostile_action(c)
	return res


## 주문 두루마리(SRD 원문, 룰북 6단계): 내 클래스 주문 목록에 있는 주문이면 읽는다.
static func can_read_scroll(c: Node, item: Dictionary) -> bool:
	var sp := RulesDB.get_entry("spell", str(item.get("spell", "")))
	var list := str(RulesDB.get_entry("class", c.class_id).get("spellcasting", {}).get("list", ""))
	return not sp.is_empty() and list != "" and list in sp.get("classes", [])


## 두루마리로 한 번 시전: 슬롯 없이, 두루마리 DC·공격 보너스로. 시전하면 두루마리가 사라진다.
static func read_scroll(world: Dictionary, c: Node, item_id: String, cell: Vector2i) -> Dictionary:
	var item := RulesDB.get_entry("item", item_id)
	if item.get("category", "") != "scroll" or Interact.count(world, item_id, c) <= 0:
		return {"ok": false, "reason": "두루마리가 없다"}
	if not can_read_scroll(c, item):
		return {"ok": false, "reason": "내 클래스 주문 목록에 없는 주문"}
	c.set_meta("scroll_cast", {"dc": int(item.get("save_dc", 13)), "attack": int(item.get("attack_bonus", 5))})
	var r: Dictionary = Spellcasting.cast(world, c, str(item["spell"]), cell, {"no_slot": true})
	c.remove_meta("scroll_cast")
	if r.get("ok", false):
		Interact.take(world, item_id, 1, c)
	return r


static func sneak_dice(c: Node) -> int:
	var table: Dictionary = c.feature_data.get("sneak_attack", {}).get("dice_by_level", {"1": "1d6"})
	var best := 1
	var best_lv := 0
	for lv: String in table:
		if c.feature_level("sneak_attack") >= int(lv) and int(lv) > best_lv:
			best_lv = int(lv)
			best = int(str(table[lv]).get_slice("d", 0))
	return best


# ======================================================================
# 상시 발동(BG3 패시브 탭): 켜고 끄는 설정
# ======================================================================

## [{"id", "name": {ko,en}, "state": 표시 글, "desc"}] — 기능 데이터 toggle(상시 발동 설정)과 반응 설정
static func passives(c: Node) -> Array:
	var out: Array = []
	for fid: String in c.feature_data:
		var f: Dictionary = c.feature_data[fid]
		if not f.has("toggle"):
			continue
		var vals: Array = f["toggle"]["values"]
		var cur := str(c.options.get(fid, vals[0]["id"]))
		var name_of: Dictionary = vals[0]["name"]
		for v: Dictionary in vals:
			if str(v["id"]) == cur:
				name_of = v["name"]
		out.append({"id": fid, "name": f.get("name", {"ko": fid, "en": fid}), "state": name_of,
			"desc": f["toggle"].get("desc", {"ko": "", "en": ""})})
	for r: String in c.known_reactions:
		var st: String = c.reaction_setting(r)
		out.append({"id": "reaction:" + r, "name": reaction_name(c, r),
			"state": {"ko": "자동" if st != "off" else "끄기", "en": "Auto" if st != "off" else "Off"},
			"desc": {"ko": "반응 설정(누를 때마다 자동/끄기).", "en": "Reaction setting (click to toggle)."}})
	# 반응형 무기 액션(끈기): 쥔 무기가 주면 상시 설정에
	for wa: String in weapon_actions_for(c):
		var d := RulesDB.get_entry("weapon_action", wa)
		if str(d["cost"]) in ["reaction", "passive"]:
			var on := str(c.options.get(wa, "on")) == "on"
			out.append({"id": wa, "name": d["name"], "state": {"ko": "자동" if on else "끄기", "en": "Auto" if on else "Off"}, "desc": d["desc"]})
	return out


## 반응 이름: 주문이면 주문 이름, 기능이면 기능 이름(코드에 이름 표를 두지 않는다)
static func reaction_name(c: Node, r: String) -> Dictionary:
	if r == "opportunity_attack":
		return {"ko": "기회 공격", "en": "Opportunity Attack"}
	var sp := RulesDB.get_entry("spell", r)
	if not sp.is_empty():
		return {"ko": sp["name"].get("ko") if sp["name"].get("ko") != null else sp["name"]["en"], "en": sp["name"]["en"]}
	if c.feature_data.has(r):
		return c.feature_data[r].get("name", {"ko": r, "en": r})
	return {"ko": r, "en": r}


static func toggle_passive(c: Node, id: String) -> void:
	if id.begins_with("reaction:"):
		var r := id.trim_prefix("reaction:")
		c.reaction_settings[r] = "auto" if c.reaction_setting(r) == "off" else "off"
		return
	if id.begins_with("wa_"):
		c.options[id] = "off" if str(c.options.get(id, "on")) == "on" else "on"  # 끈기 켜기·끄기
		return
	var f: Dictionary = c.feature_data.get(id, {})
	if not f.has("toggle"):
		return
	var mins: Dictionary = f.get("choice_min_level", {})
	var lv: int = c.feature_level(id)
	var ids: Array = f["toggle"]["values"].map(func(v: Dictionary) -> String: return str(v["id"])).filter(
		func(v: String) -> bool: return lv >= int(mins.get(v, 0)))  # 레벨이 안 된 선택지는 건너뛴다(교묘한 일격 14레벨 등)
	var cur := str(c.options.get(id, ids[0]))
	c.options[id] = ids[(ids.find(cur) + 1) % ids.size()]


static func _entity_action(world: Dictionary, c: Node, kind: String, cell: Vector2i, t: Node) -> Dictionary:
	var grid: Node = world["grid"]
	var inst := SpellUtil.find_entity(c, kind)
	if inst.is_empty():
		return {"ok": false, "reason": "주문이 끝났다"}
	var e: Dictionary = inst["entity"]
	var cost: String = ENTITY_ACTIONS[kind]["cost"]
	if not Combat.spend(c, cost):
		return {"ok": false, "reason": "비용이 없다"}
	var Summon := load("res://scripts/rules/effects/summon.gd")
	match kind:
		"spiritual_weapon":
			if t == null:
				return {"ok": false, "reason": "적을 골라야 한다"}
			var best := Vector2i(-1, -1)
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var n: Vector2i = grid.cell_of(t) + Vector2i(dx, dy)
					if grid.in_bounds(n) and grid.distance(n, e["cell"]) <= 4 and (best.x < 0 or grid.distance(n, e["cell"]) < grid.distance(best, e["cell"])):
						best = n
			if best.x < 0:
				return {"ok": false, "reason": "너무 멀다(4칸)"}
			e["cell"] = best
			return Summon.strike(world, c, inst, best, t)
		"flaming_sphere":
			var path: Array[Vector2i] = []
			var cur: Vector2i = e["cell"]
			for i in 6:
				if cur == cell:
					break
				var nxt := cur + Vector2i(signi(cell.x - cur.x), signi(cell.y - cur.y))
				if grid.blocks_movement(nxt):
					break
				cur = nxt
				path.append(cur)
				var hit: Node = grid.creature_at(cur)
				if hit != null and not hit.dead:
					Summon.sphere_burn(world, hit, inst, Spellcasting.spell_dc(c))
					break
			e["cell"] = cur
			if world.get("surfaces") != null and not path.is_empty():
				world["surfaces"].tile_damage(path, "fire")
			return {"ok": true, "path": path}
		"mage_hand":
			if grid.distance(grid.cell_of(c), cell) > 6:
				return {"ok": false, "reason": "6칸 안만"}
			e["cell"] = cell
			for tr: Dictionary in world.get("traps", []):
				if tr["state"] == "armed" and tr.get("found", false) and Vector2i(int(tr["cell"][0]), int(tr["cell"][1])) == cell:
					Interact.trigger(world, tr)
					return {"ok": true, "triggered": true}
			if not grid.object_at(cell).get("loot", {}).is_empty():
				return Interact.take_loot(world, c, cell)
			return {"ok": true}
	return {"ok": false}
