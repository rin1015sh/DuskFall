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
##   "asi": {"4": {"str": 2}}(4레벨 능력치 향상 또는 {"feat": id}), "origin_feat": "alert"(인간),
##   "masteries": [무기 ID], "cantrips": [...], "spells": [준비 주문 / 주문서],
##   "armor": "chain_mail", "shield": true, "weapons": {"melee": {"main", "off"}, "ranged": {"main"}}
## }

const CreatureScript := preload("res://scripts/rules/creature.gd")
const Levels := preload("res://scripts/rules/levels.gd")

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
	var cls := RulesDB.get_entry("class", spec.get("class", ""))
	if cls.is_empty():
		e.append("모르는 클래스 '%s'" % spec.get("class", ""))
		return e
	var lv := int(spec.get("level", 1))
	if lv < 1 or lv > Levels.level_cap():
		e.append("레벨 범위는 1~%d(data/rules/progression.json)" % Levels.level_cap())
	var sp := RulesDB.get_entry("species", spec.get("species", ""))
	if sp.is_empty():
		e.append("모르는 종족 '%s'" % spec.get("species", ""))
	elif sp.get("lineage_required", false):
		var lin := RulesDB.get_entry("species", spec.get("lineage", ""))
		if lin.is_empty() or lin.get("parent", "") != sp["id"]:
			e.append("%s는 혈통을 골라야 한다" % sp["id"])
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
	var sub_lv := 99
	for sc: Dictionary in cls.get("subclasses", []):
		sub_lv = mini(sub_lv, int(sc.get("level", 3)))
	if lv >= sub_lv and spec.get("subclass", "") == "":
		e.append("%d레벨부터 하위 클래스를 골라야 한다" % sub_lv)
	e.append_array(validate_spells(cls, spec, lv))
	e.append_array(validate_feat_spells(spec))
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
	for k: String in ["cantrips", "spells"]:
		for sid: Variant in spec.get(k, []):
			var sp := RulesDB.get_entry("spell", str(sid))
			if sp.is_empty():
				e.append("모르는 주문 '%s'" % sid)
				continue
			if not list in sp.get("classes", []):
				e.append("%s는 %s 주문 목록에 없다" % [sid, list])
			if k == "cantrips" and int(sp["level"]) != 0:
				e.append("%s는 소마법이 아니다" % sid)
			if k == "spells" and int(sp["level"]) == 0:
				e.append("%s는 소마법이다(cantrips에)" % sid)
	return e


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

