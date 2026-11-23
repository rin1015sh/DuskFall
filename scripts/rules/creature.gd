extends Node
## 생물(규칙 데이터만). 룰북 8단계 'Godot 구조' — 능력치·상태·자원. 스프라이트와 분리한다.
## 판정은 Resolver가 하고, 여기는 값과 상태 목록, 그 값에서 바로 나오는 계산만 둔다.

const ABILITIES := ["str", "dex", "con", "int", "wis", "cha"]

var display_name := {"ko": "", "en": ""}
## 플레이어 캐릭터·동료면 true. 0 HP에서 쓰러져 사망 내성을 굴린다. 몬스터는 즉사(7단계).
var is_player_character := false
var abilities := {"str": 10, "dex": 10, "con": 10, "int": 10, "wis": 10, "cha": 10}
var proficiency_bonus := 2
var save_proficiencies: Array = []
## 기능 판정 추가 보너스(기능 숙련 계산은 6단계에서 데이터로 옮긴다).
var skill_bonuses := {}
var ac_base := 10
var speed_tiles := 6
## 무게(kg). 밀치기·던지기에 쓴다(3·4단계). 기본값은 보통 체형 인간 정도.
var weight_kg := 70.0
var hp_max := 1
var hp := 1
var temp_hp := 0
var damage_resistances: Array = []
var damage_vulnerabilities: Array = []
var damage_immunities: Array = []
var condition_immunities: Array = []
## 감각 태그: "darkvision", "see_invisible", "truesight" 등.
var senses: Array = []
## 자원: id → {"current": int, "max": int} (주문 슬롯, 클래스 자원 등)
var resources := {}
## 걸린 상태: {"id", "turns_left"(-1 = 풀릴 때까지), "source"(생물 또는 문자열), "params"}
var conditions: Array[Dictionary] = []
## 상태 밖에서 붙은 수정치(주문 등): {"effect": 효과 Dictionary, "turns_left", "source"}
var extra_modifiers: Array[Dictionary] = []
## 유지 중인 집중. 비어 있으면 집중하지 않음. {"id": 주문 ID, ...}
var concentration := {}
var death_saves := {"successes": 0, "failures": 0}
var stable := false
var dead := false

