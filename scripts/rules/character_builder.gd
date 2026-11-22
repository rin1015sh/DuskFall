extends RefCounted
## 캐릭터 생성·성장(룰북 6단계). 데이터(classes·species·backgrounds·feats·armor·weapons)를 읽어 Creature를 만든다.
## 같은 명세(spec)에 레벨만 바꿔 다시 만들면 레벨업이다(선택은 명세에 누적해 둔다).
##
## spec = {
##   "name": {"ko", "en"}, "species": "elf", "lineage": "elf_high", "size": "medium"(고를 수 있는 종족),
##   "background": "sage", "class": "wizard", "subclass": "evoker", "level": 1~5,
##   "scores": {"str": 8, ...}(포인트 구매 전 값 8~15), "bonus": {"int": 2, "con": 1}(+2/+1 또는 +1/+1/+1),
##   "skills": [클래스 기능], "species_skill": "perception", "expertise": [...], "extra_skills": [숙련 재주 등],
##   "fighting_style": "defense", "divine_order": "protector", "scholar": "arcana",
##   "asi": {"4": {"str": 2}}(4레벨 능력치 향상 또는 {"feat": id}), "origin_feat": "alert"(인간),
##   "masteries": [무기 ID], "cantrips": [...], "spells": [준비 주문 / 주문서],
##   "armor": "chain_mail", "shield": true, "weapons": {"melee": {"main", "off"}, "ranged": {"main"}}
## }

const CreatureScript := preload("res://scripts/rules/creature.gd")

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
	if lv < 1 or lv > 5:
		e.append("1차 레벨 범위는 1~5")
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
	if lv >= 3 and spec.get("subclass", "") == "":
		e.append("3레벨부터 하위 클래스를 골라야 한다")
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
	c.proficiency_bonus = _by_level(cls["proficiency_bonus"], lv, 2)
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
	# 내성·기능
	c.save_proficiencies = cls["saves"].duplicate()
	var skills: Array = spec.get("skills", []).duplicate() + bg["skills"]
	if spec.get("species_skill", "") != "":
		skills.append(spec["species_skill"])
	skills.append_array(spec.get("extra_skills", []))
	if spec.get("scholar", "") != "" and lv >= 2 and cls["id"] == "wizard":
		pass  # 학자 = 전문화(아래 expertise에 넣는다)
	var expertise: Array = spec.get("expertise", []).duplicate()
	if spec.get("scholar", "") != "" and lv >= 2:
		expertise.append(spec["scholar"])
	c.skill_bonuses = {}
	for s: String in skills:
		c.skill_bonuses[s] = c.proficiency_bonus * (2 if s in expertise else 1)
	# 기능·재주
	c.features = []
	c.feature_data = {}
	c.feature_hooks = {}
	for f: Dictionary in cls["features"] + sub.get("features", []):
		if int(f.get("level", 1)) <= lv:
			_add_feature(c, f)
	for f: Dictionary in sp.get("features", []) + lin.get("features", []):
		_add_feature(c, f)
	if spec.get("fighting_style", "") != "" and c.has_feature("fighting_style"):
		feats.append(spec["fighting_style"])
	for fid: String in feats:
		var ft := RulesDB.get_entry("feat", fid)
		c.features.append(fid)
		c.features.append_array(ft.get("tags", []))
		if "initiative_proficiency" in ft.get("tags", []):
			c.initiative_bonus = c.proficiency_bonus
	if c.has_feature("remarkable_athlete"):
		c.extra_modifiers.append({"effect": {"type": "advantage", "roll": "initiative", "side": "self", "value": "advantage"},
			"source": "remarkable_athlete"})
	if c.has_feature("improved_critical"):
		c.crit_threshold = 19
	if c.has_feature("extra_attack"):
		c.attacks_per_action = 2
	# 훈련·숙련
	var wt: Array = cls["weapon_training"].duplicate()
	if spec.get("divine_order", "") == "protector" and cls["id"] == "cleric":
		wt.append("martial")
	c.weapon_proficiencies = _weapon_profs(wt)
	var armor_training: Array = cls["armor_training"].duplicate()
	if spec.get("divine_order", "") == "protector":
		armor_training.append("heavy")
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
	_apply_spells(c, cls, sub, sp, lin, spec, lv)
	# 반응
	c.known_reactions = ["opportunity_attack"]
	if c.spells.has("shield"):
		c.known_reactions.append("shield")
	if c.has_feature("uncanny_dodge"):
		c.known_reactions.append("uncanny_dodge")
	for r: String in ["hellish_rebuke", "counterspell", "feather_fall"]:
		if c.spells.has(r):
			c.known_reactions.append(r)
	c.set_meta("spec", spec.duplicate(true))
	c.reset_turn()


static func _add_feature(c: Node, f: Dictionary) -> void:
	if f.get("status", "active") == "deferred":
		c.features.append(f["id"])  # 표시만, 동작은 뒤 단계
		return
	c.feature_data[f["id"]] = f
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
		if c.has_feature("defense"):
			ac += 1
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


