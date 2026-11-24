extends RefCounted
## 캐릭터 생성·성장(룰북 6단계). 데이터(classes·species·backgrounds·feats·armor·weapons)를 읽어 Creature를 만든다.
## 같은 명세(spec)에 레벨만 바꿔 다시 만들면 레벨업이다(선택은 명세에 누적해 둔다).
##
## spec = {
##   "name": {"ko", "en"}, "species": "elf", "lineage": "elf_high", "size": "medium"(고를 수 있는 종족),
##   "background": "sage", "class": "wizard", "subclass": "evoker", "level": 1~5,
##   "scores": {"str": 8, ...}(포인트 구매 전 값 8~15), "bonus": {"int": 2, "con": 1}(+2/+1 또는 +1/+1/+1),
##   "skills": [클래스 기능], "species_skill": "perception", "expertise": [...], "extra_skills": [숙련 재주 등],
##   <고르는 기능 id>: 고른 것 — 기능 데이터 choice_kind(feat·expertise·option)대로. 예 "fighting_style": "defense", "divine_order": "protector", "scholar": "arcana",
##   "asi": {"4": {"str": 2}}(4레벨 능력치 향상 또는 {"feat": id, <고르는 +1 능력>: 1}), <고르는 재주 id>: [고른 것](숙련·무기 수련·의식 주문가 등),
##   "cantrips": [...], "spells": [준비 주문 / 주문서],
##   "armor": "chain_mail", "shield": true, "weapons": {"melee": {"main", "off"}, "ranged": {"main"}}
## }

const CreatureScript := preload("res://scripts/rules/creature.gd")
const Levels := preload("res://scripts/rules/levels.gd")
const SpellPrep := preload("res://scripts/rules/spell_prep.gd")
const Equipment := preload("res://scripts/rules/equipment.gd")

const POINT_COST := {8: 0, 9: 1, 10: 2, 11: 3, 12: 4, 13: 5, 14: 7, 15: 9}
const POINT_BUDGET := 27
const ABILITIES := ["str", "dex", "con", "int", "wis", "cha"]
const SKILL_ABILITY := {
	"acrobatics": "dex", "animal_handling": "wis", "arcana": "int", "athletics": "str", "deception": "cha",
	"history": "int", "insight": "wis", "intimidation": "cha", "investigation": "int", "medicine": "wis",
	"nature": "int", "perception": "wis", "performance": "cha", "persuasion": "cha", "religion": "int",
	"sleight_of_hand": "dex", "stealth": "dex", "survival": "wis"}


## 결과: {"creature": Node 또는 null, "errors": PackedStringArray}
static func build(spec: Dictionary) -> Dictionary:
	var errors := validate(spec)
	if not errors.is_empty():
		return {"creature": null, "errors": errors}
	var c: Node = CreatureScript.new()
	apply(c, spec)
	return {"creature": c, "errors": errors}


# ======================================================================
# 검증
# ======================================================================

static func validate(spec: Dictionary) -> PackedStringArray:
	var e := PackedStringArray()
	var entries := class_entries(spec)
	var seen := {}
	for ce: Dictionary in entries:
		if ce["cls"].is_empty():
			e.append("모르는 클래스 '%s'" % ce["id"])
			return e
		if seen.has(ce["id"]):
			e.append("같은 클래스를 두 번 적었다(%s)" % ce["id"])
		seen[ce["id"]] = true
		if int(ce["level"]) < 1:
			e.append("%s 레벨은 1 이상" % ce["id"])
	var cls: Dictionary = entries[0]["cls"]
	var lv := total_level(spec)  # 멀티클래스 선행 조건(능력치 13)은 없다(BG3식 — 사용자 결정 2026-11-23)
	if lv < 1 or lv > Levels.level_cap():
		e.append("레벨 범위는 1~%d(data/rules/progression.json)" % Levels.level_cap())
	var sp := RulesDB.get_entry("species", spec.get("species", ""))
	if sp.is_empty():
		e.append("모르는 종족 '%s'" % spec.get("species", ""))
	elif sp.get("lineage_required", false) and str(spec.get("lineage", "")) != "":
		var lin := RulesDB.get_entry("species", spec.get("lineage", ""))
		if lin.is_empty() or lin.get("parent", "") != sp["id"]:
			e.append("%s의 혈통이 아니다: %s" % [sp["id"], spec.get("lineage", "")])
	if RulesDB.get_entry("background", spec.get("background", "")).is_empty():
		e.append("모르는 배경 '%s'" % spec.get("background", ""))
	e.append_array(validate_point_buy(spec.get("scores", {})))
	e.append_array(validate_bonus(spec.get("bonus", {})))
	var skills: Array = spec.get("skills", [])
	var sk: Dictionary = cls["skills"]
	if skills.size() != int(sk["choose"]):
		e.append("클래스 기능을 %d개 골라야 한다" % sk["choose"])
	for s: String in skills:
		if not s in sk["from"]:
			e.append("%s는 %s 기능 목록에 없다" % [s, cls["id"]])
	for ce: Dictionary in entries:
		var sub_lv := 99
		for sc: Dictionary in ce["cls"].get("subclasses", []):
			sub_lv = mini(sub_lv, int(sc.get("level", 3)))
		var picked := str(spec.get("subclass", "")) if ce["primary"] and spec.get("classes", []).is_empty() else str(ce["entry"].get("subclass", ""))
		if int(ce["level"]) >= sub_lv and picked == "":
			e.append("%s %d레벨부터 하위 클래스를 골라야 한다" % [ce["id"], sub_lv] if not ce["primary"] or not spec.get("classes", []).is_empty() else "%d레벨부터 하위 클래스를 골라야 한다" % sub_lv)
		e.append_array(validate_spells(ce["cls"], spec if ce["primary"] else ce["entry"], int(ce["level"])))
	e.append_array(validate_feat_spells(spec))
	e.append_array(validate_feats(spec, entries))
	e.append_array(validate_sub_spells(spec, entries))
	return e


## 하위 클래스 주문(subclass_spells): 하위 클래스 주문 목록, 슬롯 레벨 이하, 학파 제한(schools 밖은 free_school_by_level개까지)
static func validate_sub_spells(spec: Dictionary, entries: Array) -> PackedStringArray:
	var e := PackedStringArray()
	for ce: Dictionary in entries:
		var sub: Dictionary = {}
		var picked := str(spec.get("subclass", "")) if ce["primary"] and spec.get("classes", []).is_empty() else str(ce["entry"].get("subclass", ""))
		for sc: Dictionary in ce["cls"].get("subclasses", []):
			if str(sc["id"]) == picked:
				sub = sc
		var scs: Dictionary = sub.get("spellcasting", {})
		if scs.is_empty():
			continue
		var src: Dictionary = (spec if ce["primary"] else ce["entry"]).get("subclass_spells", {})
		var free := _by_level(scs.get("free_school_by_level", {}), int(ce["level"]), 99)
		var outside := 0
		var nk := _by_level(scs.get("known", {}), int(ce["level"]), 0)
		var top := _by_level_arr(scs.get("slots", {}), int(ce["level"])).size()
		var learned: Array = (src.get("spells", []) as Array).filter(func(s: Variant) -> bool:
			return int(RulesDB.get_entry("spell", str(s)).get("level", 99)) <= top).slice(0, nk)  # 지금 레벨에서 실제로 아는 주문만
		for k: String in ["cantrips", "spells"]:
			for sid: Variant in (src.get(k, []) if k == "cantrips" else learned):
				var sp := RulesDB.get_entry("spell", str(sid))
				if sp.is_empty() or not str(scs["list"]) in sp.get("classes", []):
					e.append("%s: %s는 %s 주문 목록에 없다" % [sub["id"], sid, scs["list"]])
					continue
				if (int(sp["level"]) == 0) != (k == "cantrips"):
					e.append("%s: %s는 %s가 아니다" % [sub["id"], sid, "소마법" if k == "cantrips" else "레벨 주문"])
				if k == "spells" and not scs.get("schools", []).is_empty() and not str(sp.get("school", "")) in scs["schools"]:
					outside += 1
		if outside > free:
			e.append("%s: %s 학파 밖 주문은 %d개까지" % [sub["id"], "·".join(scs["schools"]), free])
	return e