# ---------- 전투(3단계) ----------
## 편: "party", "enemy", "neutral". 다른 편끼리 적대.
var team := "neutral"
## 무기 세트(근접·원거리 2세트, 전환 무료): {"melee": {"main", "off"}, "ranged": {"main"}} — 무기 ID
var weapon_sets := {"melee": {"main": "", "off": ""}, "ranged": {"main": ""}}
var active_set := "melee"
## 숙련 무기 분류: "simple", "martial" 또는 무기 ID
var weapon_proficiencies: Array = ["simple"]
## 마스터리를 쓸 수 있는 무기 ID(6단계 무기 마스터리 기능)
## 공격 행동 한 번의 공격 횟수(추가 공격이면 2)
var attacks_per_action := 1
## 재주·기능 ID(표시·이름 조회용). 엔진 메커니즘은 caps로 검사한다.
var features: Array = []
## 능력 태그(data/rules/capabilities.json): 기능 caps·grants.caps·재주 tags를 모은 것. 같은 태그를 여러 기능이 주면 여러 번 들어 있다(cap_count).
var caps: Array = []
## 알고 있는 반응: "opportunity_attack"(누구나), "shield" 등
var known_reactions: Array = ["opportunity_attack"]
## 반응 설정: 반응 ID → "ask" | "auto" | "off"(기본 ask, 기회 공격 기본 auto)
var reaction_settings := {}
## 상시 발동 설정(BG3 패시브 탭): {"sneak_attack": "auto"|"manual", "cunning_strike": ""|"poison"|"trip"|"withdraw"}
var options := {}
## 재충전 쿨다운: 능력 ID → 남은 턴(2단계 몬스터 재충전)
var cooldowns := {}
## 이번 턴 자원(TurnManager가 턴 시작에 채운다)
var turn := {}
var initiative := 0
## 캐릭터 레벨(소마법 강화 등), 주문 시전 능력, 쓸 수 있는 주문 ID
var level := 1
var spellcasting_ability := ""
var spells := []
## 소지품(BG3식 캐릭터마다 {아이템 ID: 개수}, 금화 포함)과 장비 칸(equipment.gd — 칸 → 아이템 ID)
var inventory := {}
var equipment := {}
## 주문 준비(spell_prep.gd): 주문서(주문서형), 지금 준비한 주문(바꿀 수 있는 것), 남은 교체 창(-1 전부·0 닫힘), 창이 열릴 때의 목록
var spellbook := []
var prepared := []
var prep_swaps := 0
var prep_base := []
## 캐릭터 출신·클래스(캐릭터 생성기가 채운다)
var class_id := ""
var subclass_id := ""
## 멀티클래스: 클래스 → 레벨, 클래스 → 하위 클래스, 기능 → 클래스, 클래스 → 준비 주문, 주문 → 클래스(시전 능력)
var class_levels := {}
var subclass_ids := {}
var feature_class := {}
var prepared_by_class := {}
var spell_class := {}
var species_id := ""
var lineage_id := ""
var background_id := ""
## 기능 데이터: 기능 ID → 기능 Dictionary(클래스·종족 데이터의 features 항목)
var feature_data := {}
## 훅 → [스크립트 ID] (Features.hook이 부른다)
var feature_hooks := {}
## 치명타가 되는 최소 자연 굴림(챔피언 19)
var crit_threshold := 20
## 이니셔티브 추가 보너스(경계 재주)
var initiative_bonus := 0
## 암시야 거리(칸). 0이면 없음. senses의 "darkvision"과 함께 쓴다.
var darkvision_tiles := 0
## 내성 보너스 고정값(몬스터 원문 SAVE 행). 있으면 save_bonus가 이 값을 쓴다.
var save_overrides := {}
## 이 상태를 피하는 내성에 유리(드워프 중독, 엘프 매혹, 하플링 공포)
var save_advantage_vs: Array = []
## 이 능력치 내성에 유리(노움)
var save_advantage_abilities: Array = []
## 생물 종류(언데드 퇴치 등): "humanoid", "undead", "beast" ...
var creature_type := "humanoid"
## 크기: "small" | "medium" | "large"
var size := "medium"
# ---------- 탐험(5단계) ----------
## 바라보는 방향(8방향 단위 벡터). 시야 원뿔이 이 방향으로 열린다.
var facing := Vector2i(0, 1)
## 시야 원뿔 길이(칸). 몬스터 데이터 sight_cone_tiles(기본 8).
var sight_tiles := 8
## 탐험 중 은신 켜짐(비용 없이 켜고 끔 — 5단계)
var sneaking := false
## 적이 이 생물을 얼마나 알아챘나: {대상 생물 → {"state": "suspicious"|"searching"|"alerted", "last": 칸}}
var awareness := {}
## 소유자 ID(절도·목격 — 이 생물이 무엇의 주인인가는 물체의 owner)
var faction := ""
## 무기 공격에 붙는 추가 피해(예: 고블린 '유리면 +1d4'): [{"dice", "damage_type"(없으면 무기 유형), "when": "advantage"}]
var attack_riders: Array = []
## 고도(공중 높이 단계): Fly·Levitate. 0이면 땅.
var altitude := 0


## 여러 값을 한 번에 넣는다(테스트·데이터 로드용).
func setup(values: Dictionary) -> Node:
	for key: String in values.keys():
		if key == "abilities":
			for a: String in values[key].keys():
				abilities[a] = values[key][a]
		else:
			set(key, values[key])
	if not values.has("hp"):
		hp = hp_max
	reset_turn()
	return self


func label() -> String:
	if display_name.get("ko", "") != "":
		return display_name["ko"]
	if display_name.get("en", "") != "":
		return display_name["en"]
	return name


# ---------- 능력치 ----------

func ability_mod(ability: String) -> int:
	return floori((int(abilities.get(ability, 10)) - 10) / 2.0)


## 클래스 레벨(멀티클래스). 클래스를 안 주면 주 클래스. 클래스 정보가 없는 생물(몬스터)은 캐릭터 레벨.
func class_level(cid: String = "") -> int:
	if class_levels.is_empty():
		return level
	return int(class_levels.get(cid if cid != "" else class_id, 0))


## 기능을 준 클래스의 레벨(기능 스크립트의 레벨표 — 급소 공격·무술 주사위·몽크 레벨 등).
func feature_level(fid: String) -> int:
	if class_levels.is_empty():
		return level
	return class_level(str(feature_class.get(fid, class_id)))