static func apply(c: Node, spec: Dictionary) -> void:
	var cls := RulesDB.get_entry("class", spec["class"])
	var sp := RulesDB.get_entry("species", spec["species"])
	var lin := RulesDB.get_entry("species", spec.get("lineage", ""))
	var bg := RulesDB.get_entry("background", spec["background"])
	var lv := int(spec.get("level", 1))
	var sub := {}
	for s: Dictionary in cls.get("subclasses", []):
		if s["id"] == spec.get("subclass", "") and lv >= int(s["level"]):
			sub = s
	c.display_name = spec.get("name", {"ko": cls["name"]["ko"], "en": cls["name"]["en"]})
	c.team = spec.get("team", "party")
	c.is_player_character = true
	c.level = lv
	c.class_id = cls["id"]
	c.subclass_id = sub.get("id", "")
	c.species_id = sp["id"]
	c.lineage_id = lin.get("id", "")
	c.background_id = bg["id"]
	c.proficiency_bonus = Levels.proficiency_bonus(lv)
	# 능력치: 포인트 구매 + 보너스 + 4레벨 능력치 향상(최대 20)
	var ab := {}
	for a: String in ABILITIES:
		ab[a] = int(spec.get("scores", {}).get(a, 8)) + int(spec.get("bonus", {}).get(a, 0))
	var feats: Array = [bg["feat"]]
	if spec.get("origin_feat", "") != "" and sp.get("origin_feat_choice", false):
		feats.append(spec["origin_feat"])
	for asi_lv: int in cls.get("asi_levels", []):
		if lv >= asi_lv:
			var pick: Dictionary = spec.get("asi", {}).get(str(asi_lv), {})
			if pick.has("feat"):
				feats.append(pick["feat"])
			else:
				for a: String in pick.keys():
					ab[a] = mini(int(ab[a]) + int(pick[a]), 20)
	c.abilities = ab
	# 크기·속도·감각
	c.size = spec.get("size", sp.get("size", "medium"))
	c.speed_tiles = int(lin.get("speed_tiles", sp.get("speed_tiles", 6)))
	c.darkvision_tiles = int(lin.get("darkvision_tiles", sp.get("darkvision_tiles", 0)))
	c.senses = ["darkvision"] if c.darkvision_tiles > 0 else []
	c.weight_kg = 35.0 if c.size == "small" else 75.0
	c.damage_resistances = sp.get("resistances", []) + lin.get("resistances", [])
	c.save_advantage_vs = sp.get("save_advantage_vs", []).duplicate()
	c.save_advantage_abilities = sp.get("save_advantage_abilities", []).duplicate()
	c.condition_immunities = sp.get("condition_immunities", []) + lin.get("condition_immunities", [])
	# 기능·재주(먼저 모아야 전문화·숙련 부여를 기능 계산에 쓸 수 있다)
	c.features = []
	c.feature_data = {}
	c.feature_hooks = {}
	c.caps = []
	for f: Dictionary in cls["features"] + sub.get("features", []):
		if int(f.get("level", 1)) <= lv:
			_add_feature(c, f)
	for f: Dictionary in sp.get("features", []) + lin.get("features", []):
		_add_feature(c, f)
	# 고르는 기능(choice_kind): 명세 키 = 기능 id. feat = 재주, expertise = 전문화, option = choice_grants 효과
	var expertise: Array = spec.get("expertise", []).duplicate()
	var grants: Array = []  # [출처 기능 id, grants]
	for fid: String in c.feature_data:
		var f: Dictionary = c.feature_data[fid]
		if f.has("grants"):
			grants.append([fid, f["grants"]])
		var kind := str(f.get("choice_kind", ""))
		var chosen := str(spec.get(fid, ""))
		if kind == "" or chosen == "" or not chosen in f.get("choices", []):
			continue
		match kind:
			"feat":
				feats.append(chosen)
			"expertise":
				expertise.append(chosen)
			"option":
				if f.get("choice_grants", {}).has(chosen):
					grants.append([fid, f["choice_grants"][chosen]])
	for fid: String in feats:
		var ft := RulesDB.get_entry("feat", fid)
		c.features.append(fid)
		c.caps.append_array(ft.get("tags", []))
	var uniq_f: Array = []
	for f: String in c.features:
		if not f in uniq_f:
			uniq_f.append(f)
	c.features = uniq_f
	# 기능이 주는 것(grants): 공격 횟수·치명타 범위·훈련·소마법 수·태그·유리
	var wt: Array = cls["weapon_training"].duplicate()
	var armor_training: Array = cls["armor_training"].duplicate()
	var extra_cantrips := 0
	for g: Array in grants:
		var gr: Dictionary = g[1]
		c.attacks_per_action = maxi(c.attacks_per_action, int(gr.get("attacks_per_action", 1)))
		c.crit_threshold = mini(c.crit_threshold, int(gr.get("crit_threshold", 20)))
		wt.append_array(gr.get("weapon_training", []))
		armor_training.append_array(gr.get("armor_training", []))
		extra_cantrips += int(gr.get("extra_cantrips", 0))
		c.caps.append_array(gr.get("caps", []))
		for adv: Dictionary in gr.get("advantage", []):
			c.extra_modifiers.append({"effect": adv.duplicate(true), "source": g[0]})
	if c.has_cap("initiative_proficiency"):
		c.initiative_bonus = c.proficiency_bonus
	# 내성·기능 숙련
	c.save_proficiencies = cls["saves"].duplicate()
	var skills: Array = spec.get("skills", []).duplicate() + bg["skills"]
	if spec.get("species_skill", "") != "":
		skills.append(spec["species_skill"])
	skills.append_array(spec.get("extra_skills", []))
	c.skill_bonuses = {}
	for s: String in skills:
		c.skill_bonuses[s] = c.proficiency_bonus * (2 if s in expertise else 1)  # 전문화는 숙련 기능에만
	# 훈련·숙련
	c.weapon_proficiencies = _weapon_profs(wt)
	# 무기 마스터리: 레벨별 개수만큼(명세에 미리 적어 둔 다음 선택은 레벨이 오르면 열린다)
	c.weapon_masteries = spec.get("masteries", []).slice(0, _by_level(cls.get("weapon_mastery", {}), lv, 0))
	# HP: 1레벨 최대, 이후 평균 올림(룰북 6단계) + 건강 수정치, 드워프 +1/레벨
	var hd: int = cls["hit_die"]
	var con: int = c.ability_mod("con")
	var hp: int = hd + con + (lv - 1) * (hd / 2 + 1 + con) + int(sp.get("hp_per_level", 0)) * lv
	c.hp_max = maxi(hp, lv)
	c.hp = c.hp_max
	# 자원
	c.resources = {}
	for r: Dictionary in cls.get("resources", []) + sp.get("resources", []):
		var mx := _resource_max(r["max"], lv, c.proficiency_bonus)
		if mx > 0:
			c.resources[r["id"]] = {"current": mx, "max": mx, "recharge": r["recharge"]}
	# 장비·AC
	var eq: Dictionary = cls.get("starting_equipment", {})
	var armor_id: String = spec.get("armor", eq.get("armor", ""))
	var shield: bool = spec.get("shield", eq.get("shield", false))
	c.set_meta("armor", armor_id)
	c.set_meta("shield", shield)
	c.ac_base = armor_class(c, armor_id, shield, armor_training)
	var ws: Dictionary = spec.get("weapons", {"melee": eq.get("melee", {"main": "", "off": ""}), "ranged": eq.get("ranged", {"main": ""})})
	c.weapon_sets = ws.duplicate(true)
	if not c.weapon_sets.has("ranged"):
		c.weapon_sets["ranged"] = {"main": ""}
	# 주문
	_apply_spells(c, cls, sub, sp, lin, spec, lv, extra_cantrips)
	_apply_feat_spells(c, feats, spec)
	# 반응
	c.known_reactions = ["opportunity_attack"]
	for sid: String in c.spells:
		if str(RulesDB.get_entry("spell", sid).get("cast", {}).get("cost", "")) == "reaction":
			c.known_reactions.append(sid)  # 반응 주문(주문 데이터 cast.cost — 반응 처리는 reaction_queue)
	for fid: String in c.feature_data:
		if str(c.feature_data[fid].get("kind", "")) == "reaction":
			c.known_reactions.append(fid)  # 반응 기능(교묘한 회피 등)
	c.set_meta("spec", spec.duplicate(true))
	c.reset_turn()