## 재주 선택(능력치 향상 칸 asi {"feat": id, <능력>: n}): 일반 재주만, 같은 재주 두 번 X(능력치 향상 제외),
## 고르는 +1은 ability_increase.choose 안에서 total만큼, 고정 +1 재주는 능력을 적지 않는다, requires(갑옷 숙련) 확인.
static func validate_feats(spec: Dictionary, entries: Array) -> PackedStringArray:
	var e := PackedStringArray()
	var picks: Array = []
	for ce: Dictionary in entries:
		var asi_src: Dictionary = spec.get("asi", {}) if ce["primary"] else ce["entry"].get("asi", {})
		for k: String in asi_src:
			if asi_src[k] is Dictionary and asi_src[k].has("feat"):
				picks.append(asi_src[k])
	var armor: Array = entries[0]["cls"].get("armor_training", []).duplicate()
	for ce: Dictionary in entries.slice(1):
		armor.append_array(ce["cls"].get("multiclass", {}).get("armor_training", []))
	for p: Dictionary in picks:
		armor.append_array(RulesDB.get_entry("feat", str(p["feat"])).get("grants", {}).get("armor_training", []))
	var seen := {}
	for p: Dictionary in picks:
		var fid := str(p["feat"])
		var ft := RulesDB.get_entry("feat", fid)
		if ft.is_empty():
			e.append("모르는 재주 '%s'" % fid)
			continue
		if str(ft.get("category", "")) != "general":
			e.append("%s는 능력치 향상 칸에서 고를 수 없다" % fid)
		if seen.has(fid) and fid != "ability_score_improvement":
			e.append("재주 %s는 한 번만" % fid)
		seen[fid] = true
		var req := str(ft.get("requires", {}).get("armor_training", ""))
		if req != "" and not req in armor:
			e.append("%s: %s 갑옷 숙련이 필요하다" % [fid, req])
		var inc: Dictionary = ft.get("ability_increase", {})
		var total := 0
		for a: String in p:
			if a in ABILITIES:
				total += int(p[a])
				if inc.has("choose") and not a in inc["choose"]:
					e.append("%s: %s는 올릴 수 없다" % [fid, a])
		if inc.has("choose") and total != int(inc.get("total", 1)):
			e.append("%s: 능력치를 %d 올려야 한다" % [fid, int(inc.get("total", 1))])
		elif not inc.has("choose") and not inc.has("total") and total != 0:
			e.append("%s는 고르는 능력치 상승이 없다" % fid)
	return e


## 주문 재주 선택: 재주 spell_list 주문 목록에 있고 소마법/1레벨이 맞는지
static func validate_feat_spells(spec: Dictionary) -> PackedStringArray:
	var e := PackedStringArray()
	for fid: String in RulesDB.ids("feat"):
		var ft := RulesDB.get_entry("feat", fid)
		if not ft.has("spell_list") or not spec.has(fid):
			continue
		var pick: Dictionary = spec[fid]
		for k: String in ["cantrips", "spells"]:
			for sid: Variant in pick.get(k, []):
				var sp := RulesDB.get_entry("spell", str(sid))
				if sp.is_empty() or not str(ft["spell_list"]) in sp.get("classes", []):
					e.append("%s: %s는 %s 주문 목록에 없다" % [fid, sid, ft["spell_list"]])
				elif int(sp["level"]) != (0 if k == "cantrips" else 1):
					e.append("%s: %s는 %s가 아니다" % [fid, sid, "소마법" if k == "cantrips" else "1레벨 주문"])
	return e


## 주문 선택: 소마법·준비 주문은 클래스 주문 목록(주문 데이터 classes ∋ spellcasting.list)에 있고,
## (가진 슬롯보다 높은 준비 주문은 오류가 아니라 생성기가 건너뛴다 — 레벨이 오르면 열린다.)
static func validate_spells(cls: Dictionary, spec: Dictionary, lv: int) -> PackedStringArray:
	var e := PackedStringArray()
	var sc: Dictionary = cls.get("spellcasting", {})
	if sc.is_empty():
		if not spec.get("spells", []).is_empty() or not spec.get("cantrips", []).is_empty():
			e.append("%s는 주문을 쓰지 않는다" % cls["id"])
		return e
	var list := str(sc.get("list", cls["id"]))
	var lists := extra_lists(cls, lv)
	lists.append(list)
	for k: String in ["cantrips", "spells"]:
		for sid: Variant in spec.get(k, []):
			var sp := RulesDB.get_entry("spell", str(sid))
			if sp.is_empty():
				e.append("모르는 주문 '%s'" % sid)
				continue
			if not lists.any(func(l: String) -> bool: return l in sp.get("classes", [])):
				e.append("%s는 %s 주문 목록에 없다" % [sid, list])
			if k == "cantrips" and int(sp["level"]) != 0:
				e.append("%s는 소마법이 아니다" % sid)
			if k == "spells" and int(sp["level"]) == 0:
				e.append("%s는 소마법이다(cantrips에)" % sid)
	return e


## 클래스 레벨에 따라 더 열리는 주문 목록(spellcasting.extra_lists {"level", "lists"} — 바드 마법의 비밀 10레벨).
static func extra_lists(cls: Dictionary, lv: int) -> Array:
	var x: Dictionary = cls.get("spellcasting", {}).get("extra_lists", {})
	if x.is_empty() or lv < int(x.get("level", 99)):
		return []
	return (x.get("lists", []) as Array).duplicate()


## 포인트 구매 27점: 능력치마다 8~15, 비용 합계 ≤ 27(룰북 6단계).
static func validate_point_buy(scores: Dictionary) -> PackedStringArray:
	var e := PackedStringArray()
	var total := 0
	for a: String in ABILITIES:
		var v := int(scores.get(a, 8))
		if not POINT_COST.has(v):
			e.append("%s %d: 포인트 구매는 8~15" % [a, v])
		else:
			total += POINT_COST[v]
	if total > POINT_BUDGET:
		e.append("포인트 %d점 사용(최대 27)" % total)
	return e


static func point_cost(scores: Dictionary) -> int:
	var total := 0
	for a: String in ABILITIES:
		total += POINT_COST.get(int(scores.get(a, 8)), 99)
	return total


## 능력치 보너스: 아무 능력치에나 +2/+1 또는 +1/+1/+1(룰북 6단계 결정 1).
static func validate_bonus(bonus: Dictionary) -> PackedStringArray:
	var vals: Array = bonus.values().map(func(v: Variant) -> int: return int(v))
	vals.sort()
	if vals == [1, 2] or vals == [1, 1, 1]:
		return PackedStringArray()
	return PackedStringArray(["능력치 보너스는 +2/+1 또는 +1/+1/+1"])


# ======================================================================
# 적용
# ======================================================================

## 명세의 혈통(서브종족). 고르지 않았으면 그 종족의 첫 혈통(BG3 — 서브종족은 늘 하나 골라져 있다).
static func lineage_of(spec: Dictionary) -> String:
	var lid := str(spec.get("lineage", ""))
	if lid != "":
		return lid
	var sp := RulesDB.get_entry("species", spec.get("species", ""))
	if not sp.get("lineage_required", false):
		return ""
	if str(sp.get("default_lineage", "")) != "":
		return str(sp["default_lineage"])
	for l: Dictionary in RulesDB.entries("species"):
		if str(l.get("parent", "")) == str(sp.get("id", "")):
			return str(l["id"])
	return ""