static func _apply_spells(c: Node, cls: Dictionary, sub: Dictionary, sp: Dictionary, lin: Dictionary, spec: Dictionary, lv: int) -> void:
	var spells: Array = []
	var sc: Dictionary = cls.get("spellcasting", {})
	if not sc.is_empty():
		c.spellcasting_ability = sc["ability"]
		var slots: Array = sc["slots"].get(str(lv), [])
		for i in slots.size():
			c.resources["spell_slot_%d" % (i + 1)] = {"current": slots[i], "max": slots[i], "recharge": "long"}
		var cantrips: Array = spec.get("cantrips", [])
		spells.append_array(cantrips.slice(0, _by_level(sc["cantrips"], lv, 0) + (1 if spec.get("divine_order", "") == "thaumaturge" else 0)))
		spells.append_array(spec.get("spells", []).slice(0, _by_level(sc["prepared"], lv, 0)))
	for k: String in sub.get("always_prepared", {}).keys():
		if lv >= int(k):
			spells.append_array(sub["always_prepared"][k])
	for s: Dictionary in sp.get("spells", []) + lin.get("spells", []):
		if lv >= int(s["level"]):
			spells.append(s["spell"])
	var uniq: Array = []
	for s: String in spells:
		if not s in uniq and not RulesDB.get_entry("spell", s).is_empty():
			uniq.append(s)
	c.spells = uniq
	if c.spellcasting_ability == "" and not uniq.is_empty():
		c.spellcasting_ability = spec.get("origin_ability", "cha")


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


## 기본 명세(동료·시험용). 클래스마다 SRD 추천을 따른다.
static func default_spec(class_id: String, level: int = 1) -> Dictionary:
	var base := {"level": level, "team": "party"}
	match class_id:
		"fighter":
			base.merge({"class": "fighter", "subclass": "champion", "species": "human", "background": "soldier",
				"scores": {"str": 15, "dex": 13, "con": 14, "int": 8, "wis": 12, "cha": 10}, "bonus": {"str": 2, "con": 1},
				"skills": ["perception", "survival"], "species_skill": "acrobatics", "origin_feat": "alert",
				"fighting_style": "defense", "masteries": ["longsword", "greatsword", "javelin", "shortbow"],
				"asi": {"4": {"str": 2}}, "armor": "chain_mail", "shield": true,
				"weapons": {"melee": {"main": "longsword", "off": ""}, "ranged": {"main": "javelin"}}})
		"rogue":
			base.merge({"class": "rogue", "subclass": "thief", "species": "halfling", "background": "criminal",
				"scores": {"str": 8, "dex": 15, "con": 14, "int": 12, "wis": 13, "cha": 10}, "bonus": {"dex": 2, "con": 1},
				"skills": ["acrobatics", "perception", "investigation", "deception"], "expertise": ["stealth", "perception"],
				"masteries": ["shortsword", "dagger"], "asi": {"4": {"dex": 2}}, "armor": "leather_armor",
				"weapons": {"melee": {"main": "shortsword", "off": "dagger"}, "ranged": {"main": "shortbow"}}})
		"cleric":
			base.merge({"class": "cleric", "subclass": "life", "species": "dwarf", "background": "acolyte",
				"scores": {"str": 14, "dex": 8, "con": 13, "int": 10, "wis": 15, "cha": 12}, "bonus": {"wis": 2, "con": 1},
				"skills": ["medicine", "persuasion"], "divine_order": "protector",
				"cantrips": ["sacred_flame", "guidance", "spare_the_dying", "light"],
				"spells": ["healing_word", "guiding_bolt", "shield_of_faith", "sanctuary", "spiritual_weapon", "hold_person", "spirit_guardians", "mass_healing_word", "dispel_magic"],
				"asi": {"4": {"wis": 2}}, "armor": "chain_mail", "shield": true,
				"weapons": {"melee": {"main": "mace", "off": ""}, "ranged": {"main": "light_crossbow"}}})
		"wizard":
			base.merge({"class": "wizard", "subclass": "evoker", "species": "elf", "lineage": "elf_high", "background": "sage",
				"scores": {"str": 8, "dex": 14, "con": 13, "int": 15, "wis": 12, "cha": 10}, "bonus": {"int": 2, "dex": 1},
				"skills": ["investigation", "insight"], "species_skill": "perception", "scholar": "arcana",
				"cantrips": ["fire_bolt", "ray_of_frost", "shocking_grasp", "light"],
				"spells": ["magic_missile", "shield", "burning_hands", "sleep", "scorching_ray", "misty_step", "fireball", "counterspell", "haste"],
				"asi": {"4": {"int": 2}}, "armor": "",
				"weapons": {"melee": {"main": "quarterstaff", "off": ""}, "ranged": {"main": "dagger"}}})
	return base