static func _add_feature(c: Node, f: Dictionary) -> void:
	if f.get("status", "active") == "deferred":
		c.features.append(f["id"])  # 표시만, 동작은 뒤 단계
		return
	c.feature_data[f["id"]] = f
	c.caps.append_array(f.get("caps", []))
	if f.has("hook") and f.has("script"):
		if not c.feature_hooks.has(f["hook"]):
			c.feature_hooks[f["hook"]] = []
		c.feature_hooks[f["hook"]].append(f["script"])


## AC: 갑옷 기본값 + 민첩(상한) + 방패 2 + 방어 재주 1(갑옷을 입었을 때). 갑옷이 없으면 10 + 민첩.
static func armor_class(c: Node, armor_id: String, shield: bool, training: Array = []) -> int:
	var dex: int = c.ability_mod("dex")
	var ac := 10 + dex
	if armor_id != "":
		var a := RulesDB.get_entry("armor", armor_id)
		var cap: Variant = a.get("dex_cap")
		# 중갑(상한 0)은 민첩을 더하지도 빼지도 않는다(SRD Heavy Armor)
		ac = int(a["ac_base"]) + (dex if cap == null else (0 if int(cap) == 0 else mini(dex, int(cap))))
		if c.has_cap("armor_ac_plus_1"):
			ac += 1  # 방어(전투 방식)
	if shield:
		ac += 2
	return ac


static func _weapon_profs(training: Array) -> Array:
	var out: Array = []
	for t: String in training:
		if t == "martial_finesse_or_light":
			for wid: String in RulesDB.ids("weapon"):
				var w := RulesDB.get_entry("weapon", wid)
				if str(w["category"]).begins_with("martial") and ("finesse" in w["properties"] or "light" in w["properties"]):
					out.append(wid)
		else:
			out.append(t)
	return out


static func _apply_spells(c: Node, cls: Dictionary, sub: Dictionary, sp: Dictionary, lin: Dictionary, spec: Dictionary, lv: int, extra_cantrips: int = 0) -> void:
	var spells: Array = []
	var sc: Dictionary = cls.get("spellcasting", {})
	if not sc.is_empty():
		c.spellcasting_ability = sc["ability"]
		var slots: Array = sc["slots"].get(str(lv), [])
		for i in slots.size():
			c.resources["spell_slot_%d" % (i + 1)] = {"current": slots[i], "max": slots[i], "recharge": str(sc.get("slot_recharge", "long"))}
		var cantrips: Array = spec.get("cantrips", [])
		spells.append_array(cantrips.slice(0, _by_level(sc["cantrips"], lv, 0) + extra_cantrips))
		# 준비 주문: 명세 순서대로, 가진 슬롯 레벨 이하인 것만 준비 수만큼(높은 주문은 레벨이 오르면 열린다)
		var max_slot: int = slots.size()
		var castable: Array = spec.get("spells", []).filter(func(sid: Variant) -> bool:
			return int(RulesDB.get_entry("spell", str(sid)).get("level", 99)) <= max_slot)
		spells.append_array(castable.slice(0, _by_level(sc["prepared"], lv, 0)))
	for src: Dictionary in [cls, sub]:
		for k: String in src.get("always_prepared", {}).keys():
			if lv >= int(k):
				spells.append_array(src["always_prepared"][k])  # 클래스·하위 클래스의 항상 준비 주문(준비 수에 세지 않음)
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
			if int(RulesDB.get_entry("spell", s)["level"]) > 0:
				c.resources["innate_" + s] = {"current": 1, "max": 1, "recharge": "long"}
		if c.spellcasting_ability == "" and pick.has("ability"):
			c.spellcasting_ability = str(pick["ability"])


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


static func _resource_max(mx: Variant, lv: int, pb: int) -> int:
	if typeof(mx) == TYPE_STRING and mx == "proficiency_bonus":
		return pb
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
	return base