static func apply(c: Node, spec: Dictionary) -> void:
	var entries := class_entries(spec)  # 멀티클래스: 첫 클래스가 주 클래스(내성·기능 숙련·전체 훈련)
	var cls: Dictionary = entries[0]["cls"]
	var sp := RulesDB.get_entry("species", spec["species"])
	var lin := RulesDB.get_entry("species", lineage_of(spec))
	var bg := RulesDB.get_entry("background", spec["background"])
	var lv := total_level(spec)
	var sub: Dictionary = entries[0]["sub"]
	c.display_name = spec.get("name", {"ko": cls["name"]["ko"], "en": cls["name"]["en"]})
	c.team = spec.get("team", "party")
	c.is_player_character = true
	c.level = lv
	c.class_id = cls["id"]
	c.subclass_id = sub.get("id", "")
	c.class_levels = {}
	c.subclass_ids = {}
	c.feature_class = {}
	for e: Dictionary in entries:
		c.class_levels[e["id"]] = int(e["level"])
		c.subclass_ids[e["id"]] = e["sub"].get("id", "")
	c.species_id = sp["id"]
	c.lineage_id = lin.get("id", "")
	c.background_id = bg["id"]
	c.proficiency_bonus = Levels.proficiency_bonus(lv)
	# 능력치: 포인트 구매 + 보너스 + 4레벨 능력치 향상(최대 20)
	var ab := {}
	for a: String in ABILITIES:
		ab[a] = int(spec.get("scores", {}).get(a, 8)) + int(spec.get("bonus", {}).get(a, 0))
	var feats: Array = []  # 출신 재주 없음(BG3식 — 배경·인간이 재주를 주지 않는다, 2026-11-23)
	for e: Dictionary in entries:
		var asi_src: Dictionary = spec.get("asi", {}) if e["primary"] else e["entry"].get("asi", {})  # 능력치 향상은 클래스 레벨로
		for asi_lv: int in e["cls"].get("asi_levels", []):
			if int(e["level"]) >= asi_lv:
				var pick: Dictionary = asi_src.get(str(asi_lv), {})
				var cap := 20
				if pick.has("feat"):
					feats.append(pick["feat"])
					cap = int(RulesDB.get_entry("feat", str(pick["feat"])).get("ability_increase", {}).get("max", 20))
				for a: String in pick.keys():
					if a in ABILITIES:
						ab[a] = mini(int(ab[a]) + int(pick[a]), maxi(cap, int(ab[a])))
	# 장비(equipment.gd): 착용 능력치 최소값(오우거 힘의 건틀릿 등)
	var slots := Equipment.from_spec(spec, cls)
	var mins := Equipment.ability_mins(slots)
	for a: String in mins:
		ab[a] = maxi(int(ab[a]), int(mins[a]))
	c.abilities = ab
	# 크기·속도·감각
	c.size = spec.get("size", sp.get("size", "medium"))
	c.speed_tiles = int(lin.get("speed_tiles", sp.get("speed_tiles", 6)))
	c.darkvision_tiles = int(lin.get("darkvision_tiles", sp.get("darkvision_tiles", 0)))
	c.senses = ["darkvision"] if c.darkvision_tiles > 0 else []
	c.weight_kg = 35.0 if c.size == "small" else 75.0
	c.damage_resistances = sp.get("resistances", []) + lin.get("resistances", [])
	c.save_advantage_vs = sp.get("save_advantage_vs", []) + lin.get("save_advantage_vs", [])  # 혈통도(굳센심장·회색 드워프)
	c.save_advantage_abilities = sp.get("save_advantage_abilities", []).duplicate()
	c.condition_immunities = sp.get("condition_immunities", []) + lin.get("condition_immunities", [])
	# 기능·재주(먼저 모아야 전문화·숙련 부여를 기능 계산에 쓸 수 있다)
	c.features = []
	c.feature_data = {}
	c.feature_hooks = {}
	c.set_meta("special_attacks", [])
	c.set_meta("picked_spells", [])
	c.caps = []
	for e: Dictionary in entries:
		for f: Dictionary in e["cls"]["features"] + e["sub"].get("features", []):
			if int(f.get("level", 1)) <= int(e["level"]):
				if not c.feature_class.has(f["id"]):
					c.feature_class[f["id"]] = e["id"]  # 기능 → 클래스(기능 스크립트는 그 클래스 레벨로 — creature.feature_level)
				_add_feature(c, f)
	for f: Dictionary in sp.get("features", []) + lin.get("features", []):
		_add_feature(c, f)
	# 고르는 기능(choice_kind): 명세 키 = 기능 id. feat = 재주, expertise = 전문화, option = choice_grants 효과
	var expertise: Array = spec.get("expertise", []).duplicate()
	var extra_skill: Array = []
	var grants: Array = []  # [출처 기능 id, grants]
	for fid: String in c.feature_data:
		var f: Dictionary = c.feature_data[fid]
		if f.has("grants"):
			grants.append([fid, f["grants"]])
		var kind := str(f.get("choice_kind", ""))
		if kind == "option" and spec.get(fid) is Array:
			var on := _by_level(f.get("count_by_level", {}), c.feature_level(fid), int(f.get("count", 1)))  # 레벨마다 늘어나는 선택(4원소 수련)
			for pick: Variant in (spec[fid] as Array).slice(0, on):
				if c.feature_level(fid) < int(f.get("choice_min_level", {}).get(str(pick), 0)):
					continue  # 선행 레벨이 안 된 선택지(워락 영창)
				if f.get("choice_grants", {}).has(str(pick)):
					grants.append([fid, f["choice_grants"][str(pick)]])  # 여러 개 고르기(소서러 주문 변형 2)
			continue
		if kind == "expertise" and spec.get(fid) is Array:
			for pick: Variant in (spec[fid] as Array).slice(0, int(f.get("count", 1))):
				if str(pick) in f.get("choices", []) or f.get("choices", []).is_empty():
					expertise.append(str(pick))  # 여러 개 고르기(로그 6레벨 전문화 2)
					if f.get("also_proficiency", false):
						extra_skill.append(str(pick))  # 숙련 + 전문화(앎의 축복)
			continue
		if kind == "skill" and spec.get(fid) is Array:
			for pick: Variant in (spec[fid] as Array).slice(0, int(f.get("count", 1))):
				if str(pick) in f.get("choices", []):
					extra_skill.append(str(pick))  # 여러 개 고르기(지식 학파 추가 숙련 3)
			continue
		if kind == "spell" and spec.get(fid) is Array:
			continue  # 고른 주문(마법의 발견): 아래 주문 단계에서 항상 준비로
		if kind == "special_attack" and spec.get(fid) is Array:
			# 기법·비전 사격(배틀 마스터·아케인 아처·전투 기법 입문): 레벨표 count_by_level만큼 배운다(무기 액션 group 항목)
			var n := _by_level(f.get("count_by_level", {}), c.feature_level(fid), int(f.get("count", 1)))
			var learned: Array = c.get_meta("special_attacks", []).duplicate()
			for pick: Variant in (spec[fid] as Array).slice(0, n):
				var wa := RulesDB.get_entry("weapon_action", str(pick))
				if not wa.is_empty() and str(wa.get("group", "")) == str(f.get("group", "")) and not str(pick) in learned:
					learned.append(str(pick))
					c.caps.append_array(wa.get("caps", []))  # 반격·정밀 공격
			c.set_meta("special_attacks", learned)
			continue
		var chosen := str(spec.get(str(f.get("choice_from", fid)), ""))  # choice_from: 다른 기능의 선택을 따른다(자연의 수호 = 대지 종류)
		if kind == "" or chosen == "" or not chosen in f.get("choices", []):
			continue
		match kind:
			"feat":
				feats.append(chosen)
			"expertise":
				expertise.append(chosen)
			"skill":
				extra_skill.append(chosen)  # 기능 숙련 하나 더(바바리안 원시 지식)
			"spell_pick":
				var pk: Array = c.get_meta("picked_spells", []).duplicate()
				pk.append(chosen)  # 고르는 주문 하나(비전 궁수 소마법) — 재주 주문처럼 시전 능력 없으면 지능·지혜·매력 중 높은 것
				c.set_meta("picked_spells", pk)
			"option":
				if f.get("choice_grants", {}).has(chosen):
					grants.append([fid, f["choice_grants"][chosen]])
	var feat_weapons: Array = []
	var feat_spells: Array = []
	for fid: String in feats:
		var ft := RulesDB.get_entry("feat", fid)
		c.features.append(fid)
		c.caps.append_array(ft.get("tags", []))
		if ft.has("grants"):
			grants.append([fid, ft["grants"]])  # 재주도 기능과 같은 부여 장치(훈련·내성·HP·태그·능력치 등)
		if (ft.has("hook") and ft.has("script")) or ft.has("toggle") or ft.has("kind"):
			_add_feature(c, ft)  # 켜고 끄는·반응 재주는 기능과 같은 장치(상시 설정·반응 목록)
		# 고르는 재주(choose): 명세 키 = 재주 id, 값 = 고른 목록
		var ch: Dictionary = ft.get("choose", {})
		var picks: Array = (spec.get(fid, []) as Array).slice(0, int(ch.get("count", 0))) if spec.get(fid) is Array else []
		match str(ch.get("kind", "")):
			"skills":
				extra_skill.append_array(picks)
			"weapons":
				feat_weapons.append_array(picks)
			"spells":
				for sid: Variant in picks:
					if str(sid) in ch.get("from", []):
						feat_spells.append(str(sid))
			"special_attacks":
				var learned: Array = c.get_meta("special_attacks", []).duplicate()
				for pick: Variant in picks:
					var wa := RulesDB.get_entry("weapon_action", str(pick))
					if not wa.is_empty() and str(wa.get("group", "")) == str(ch.get("group", "")) and not str(pick) in learned:
						learned.append(str(pick))
						c.caps.append_array(wa.get("caps", []))
				c.set_meta("special_attacks", learned)
	var uniq_f: Array = []
	for f: String in c.features:
		if not f in uniq_f:
			uniq_f.append(f)
	c.features = uniq_f
	# 기능이 주는 것(grants): 공격 횟수·치명타 범위·훈련·소마법 수·태그·유리
	var wt: Array = cls["weapon_training"].duplicate()
	var armor_training: Array = cls["armor_training"].duplicate()
	for e: Dictionary in entries.slice(1):
		wt.append_array(e["cls"].get("multiclass", {}).get("weapon_training", []))  # 멀티클래스로 들어온 클래스는 일부 숙련만(SRD)
		armor_training.append_array(e["cls"].get("multiclass", {}).get("armor_training", []))
	var extra_cantrips := 0
	var hp_per_level := 0
	var at_will: Array = []
	var grant_spells: Array = []
	var innate_grants: Array = []
	var skill_bonus_ability := {}
	var hit_bonus: Array = []
	var type_bonus: Array = []
	var extra_saves: Array = []
	var init_bonus := 0
	c.remove_meta("elemental_adept")
	c.remove_meta("ignore_resistance")
	c.remove_meta("scribe_discount")
	c.remove_meta("bonus_action_spells")
	c.remove_meta("condition_immunity_from")
	wt.append_array(feat_weapons)  # 무기 수련: 고른 무기 4종
	for g: Array in grants:
		var gr: Dictionary = g[1]
		c.attacks_per_action = maxi(c.attacks_per_action, int(gr.get("attacks_per_action", 1)))
		c.crit_threshold = mini(c.crit_threshold, int(gr.get("crit_threshold", 20)))
		wt.append_array(gr.get("weapon_training", []))
		armor_training.append_array(gr.get("armor_training", []))
		extra_cantrips += int(gr.get("extra_cantrips", 0))
		hp_per_level += int(gr.get("hp_per_level", 0))
		at_will.append_array(gr.get("at_will", []))  # 슬롯 없이 마음대로 쓰는 주문(워락 영창)
		innate_grants.append_array(gr.get("innate_spells", []))  # 긴 휴식마다 슬롯 없이 1회(워락 영창·깊어진 계약 — BG3)
		for k: String in gr.get("always_prepared", {}):
			if c.feature_level(str(g[0])) >= int(k):
				grant_spells.append_array(gr["always_prepared"][k])  # 선택에 따른 항상 준비(대지 회합 주문)
		for sk: String in gr.get("skill_bonus_ability", {}):
			skill_bonus_ability[sk] = str(gr["skill_bonus_ability"][sk])  # 원초의 질서 마법사: 비전·자연 + 지혜
		if int(gr.get("darkvision_tiles", 0)) > c.darkvision_tiles:
			c.darkvision_tiles = int(gr["darkvision_tiles"])  # 악마의 시야
			if not c.senses.has("darkvision"):
				c.senses.append("darkvision")
		c.caps.append_array(gr.get("caps", []))
		for r: String in gr.get("resistances", []):
			if not r in c.damage_resistances:
				c.damage_resistances.append(r)  # 자연의 수호·악마의 회복력
		for ci: String in gr.get("condition_immunities", []):
			if not ci in c.condition_immunities:
				c.condition_immunities.append(ci)
		type_bonus.append_array(gr.get("spell_damage_types", []))
		extra_saves.append_array(gr.get("save_proficiencies", []))  # 수련된 생존자(전부)·미끄러운 정신(지혜·매력)  # 원소 친화: 그 종류 주문 피해 + 주문 능력
		if gr.has("weapon_hit_bonus"):
			var hb: Dictionary = gr["weapon_hit_bonus"].duplicate(true)
			hb["feature"] = str(g[0])
			hit_bonus.append(hb)  # 신성한 일격·원초의 일격: 턴당 1회 무기 명중 추가 피해(resolver._hit_riders)
		for adv: Dictionary in gr.get("advantage", []):
			c.extra_modifiers.append({"effect": adv.duplicate(true), "source": g[0], "builder": true})
		extra_skill.append_array(gr.get("skills", []))  # 무대 체질: 기만·공연
		expertise.append_array(gr.get("expertise", []))
		init_bonus += int(gr.get("initiative_bonus", 0))  # 경계 +5
		if str(gr.get("initiative_bonus_from", "")) == "proficiency_bonus":
			init_bonus += c.proficiency_bonus  # 대담함(스워시버클러형): 레벨에 따라 오르는 이니셔티브
		if gr.has("special_attacks"):
			var sl: Array = c.get_meta("special_attacks", []).duplicate()
			for sa: String in gr["special_attacks"]:
				if c.feature_level(str(g[0])) >= int(gr.get("special_attacks_level", 0)) and not sa in sl:
					sl.append(sa)  # 정해진 특수 공격(지저분한 수법)
			c.set_meta("special_attacks", sl)
		c.speed_tiles += int(gr.get("speed_tiles", 0))  # 날랜 발 +2칸
		if gr.has("condition_immunity_from"):
			c.set_meta("condition_immunity_from", gr["condition_immunity_from"])
		if gr.has("damage_immunities"):
			for di: String in gr["damage_immunities"]:
				if not di in c.damage_immunities:
					c.damage_immunities.append(di)
		if gr.has("bonus_action_spells"):
			var ba: Array = c.get_meta("bonus_action_spells", []).duplicate()
			ba.append_array(gr["bonus_action_spells"])
			c.set_meta("bonus_action_spells", ba)
		if gr.has("scribe_discount"):
			var sd: Array = c.get_meta("scribe_discount", []).duplicate()
			sd.append(str(gr["scribe_discount"]))
			c.set_meta("scribe_discount", sd)  # 학파 주문 옮겨 적기 절반
		if gr.has("ignore_resistance"):
			var ir: Array = c.get_meta("ignore_resistance", []).duplicate()
			ir.append_array(gr["ignore_resistance"])
			c.set_meta("ignore_resistance", ir)  # 피할 수 없는 파괴(죽음 영역): 사령 저항 무시
		if gr.has("elemental_adept"):
			var ea: Array = c.get_meta("elemental_adept", []).duplicate()
			ea.append(str(gr["elemental_adept"]))
			c.set_meta("elemental_adept", ea)
	# 능력치 상승 부여(ability_increase {능력: n, "max": m} — 원시 투사·몸과 마음: +4, 최대 25)
	for g: Array in grants:
		var inc: Dictionary = g[1].get("ability_increase", {})
		for a: String in inc:
			if a in ABILITIES:
				c.abilities[a] = mini(int(c.abilities[a]) + int(inc[a]), maxi(int(inc.get("max", 20)), int(c.abilities[a])))
	c.initiative_bonus = init_bonus
	# 내성·기능 숙련
	c.save_proficiencies = cls["saves"].duplicate()
	for sv: String in extra_saves:
		if not sv in c.save_proficiencies:
			c.save_proficiencies.append(sv)
	var skills: Array = spec.get("skills", []).duplicate() + bg["skills"]
	if spec.get("species_skill", "") != "":
		skills.append(spec["species_skill"])
	skills.append_array(spec.get("extra_skills", []))
	skills.append_array(extra_skill)
	for e: Dictionary in entries.slice(1):
		skills.append_array(e["entry"].get("skills", []).slice(0, int(e["cls"].get("multiclass", {}).get("skills", {}).get("choose", 0))))
	c.skill_bonuses = {}
	for s: String in skills:
		c.skill_bonuses[s] = c.proficiency_bonus * (2 if s in expertise else 1)  # 전문화는 숙련 기능에만
	for sk: String in skill_bonus_ability:
		c.skill_bonuses[sk] = int(c.skill_bonuses.get(sk, 0)) + maxi(1, c.ability_mod(skill_bonus_ability[sk]))
	# 훈련·숙련
	c.weapon_proficiencies = _weapon_profs(wt)
	# HP: 1레벨 최대, 이후 평균 올림(룰북 6단계) + 건강 수정치, 드워프 +1/레벨
	var con: int = c.ability_mod("con")
	var hp: int = (int(sp.get("hp_per_level", 0)) + int(RulesDB.get_entry("species", lineage_of(spec)).get("hp_per_level", 0))) * lv  # 언덕 드워프(혈통)
	for e: Dictionary in entries:
		var hd: int = e["cls"]["hit_die"]
		var n := int(e["level"])
		if e["primary"]:
			hp += hd + con + (n - 1) * (hd / 2 + 1 + con)  # 캐릭터 1레벨만 최대(SRD 멀티클래스)
		else:
			hp += n * (hd / 2 + 1 + con)
	hp += hp_per_level * lv  # 기능 부여 hp_per_level(용의 회복력: 레벨당 +1)
	c.hp_max = maxi(hp, lv)
	c.hp = c.hp_max
	# 자원
	c.resources = {}
	var res_src: Array = []  # [자원 데이터, 그 클래스 레벨]
	for e: Dictionary in entries:
		for r: Dictionary in e["cls"].get("resources", []):
			if str(r.get("subclass", "")) != "" and str(r["subclass"]) != str(e["sub"].get("id", "")):
				continue  # 하위 클래스 자원(우월 주사위·비전 화살)
			res_src.append([r, int(e["level"])])
	for r: Dictionary in sp.get("resources", []):
		res_src.append([r, lv])
	for fid: String in feats:
		for r: Dictionary in RulesDB.get_entry("feat", fid).get("resources", []):
			res_src.append([r, lv])  # 재주 자원(행운 점수)
	for row: Array in res_src:
		var r: Dictionary = row[0]
		var mx := _resource_max(r["max"], int(row[1]), c.proficiency_bonus, c)
		if mx > 0:
			var rc: Variant = r["recharge"]
			if rc is Dictionary:
				rc = _by_level_str(rc, int(row[1]), "long")  # 레벨표(바드: 5레벨부터 짧은 휴식 — 영감의 샘)
			if c.resources.has(r["id"]) and r.get("add", false):
				c.resources[r["id"]]["max"] = int(c.resources[r["id"]]["max"]) + mx  # add: 더한다(전투 기법 입문 우월 주사위 +1)
				c.resources[r["id"]]["current"] = c.resources[r["id"]]["max"]
				continue
			if c.resources.has(r["id"]) and int(c.resources[r["id"]]["max"]) >= mx:
				continue  # 같은 자원을 두 클래스가 주면 큰 쪽(신성 변환 등)
			c.resources[r["id"]] = {"current": mx, "max": mx, "recharge": str(rc)}
	# 장비·AC: 칸에서 갑옷·방패·무기 묶음과 착용 효과(마법 보너스·반지·망토 등은 수정치 source "item:<칸>")
	c.set_meta("armor_training", armor_training)
	Equipment.apply_to(c, slots)
	c.ac_base = armor_class(c, str(c.get_meta("armor")), bool(c.get_meta("shield")), armor_training)
	Equipment.sync_conditions(c)  # 숙련 없는 갑옷·무게 상태(BG3식)
	var worn := str(c.get_meta("armor"))
	if worn != "" and int(c.abilities.get("str", 10)) < int(RulesDB.get_entry("armor", worn).get("str_required", 0)):
		c.speed_tiles = maxi(0, c.speed_tiles - 2)  # 근력 요구치 미달: 속도 −10피트(SRD 갑옷 표)
	if c.has_cap("fast_movement") and not _heavy(str(c.get_meta("armor"))):
		c.speed_tiles += 2  # 빠른 이동: 중갑이 아니면 +10피트
	if c.has_cap("unarmored_movement") and str(c.get_meta("armor")) == "" and not bool(c.get_meta("shield")):
		var mv: Dictionary = c.feature_data.get("unarmored_movement", {}).get("bonus_by_level", {})
		c.speed_tiles += _by_level(mv, c.feature_level("unarmored_movement"), 2) if not mv.is_empty() else 2  # 몽크 맨몸 이동: +10~30피트(레벨표)
	# 주문
	_apply_spells(c, entries, sp, lin, spec, lv, extra_cantrips)
	_apply_feat_spells(c, feats, spec)
	# 고른 재주 주문(의식 주문가·주문 저격): 소마법은 그냥, 1레벨 이상은 슬롯 없이(BG3 의식). 시전 능력은 내 시전 능력 — 없으면 지능·지혜·매력 중 높은 것
	var sab: Dictionary = c.get_meta("spell_ability", {})
	for sid: String in feat_spells + c.get_meta("picked_spells", []):
		if int(RulesDB.get_entry("spell", sid).get("level", 0)) == 0:
			if not c.spells.has(sid):
				c.spells.append(sid)
		elif not sid in at_will:
			at_will.append(sid)
		if not sab.has(sid) and c.spellcasting_ability == "":
			var best := "int"
			for a: String in ["wis", "cha"]:
				if c.ability_mod(a) > c.ability_mod(best):
					best = a
			sab[sid] = best
	c.set_meta("spell_ability", sab)
	at_will.append_array(c.get_meta("chosen_at_will", []))
	if c.has_meta("chosen_at_will"):
		c.remove_meta("chosen_at_will")
	c.set_meta("at_will", at_will)
	c.set_meta("weapon_hit_bonus", hit_bonus)
	c.set_meta("spell_type_bonus", type_bonus)
	var aura := {}
	for fid: String in c.feature_data:
		var fa: Dictionary = c.feature_data[fid].get("aura", {})
		if fa.is_empty():
			continue
		if fa.has("range_by_level"):
			aura["range_by_level"] = fa["range_by_level"]
			aura["feature"] = fid
		if fa.has("save_bonus"):
			aura["save_bonus"] = fa["save_bonus"]
		if fa.has("spell_resistance"):
			aura["spell_resistance"] = true  # 수호의 오라
		if fa.has("melee_bonus_types"):
			aura["melee_bonus_types"] = fa["melee_bonus_types"]  # 증오의 오라
		var im: Array = aura.get("immune", [])
		im.append_array(fa.get("immune", []))
		aura["immune"] = im
	if aura.has("feature"):
		c.set_meta("aura", aura)  # 팔라딘 오라(scripts/rules/auras.gd)
	elif c.has_meta("aura"):
		c.remove_meta("aura")
	var sub_spells: Array = grant_spells.duplicate()  # 하위 클래스 주문(무료 시전 free_cast_from subclass — 자연 회복)
	for e: Dictionary in entries:
		for k: String in (e["sub"] as Dictionary).get("always_prepared", {}):
			if int(e["level"]) >= int(k):
				sub_spells.append_array(e["sub"]["always_prepared"][k])
	c.set_meta("subclass_spells", sub_spells)
	for sid: String in at_will + grant_spells + innate_grants:
		if not c.spells.has(sid) and not RulesDB.get_entry("spell", sid).is_empty():
			c.spells.append(sid)
	for sid: String in innate_grants:
		if not RulesDB.get_entry("spell", sid).is_empty():
			c.resources["innate_" + sid] = {"current": 1, "max": 1, "recharge": "long"}
	# 반응
	c.known_reactions = ["opportunity_attack"]
	for sid: String in c.spells:
		if str(RulesDB.get_entry("spell", sid).get("cast", {}).get("cost", "")) == "reaction":
			c.known_reactions.append(sid)  # 반응 주문(주문 데이터 cast.cost — 반응 처리는 reaction_queue)
	for fid: String in c.feature_data:
		if str(c.feature_data[fid].get("kind", "")) == "reaction":
			c.known_reactions.append(fid)  # 반응 기능(교묘한 회피 등)
	if c.has_cap("cosmic_omen"):
		c.set_meta("omen", "weal" if Dice.die(20) % 2 == 0 else "woe")  # 우주의 징조: 긴 휴식마다 짝수 행운·홀수 불운
	if c.has_cap("portent") and c.resources.has("portent_dice"):
		var pv: Array = []
		for i in int(c.resources["portent_dice"]["max"]):
			pv.append(Dice.die(20))
		c.set_meta("portent_values", pv)  # 예지: 새로 만든 캐릭터는 막 쉰 것처럼 굴려 둔다
	c.set_meta("spec", spec.duplicate(true))
	# 새로 만든 캐릭터는 막 쉰 것처럼 준비 교체 창이 열려 있다(spell_prep.gd)
	SpellPrep.open_window(c, "long")
	c.reset_turn()