func save_bonus(ability: String) -> int:
	var flat := 0
	for m in modifier_entries():
		var e: Dictionary = m["effect"]
		if e["type"] == "modify" and e["stat"] == "saving_throw_flat":
			flat += int(e.get("add", 0))  # 보호의 반지·망토 +1
	if save_overrides.has(ability):
		return int(save_overrides[ability]) + flat
	return ability_mod(ability) + (proficiency_bonus if save_proficiencies.has(ability) else 0) + flat


func ac() -> int:
	var value := ac_base
	var floor_ac := 0
	for m in modifier_entries():
		var e: Dictionary = m["effect"]
		if e["type"] == "modify" and e["stat"] == "ac":
			if e.has("set"):
				value = e["set"]
			value += int(e.get("add", 0))
			floor_ac = maxi(floor_ac, int(e.get("floor", 0)))  # AC 바닥값(나무껍질 피부)
		elif e["type"] == "modify" and e["stat"] == "ac_base" and str(get_meta("armor", "")) == "":
			value += 3  # Mage Armor: 갑옷이 없으면 10 + 민첩 → 13 + 민첩
	if has_cap("dual_wield_ac") and weapon("off") != "" and weapon("main") != "" and active_set == "melee":
		value += 1  # 양손 무기술: 양손에 근접 무기
	if has_flag("no_dex_ac"):
		value -= dex_ac_part()  # 비틀거림(무기 액션): AC에 민첩 보너스 없음
	return maxi(value, floor_ac)


## AC에 들어간 민첩 보너스(갑옷 dex_cap 반영, 음수는 그대로 두므로 0 이상만).
func dex_ac_part() -> int:
	var d := maxi(ability_mod("dex"), 0)
	var armor_id := str(get_meta("armor", ""))
	if armor_id != "":
		var a := RulesDB.get_entry("armor", armor_id)
		var cap: Variant = a.get("dex_cap")
		if cap != null and str(a.get("category", "")) == "medium" and has_cap("medium_armor_master"):
			cap = 3
		if cap != null:
			d = mini(d, int(cap))
	return d


func speed() -> int:
	if has_flag("speed_zero"):
		return 0
	var value := speed_tiles
	var mult := 1.0
	for m in modifier_entries():
		var e: Dictionary = m["effect"]
		if e["type"] == "modify" and e["stat"] == "speed_tiles":
			value += int(e.get("add", 0))
			if e.has("multiply"):
				mult = minf(mult, float(e["multiply"]))  # 무게 초과(BG3): 가장 무거운 것 하나만
	return maxi(floori(value * mult), 0)


# ---------- 턴 자원 ----------

## 턴 시작에 행동·보너스 행동·이동·무료 상호작용을 채운다. 반응은 refresh_reaction이 따로 채운다.
func reset_turn() -> void:
	if has_meta("sentinel_stopped"):
		remove_meta("sentinel_stopped")
	var can_act := not is_incapacitated() and not has_flag("cannot_act")
	# 추가 보너스 행동(빠른 손 등 — changes.md 2026-11-22)
	var bonus := (2 if has_cap("extra_bonus_action") else 1) if can_act else 0
	turn = {"action": 1 if can_act else 0, "bonus": bonus, "movement": speed(),
		"interaction": 1, "attacks_left": 0, "light_attack_done": false,
		"disengaged": false, "dashed": false, "reaction": turn.get("reaction", 1),
		"moved": false, "sneak_used": false, "savage_used": false, "free_move_no_oa": 0}
	if has_flag("action_minus_one"):
		turn["action"] = maxi(0, int(turn["action"]) - 1)  # 숨 막힘(무기 액션): 행동 하나 적음
	if has_flag("one_thing_only"):
		turn["bonus"] = 0  # 현혹(교묘한 일격): 이동·행동·보너스 행동 중 하나만 — 행동을 남기고 이동·보너스 행동을 막는다(1차)
		turn["movement"] = 0


func has_feature(id: String) -> bool:
	return features.has(id) or feature_data.has(id)


## 엔진 메커니즘 검사(룰북 1단계 클래스 확장 원칙): 기능 이름이 아니라 능력 태그로.
## 몬스터는 특성 ID가 곧 태그 이름이다(pack_tactics 등) — 그래서 기능 ID도 함께 본다.
func has_cap(cap: String) -> bool:
	return caps.has(cap) or has_feature(cap)