## 명세를 다시 적용한다(장비 바꾸기·레벨 업): 잃은 HP·쓴 자원·턴 상태·고른 무기 묶음·준비 교체 창은 그대로 둔다.
## 기능·장비가 붙인 수정치는 다시 붙으므로 걷어 낸다(주문·상태가 붙인 것은 남긴다).
static func reapply(c: Node, spec: Dictionary) -> void:
	var lost: int = c.hp_max - c.hp
	var was_down: bool = c.hp <= 0
	var used := {}
	for id: String in c.resources:
		used[id] = int(c.resources[id]["max"]) - int(c.resources[id]["current"])
	var turn: Dictionary = c.turn.duplicate(true)
	var active: String = c.active_set
	var window := [c.prep_swaps, c.prep_base.duplicate()]
	for m in c.extra_modifiers.duplicate():
		if m.get("builder", false):
			c.extra_modifiers.erase(m)  # 생성기가 단 것(기능 grants·장비)만 걷어 낸다
	apply(c, spec)
	c.hp = 0 if was_down else maxi(1, c.hp_max - lost)
	for id: String in c.resources:
		if used.has(id):
			c.resources[id]["current"] = maxi(0, int(c.resources[id]["max"]) - int(used[id]))
	c.turn = turn
	c.active_set = active
	c.prep_swaps = window[0]
	c.prep_base = window[1]


static func _add_feature(c: Node, f: Dictionary) -> void:
	if f.get("status", "active") == "deferred":
		c.features.append(f["id"])  # 표시만, 동작은 뒤 단계
		return
	c.feature_data[f["id"]] = f
	c.caps.append_array(f.get("caps", []))
	if f.has("hook") and f.has("script"):
		for h: String in [str(f["hook"])] + Array(f.get("also_hooks", [])):  # also_hooks: 같은 스크립트를 다른 훅에도(어둠의 자의 행운)
			if not c.feature_hooks.has(h):
				c.feature_hooks[h] = []
			c.feature_hooks[h].append(f["script"])


## AC: 갑옷 기본값 + 민첩(상한) + 방패 2 + 방어 재주 1(갑옷을 입었을 때). 갑옷이 없으면 10 + 민첩.
static func armor_class(c: Node, armor_id: String, shield: bool, training: Array = []) -> int:
	var dex: int = c.ability_mod("dex")
	var ac := 10 + dex
	# 맨몸 방어 공식은 하나만(SRD 멀티클래스 — 가장 좋은 것)
	var extra := 0
	if armor_id == "" and c.has_cap("unarmored_defense_con"):
		extra = maxi(extra, c.ability_mod("con"))  # 바바리안 맨몸 방어: 10 + 민첩 + 건강(방패 가능)
	if armor_id == "" and c.has_cap("unarmored_defense_cha"):
		extra = maxi(extra, c.ability_mod("cha"))  # 용의 회복력(소서러): 갑옷이 없으면 10 + 민첩 + 매력
	if armor_id == "" and c.has_cap("unarmored_defense_13"):
		extra = maxi(extra, 3)  # 용의 회복력(BG3): 갑옷이 없으면 13 + 민첩(방패 가능)
	if armor_id == "" and not shield and c.has_cap("unarmored_defense_wis"):
		extra = maxi(extra, c.ability_mod("wis"))  # 몽크 맨몸 방어: 10 + 민첩 + 지혜(방패 없이)
	ac += extra
	if armor_id != "":
		var a := RulesDB.get_entry("armor", armor_id)
		var cap: Variant = a.get("dex_cap")
		# 중갑(상한 0)은 민첩을 더하지도 빼지도 않는다(SRD Heavy Armor)
		if cap != null and str(a.get("category", "")) == "medium" and c.has_cap("medium_armor_master"):
			cap = 3  # 중형 갑옷 숙달: 민첩 +3까지
		ac = int(a["ac_base"]) + (dex if cap == null else (0 if int(cap) == 0 else mini(dex, int(cap))))
		if c.has_cap("armor_ac_plus_1"):
			ac += 1  # 방어(전투 방식)
	if shield:
		ac += 2
	return ac