## 같은 태그를 준 기능 수(도약 +1칸처럼 겹치는 메커니즘)
func cap_count(cap: String) -> int:
	return caps.count(cap)


## 그 태그를 준 기능이 쓰는 자원 ID(전술적 판단 = 재기의 숨결 등). 없으면 "".
func cap_resource(cap: String) -> String:
	for fid: String in feature_data:
		var f: Dictionary = feature_data[fid]
		if cap in f.get("caps", []) and f.has("resource"):
			return str(f["resource"])
	return ""


func refresh_reaction() -> void:
	turn["reaction"] = 1


func can_react() -> bool:
	if int(turn.get("reaction", 1)) <= 0 or is_incapacitated() or has_flag("cannot_act") or dead:
		return false
	for m in modifier_entries():
		if m["effect"]["type"] == "modify" and m["effect"]["stat"] == "no_reactions":
			return false  # Slow
	return true


func reaction_setting(id: String) -> String:
	return reaction_settings.get(id, "auto" if id == "opportunity_attack" else "ask")


## 지금 쥔 무기 ID(main 또는 off). 없으면 "".
func weapon(hand: String = "main") -> String:
	return weapon_sets.get(active_set, {}).get(hand, "")


func is_hostile_to(other: Node) -> bool:
	return team != other.team and team != "neutral" and other.team != "neutral"


# ---------- 상태 ----------

## 지금 효과가 있는 상태 정의 목록. 포함 상태(마비 → 무력화)를 풀고, 억제된 상태(윤곽 → 투명)를 뺀다.
## 항목: {"id", "def", "instance"}
func active_conditions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	for inst in conditions:
		_add_active(inst["id"], inst, out, seen)
	var suppressed := {}
	for a in out:
		for s: String in a["def"].get("suppresses", []):
			suppressed[s] = true
	return out.filter(func(a: Dictionary) -> bool: return not suppressed.has(a["id"]))


func _add_active(id: String, inst: Dictionary, out: Array[Dictionary], seen: Dictionary) -> void:
	if seen.has(id):
		return
	var def := RulesDB.get_entry("condition", id)
	if def.is_empty():
		return
	seen[id] = true
	out.append({"id": id, "def": def, "instance": inst})
	for inc: String in def.get("includes", []):
		_add_active(inc, inst, out, seen)


func has_condition(id: String) -> bool:
	for a in active_conditions():
		if a["id"] == id:
			return true
	return false


## 직접 걸린 상태 인스턴스(포함 상태는 아님). 없으면 빈 Dictionary.
func condition_instance(id: String) -> Dictionary:
	for inst in conditions:
		if inst["id"] == id:
			return inst
	return {}


func has_flag(flag: String) -> bool:
	for a in active_conditions():
		var v: Variant = a["def"].get("flags", {}).get(flag)
		if v != null and v != false:
			return true
	return false


## 오르기 지점 없이 높이 차를 오르내린다(2층 작업·Spider Climb·비행).
func is_climber() -> bool:
	return has_cap("climber") or has_flag("climber") or has_flag("flying")


func is_incapacitated() -> bool:
	return has_flag("incapacitated")


func auto_fails_save(ability: String) -> bool:
	for a in active_conditions():
		if ability in a["def"].get("flags", {}).get("auto_fail_saves", []):
			return true
	return false


## 이 거리(칸) 안에서 맞으면 치명타가 되는가(마비·무의식).
func auto_crit_against_within(distance_tiles: int) -> bool:
	for a in active_conditions():
		var r: Variant = a["def"].get("flags", {}).get("auto_crit_within_tiles")
		if r != null and distance_tiles <= int(r):
			return true
	return false


## 모든 수정치: 상태의 modifiers + extra_modifiers. 항목: {"effect", "condition"(없으면 ""), "instance"}
func modifier_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a in active_conditions():
		for e: Dictionary in a["def"].get("modifiers", []):
			out.append({"effect": e, "condition": a["id"], "instance": a["instance"]})
	for m in extra_modifiers:
		out.append({"effect": m["effect"], "condition": "", "instance": m})
	return out