static func _by_level_str(table: Dictionary, lv: int, default: String) -> String:
	var best := default
	var best_lv := 0
	for k: String in table:
		if lv >= int(k) and int(k) >= best_lv:
			best_lv = int(k)
			best = str(table[k])
	return best


static func _heavy(armor_id: String) -> bool:
	return armor_id != "" and str(RulesDB.get_entry("armor", armor_id).get("category", "")) == "heavy"


static func _weapon_profs(training: Array) -> Array:
	var out: Array = []
	for t: String in training:
		if t == "martial_light":
			for wid: String in RulesDB.ids("weapon"):
				var w := RulesDB.get_entry("weapon", wid)
				if str(w["category"]).begins_with("martial") and "light" in w["properties"]:
					out.append(wid)  # 몽크: 가벼운 군용 무기만(SRD)
		elif t == "martial_finesse_or_light":
			for wid: String in RulesDB.ids("weapon"):
				var w := RulesDB.get_entry("weapon", wid)
				if str(w["category"]).begins_with("martial") and ("finesse" in w["properties"] or "light" in w["properties"]):
					out.append(wid)
		else:
			out.append(t)
	return out


## 주문: 슬롯(한 시전 클래스면 그 표, 둘 이상이면 SRD 멀티클래스 표 — 계약 마법은 따로 pact_slot_N), 클래스마다 소마법·준비·주문서.
## 주 클래스는 명세 cantrips·spells·spellbook, 다른 클래스는 명세 classes 항목의 같은 키. c.spell_class = 주문 → 클래스(시전 능력).
static func _apply_spells(c: Node, entries: Array, sp: Dictionary, lin: Dictionary, spec: Dictionary, lv: int, extra_cantrips: int = 0) -> void:
	var spells: Array = []
	c.spellcasting_ability = ""
	c.spellbook = []
	c.prepared = []
	c.prepared_by_class = {}
	c.spell_class = {}
	c.set_meta("spell_ability", {})
	var casters: Array = entries.filter(func(e: Dictionary) -> bool: return not e["cls"].get("spellcasting", {}).is_empty())
	var normal: Array = casters.filter(func(e: Dictionary) -> bool: return str(e["cls"]["spellcasting"].get("progression", "full")) != "pact")
	var pact: Array = casters.filter(func(e: Dictionary) -> bool: return str(e["cls"]["spellcasting"].get("progression", "full")) == "pact")
	# 하위 클래스 주문 시전(엘드리치 나이트·아케인 트릭스터 — 1/3 시전자): 클래스에 주문 시전이 없고 하위 클래스에 있으면
	var subcasters: Array = entries.filter(func(e: Dictionary) -> bool:
		return e["cls"].get("spellcasting", {}).is_empty() and not (e["sub"] as Dictionary).get("spellcasting", {}).is_empty() \
			and int(e["level"]) >= int(e["sub"].get("level", 3)))
	if normal.size() + subcasters.size() >= 2:
		var clv := 0
		for e: Dictionary in normal:
			clv += int(e["level"]) if str(e["cls"]["spellcasting"].get("progression", "full")) == "full" else ceili(int(e["level"]) / 2.0)
		for e: Dictionary in subcasters:
			clv += int(e["level"]) / 3  # 1/3 시전자(SRD 멀티클래스 표: 내림)
		var table: Array = Levels.multiclass_slots(clv)
		for i in table.size():
			c.resources["spell_slot_%d" % (i + 1)] = {"current": table[i], "max": table[i], "recharge": "long"}
	elif normal.is_empty() and subcasters.size() == 1:
		var scs: Dictionary = subcasters[0]["sub"]["spellcasting"]
		var ts: Array = _by_level_arr(scs.get("slots", {}), int(subcasters[0]["level"]))
		for i in ts.size():
			c.resources["spell_slot_%d" % (i + 1)] = {"current": ts[i], "max": ts[i], "recharge": "long"}
	elif normal.size() == 1:
		var sc0: Dictionary = normal[0]["cls"]["spellcasting"]
		var t0: Array = sc0["slots"].get(str(normal[0]["level"]), [])
		for i in t0.size():
			c.resources["spell_slot_%d" % (i + 1)] = {"current": t0[i], "max": t0[i], "recharge": str(sc0.get("slot_recharge", "long"))}
	for e: Dictionary in pact:
		var scp: Dictionary = e["cls"]["spellcasting"]
		var tp: Array = scp["slots"].get(str(e["level"]), [])
		var key := "pact_slot_%d" if not normal.is_empty() else "spell_slot_%d"  # 계약 마법은 다른 시전 슬롯과 따로(짧은 휴식)
		for i in tp.size():
			if int(tp[i]) > 0 or normal.is_empty():
				c.resources[key % (i + 1)] = {"current": tp[i], "max": tp[i], "recharge": str(scp.get("slot_recharge", "short"))}
	for e: Dictionary in casters:
		var cs: Array = _class_spells(c, e, spec if e["primary"] else e["entry"], extra_cantrips if e["primary"] else 0)
		spells.append_array(cs)
		if c.spellcasting_ability == "" or e["primary"]:
			c.spellcasting_ability = str(e["cls"]["spellcasting"]["ability"])
	# 하위 클래스 주문: 명세 subclass_spells {cantrips, spells} — 레벨표 수만큼, 항상 준비(아는 주문), 시전 능력은 하위 클래스 것
	var sab: Dictionary = c.get_meta("spell_ability", {})
	for e: Dictionary in subcasters:
		var scs2: Dictionary = e["sub"]["spellcasting"]
		var src2: Dictionary = (spec if e["primary"] else e["entry"]).get("subclass_spells", {})
		var nc := _by_level(scs2.get("cantrips", {}), int(e["level"]), 0)
		var nk := _by_level(scs2.get("known", {}), int(e["level"]), 0)
		var top := _by_level_arr(scs2.get("slots", {}), int(e["level"])).size()
		var picks: Array = (src2.get("cantrips", []) as Array).slice(0, nc)
		for sid: Variant in (src2.get("spells", []) as Array):
			if picks.size() >= nc + nk:
				break
			if int(RulesDB.get_entry("spell", str(sid)).get("level", 99)) <= top:
				picks.append(sid)
		for sid: Variant in picks:
			spells.append(str(sid))
			sab[str(sid)] = str(scs2["ability"])
		if c.spellcasting_ability == "":
			c.spellcasting_ability = str(scs2["ability"])
	c.set_meta("spell_ability", sab)
	for e: Dictionary in entries:
		for src: Dictionary in [e["cls"], e["sub"]]:
			for k: String in src.get("always_prepared", {}).keys():
				if int(e["level"]) >= int(k):
					for sid: String in src["always_prepared"][k]:
						spells.append(sid)  # 클래스·하위 클래스의 항상 준비 주문(준비 수에 세지 않음)
						if not c.spell_class.has(sid):
							c.spell_class[sid] = e["id"]
	# 고른 주문(choice_kind spell — 바드 마법의 발견): spell_lists의 주문 중 소마법이거나 가진 슬롯 레벨 이하, 항상 준비
	var top_slot := 0
	for i in range(1, 10):
		if c.resources.has("spell_slot_%d" % i) or c.resources.has("pact_slot_%d" % i):
			top_slot = i
	for fid: String in c.feature_data:
		var f: Dictionary = c.feature_data[fid]
		if str(f.get("choice_kind", "")) != "spell" or not spec.get(fid) is Array:
			continue
		for sid: Variant in (spec[fid] as Array).slice(0, int(f.get("count", 1))):
			var spd := RulesDB.get_entry("spell", str(sid))
			if spd.is_empty():
				continue
			if f.has("spell_level"):
				if int(spd["level"]) != int(f["spell_level"]):
					continue  # 신비한 비전(워락): 정해진 레벨의 주문 하나, 긴 휴식마다 슬롯 없이 1회
				if f.get("from_spellbook", false) and not str(sid) in c.spellbook and not str(sid) in spec.get("spells", []):
					continue  # 주문 숙달·대표 주문(위저드): 주문서의 주문
				if f.get("at_will", false):
					var aw: Array = c.get_meta("chosen_at_will", [])
					aw.append(str(sid))
					c.set_meta("chosen_at_will", aw)  # 주문 숙달(위저드 18레벨): 가장 낮은 레벨로 마음대로
				else:
					c.resources["innate_" + str(sid)] = {"current": 1, "max": 1, "recharge": str(f.get("recharge", "long"))}
			elif int(spd["level"]) > top_slot:
				continue
			if not (f.get("spell_lists", []) as Array).any(func(l: String) -> bool: return l in spd.get("classes", [])):
				continue
			spells.append(str(sid))
			if not c.spell_class.has(str(sid)):
				c.spell_class[str(sid)] = str(c.feature_class.get(fid, c.class_id))
	for cid: String in c.prepared_by_class:
		for sid: String in c.prepared_by_class[cid]:
			if not sid in c.prepared:
				c.prepared.append(sid)
	for s: Dictionary in sp.get("spells", []) + lin.get("spells", []):
		if lv >= int(s["level"]):
			spells.append(s["spell"])
			# 종족·혈통 주문(SRD 유산): 슬롯 없이 긴 휴식마다 1회(innate_<주문> — 무료 횟수 먼저), 슬롯으로도 시전
			if int(RulesDB.get_entry("spell", str(s["spell"])).get("level", 0)) > 0:
				c.resources["innate_" + str(s["spell"])] = {"current": 1, "max": 1, "recharge": "long"}
	var uniq: Array = []
	for s: String in spells:
		if not s in uniq and not RulesDB.get_entry("spell", s).is_empty():
			uniq.append(s)
	c.spells = uniq
	if c.spellcasting_ability == "" and not uniq.is_empty():
		c.spellcasting_ability = spec.get("origin_ability", "cha")


## 한 시전 클래스의 소마법·준비 주문(주문서형이면 주문서). src = 그 클래스의 명세(주 클래스는 명세 전체, 다른 클래스는 classes 항목).
## 준비할 수 있는 레벨은 그 클래스만 있는 것처럼(SRD 멀티클래스 — 자기 표의 슬롯 레벨까지).
static func _class_spells(c: Node, e: Dictionary, src: Dictionary, extra_cantrips: int) -> Array:
	var sc: Dictionary = e["cls"]["spellcasting"]
	var clv := int(e["level"])
	var out: Array = []
	var cantrips: Array = src.get("cantrips", []).slice(0, _by_level(sc["cantrips"], clv, 0) + extra_cantrips)
	for sid: Variant in cantrips:
		out.append(str(sid))
		c.spell_class[str(sid)] = e["id"]
	var max_slot: int = sc["slots"].get(str(clv), []).size()
	var castable: Array = src.get("spells", []).filter(func(sid: Variant) -> bool:
		var l := int(RulesDB.get_entry("spell", str(sid)).get("level", 99))
		return l >= 1 and l <= max_slot)
	# 주문서형: 주문서 = 명세 spellbook(두루마리로 배운 것 포함), 없으면 명세 주문에서 기본 크기만큼. 준비는 주문서 안에서만
	if str(sc.get("type", "")) == "spellbook":
		var book: Array = []
		for sid: Variant in src.get("spellbook", []):
			if not str(sid) in book and not RulesDB.get_entry("spell", str(sid)).is_empty():
				book.append(str(sid))
		# 크기 = 기본(6 + 레벨당 2) + 학파 무료 주문(grants.spellbook_school — 방출 학자) + 두루마리로 배운 수
		var base_size := int(sc.get("spellbook", {}).get("1", 6)) + int(sc.get("spellbook", {}).get("per_level", 2)) * (clv - 1)
		var target := base_size + int(src.get("spellbook_learned", 0))
		for f: Dictionary in c.feature_data.values():
			var bonus: Dictionary = f.get("grants", {}).get("spellbook_school", {})
			if bonus.is_empty():
				continue
			var slots_then: int = sc["slots"].get(str(int(f.get("level", 1))), []).size()
			var n := int(bonus.get("count", 0)) + int(bonus.get("per_new_slot_level", 0)) * maxi(0, max_slot - slots_then)
			var have := book.filter(func(x: String) -> bool: return str(RulesDB.get_entry("spell", x).get("school", "")) == str(bonus["school"])).size()
			target += n
			for sid: Variant in castable:
				if have >= n:
					break
				var se := RulesDB.get_entry("spell", str(sid))
				if str(se.get("school", "")) == str(bonus["school"]) and not str(sid) in book:
					book.append(str(sid))
					have += 1
		for sid: Variant in castable:
			if book.size() >= target:
				break
			if not str(sid) in book:
				book.append(str(sid))
		c.spellbook = book
		castable = castable.filter(func(sid: Variant) -> bool: return str(sid) in book)
	var prep: Array = []
	for sid: Variant in castable:
		if not str(sid) in prep:
			prep.append(str(sid))
	prep = prep.slice(0, _by_level(sc["prepared"], clv, 0))
	for sid: String in prep:
		c.spell_class[sid] = e["id"]
	c.prepared_by_class[e["id"]] = prep
	out.append_array(prep)
	return out