func is_condition_immune(id: String) -> bool:
	if condition_immunities.has(id):
		return true
	if id in ["charmed", "frightened"] and has_cap("mindless_rage") and has_condition("raging"):
		return true  # 광기 없는 분노(광전사 6레벨)
	if load("res://scripts/rules/auras.gd").immune(self, id):
		return true  # 용기·헌신의 오라(팔라딘)
	for a in active_conditions():
		if id in a["def"].get("condition_immunities", []):
			return true
	return false


## 상태를 건다. 면역이면 false. 같은 상태는 남은 지속시간이 긴 쪽만 남는다(4단계 중첩 규칙 1).
## turns: -1 = 풀릴 때까지, 0 = 정의의 기본 지속시간(없으면 -1).
func apply_condition(id: String, turns: int = 0, source: Variant = null, params: Dictionary = {}) -> bool:
	var def := RulesDB.get_entry("condition", id)
	if def.is_empty():
		push_error("모르는 상태 '%s'" % id)
		return false
	if dead or is_condition_immune(id) or creature_type in def.get("immune_creature_types", []):
		return false
	if turns == 0:
		turns = int(def.get("default_duration_turns", -1))
	for r: String in def.get("removes_on_apply", []):
		remove_condition(r)
	var old := condition_instance(id)
	if not old.is_empty():
		if _longer(turns, old["turns_left"]):
			old["turns_left"] = turns
			old["source"] = source
			old["params"] = params
	else:
		conditions.append({"id": id, "turns_left": turns, "source": source, "params": params})
	for extra: String in def.get("also_applies", []):
		apply_condition(extra, -1, source)
	EventBus.on_condition_applied.emit(self, id)
	if is_incapacitated() and not concentration.is_empty():
		break_concentration("무력화")
	return true


func remove_condition(id: String) -> bool:
	for i in conditions.size():
		if conditions[i]["id"] == id:
			conditions.remove_at(i)
			EventBus.on_condition_removed.emit(self, id)
			return true
	return false


## 지속시간을 1턴 줄이고 끝난 상태를 푼다. 언제 부를지는 3단계 TurnManager가 정한다.
func tick_conditions() -> void:
	for inst in conditions.duplicate():
		if inst["turns_left"] > 0:
			inst["turns_left"] -= 1
			if inst["turns_left"] == 0:
				remove_condition(inst["id"])
	for m in extra_modifiers.duplicate():
		if m.get("turns_left", -1) > 0:
			m["turns_left"] -= 1
			if m["turns_left"] == 0:
				extra_modifiers.erase(m)


func _longer(a: int, b: int) -> bool:
	if b < 0:
		return false
	return a < 0 or a > b


# ---------- 피해 유형 ----------

func _damage_list(stat: String, base: Array) -> Array:
	var out := base.duplicate()
	for m in modifier_entries():
		var e: Dictionary = m["effect"]
		if e["type"] == "modify" and e["stat"] == stat:
			out.append_array(e.get("damage_types", []))
	return out


func resists(damage_type: String) -> bool:
	var l := _damage_list("damage_resistance", damage_resistances)
	return l.has(damage_type) or l.has("all")


func vulnerable_to(damage_type: String) -> bool:
	var l := _damage_list("damage_vulnerability", damage_vulnerabilities)
	return l.has(damage_type) or l.has("all")


func immune_to(damage_type: String) -> bool:
	var l := _damage_list("damage_immunity", damage_immunities)
	return l.has(damage_type) or l.has("all")


# ---------- 집중·자원 ----------

func start_concentration(id: String, data: Dictionary = {}) -> void:
	if not concentration.is_empty():
		break_concentration("새 집중")
	concentration = data.duplicate()
	concentration["id"] = id


func break_concentration(reason: String) -> void:
	if concentration.is_empty():
		return
	Dice.log_text("%s의 집중(%s)이 끝났다: %s" % [label(), concentration.get("id", ""), reason])
	var inst: Variant = concentration.get("instance")
	concentration = {}
	if inst != null:
		load("res://scripts/rules/spellcasting.gd").end_instance(inst)


func resource(id: String) -> int:
	return int(resources.get(id, {}).get("current", 0))


## 자원을 쓴다. 모자라면 false.
func spend_resource(id: String, amount: int = 1) -> bool:
	if resource(id) < amount:
		return false
	resources[id]["current"] -= amount
	return true


func is_down() -> bool:
	return hp == 0 and not dead