## 명세의 클래스 목록(멀티클래스): classes [{class, level, subclass, (다른 클래스는 skills·cantrips·spells·asi)}],
## 없으면 class·level·subclass 하나. 결과 [{id, level, cls, sub, entry, primary}].
static func class_entries(spec: Dictionary) -> Array:
	var raw: Array = spec.get("classes", [])
	if raw.is_empty():
		raw = [{"class": spec.get("class", ""), "level": int(spec.get("level", 1)), "subclass": spec.get("subclass", "")}]
	var out: Array = []
	for i in raw.size():
		var e: Dictionary = raw[i]
		var cls := RulesDB.get_entry("class", str(e.get("class", "")))
		var sub := {}
		for sc: Dictionary in cls.get("subclasses", []):
			if sc["id"] == str(e.get("subclass", "")) and int(e.get("level", 1)) >= int(sc["level"]):
				sub = sc
		out.append({"id": str(e.get("class", "")), "level": int(e.get("level", 1)), "cls": cls, "sub": sub, "entry": e, "primary": i == 0})
	return out


## 캐릭터 레벨 = 클래스 레벨 합.
static func total_level(spec: Dictionary) -> int:
	if spec.get("classes", []).is_empty():
		return int(spec.get("level", 1))
	var n := 0
	for e: Dictionary in spec["classes"]:
		n += int(e.get("level", 1))
	return n


## 주문 재주(마법 입문 등 — 재주 데이터 spell_list·cantrips·level1_spells): 명세 키 = 재주 id, 값 {"cantrips": [...], "spells": [...]}.
## 소마법은 그냥 쓰고, 1레벨 주문은 슬롯이 있으면 슬롯으로, 없으면 긴 휴식마다 1회(innate_<주문>).
static func _apply_feat_spells(c: Node, feats: Array, spec: Dictionary) -> void:
	for fid: String in feats:
		var ft := RulesDB.get_entry("feat", fid)
		if not ft.has("spell_list"):
			continue
		var pick: Dictionary = spec.get(fid, {})
		for sid: Variant in pick.get("cantrips", []).slice(0, int(ft.get("cantrips", 0))) + pick.get("spells", []).slice(0, int(ft.get("level1_spells", 0))):
			var s := str(sid)
			if RulesDB.get_entry("spell", s).is_empty() or c.spells.has(s):
				continue
			c.spells.append(s)
			if ft.has("casting_ability"):
				var sab: Dictionary = c.get_meta("spell_ability", {})
				sab[s] = str(ft["casting_ability"])  # 마법 입문(BG3): 목록마다 시전 능력이 정해져 있다
				c.set_meta("spell_ability", sab)
			if int(RulesDB.get_entry("spell", s)["level"]) > 0:
				c.resources["innate_" + s] = {"current": 1, "max": 1, "recharge": "long"}
		if c.spellcasting_ability == "":
			c.spellcasting_ability = str(ft.get("casting_ability", pick.get("ability", "")))


## 레벨표에서 배열 값(하위 클래스 주문 슬롯표)
static func _by_level_arr(table: Dictionary, lv: int) -> Array:
	var best: Array = []
	var best_lv := 0
	for k: String in table:
		if lv >= int(k) and int(k) >= best_lv:
			best_lv = int(k)
			best = table[k]
	return best


static func _by_level(table: Variant, lv: int, default: int) -> int:
	if typeof(table) != TYPE_DICTIONARY:
		return default
	var best := default
	var best_lv := 0
	for k: String in table.keys():
		if lv >= int(k) and int(k) >= best_lv:
			best_lv = int(k)
			best = int(table[k])
	return best


static func _resource_max(mx: Variant, lv: int, pb: int, c: Node = null) -> int:
	if typeof(mx) == TYPE_STRING and mx == "proficiency_bonus":
		return pb
	if typeof(mx) == TYPE_STRING and str(mx).begins_with("ability_mod:") and c != null:
		return maxi(1, c.ability_mod(str(mx).get_slice(":", 1)))  # 능력 수정치(최소 1 — 바드의 영감 = 매력)
	if typeof(mx) == TYPE_DICTIONARY:
		return _by_level(mx, lv, 0)
	return int(mx)


## 기본 명세(동료·시험·생성 화면 시작값): 클래스 데이터의 default_build(추천 빌드)에 클래스·레벨·편을 붙인다.
## 클래스 목록을 코드에 두지 않는다 — 새 클래스는 데이터에 default_build만 있으면 된다(룰북 1단계 '클래스 확장 원칙').
static func default_spec(class_id: String, level: int = 1) -> Dictionary:
	var base := {"level": level, "team": "party"}
	var cls := RulesDB.get_entry("class", class_id)
	if cls.is_empty():
		return base
	base.merge((cls.get("default_build", {}) as Dictionary).duplicate(true))
	base["class"] = class_id
	fill_asi(base)
	return base


## 비어 있는 능력치 향상 레벨을 채운다(추천 빌드의 첫 향상 능력 → 20이 되면 건강 → 민첩·지혜). 레벨 업·추천 빌드가 쓴다.
static func fill_asi(spec: Dictionary) -> void:
	var ab := {}
	for a: String in ABILITIES:
		ab[a] = int(spec.get("scores", {}).get(a, 8)) + int(spec.get("bonus", {}).get(a, 0))
	for e: Dictionary in class_entries(spec):
		var key := "asi"
		var src: Dictionary = spec if e["primary"] else e["entry"]
		if not src.has(key):
			src[key] = {}
		var asi: Dictionary = src[key]
		var db_asi: Dictionary = e["cls"].get("default_build", {}).get("asi", {})
		var first: String = str((db_asi.get("4", {"con": 2}) as Dictionary).keys()[0]) if not db_asi.is_empty() else "con"
		for asi_lv: int in e["cls"].get("asi_levels", []):
			if int(e["level"]) < asi_lv:
				continue
			if asi.has(str(asi_lv)):
				for a: String in (asi[str(asi_lv)] as Dictionary).keys():
					if a in ABILITIES:
						ab[a] = mini(int(ab[a]) + int(asi[str(asi_lv)][a]), 20)
				continue
			var pick := {}
			var left := 2
			for a: String in [first, "con", "dex", "wis"]:
				var add := mini(left, 20 - int(ab[a]))
				if add > 0:
					pick[a] = int(pick.get(a, 0)) + add
					ab[a] = int(ab[a]) + add
					left -= add
				if left == 0:
					break
			asi[str(asi_lv)] = pick
