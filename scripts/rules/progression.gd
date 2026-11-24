extends RefCounted
## 경험치·레벨 업·동료 영입(룰북 7단계 '캠프와 동료': 영입한 동료 전원이 같은 경험치, 레벨업은 전투 밖 언제나,
## SRD 경험치 표·상한은 data/rules/progression.json). 경험치는 파티 공용 world["xp"].

const SpellPrep := preload("res://scripts/rules/spell_prep.gd")
const Builder := preload("res://scripts/rules/character_builder.gd")

const Levels := preload("res://scripts/rules/levels.gd")
const PARTY_MAX := 4


## 레벨 상한(data/rules/progression.json)
static func level_cap() -> int:
	return Levels.level_cap()


static func level_for(xp: int) -> int:
	return Levels.level_for(xp)


static func award(world: Dictionary, xp: int, why: String = "") -> void:
	world["xp"] = int(world.get("xp", 0)) + xp
	Dice.log_text("경험치 +%d%s (합계 %d)" % [xp, " — " + why if why != "" else "", world["xp"]])


## 쓰러뜨린 적의 경험치(몬스터 데이터 xp)를 모은다. 전투가 끝날 때 부른다.
static func award_defeated(world: Dictionary, foes: Array) -> int:
	var total := 0
	for f: Node in foes:
		if f.dead and not f.get_meta("xp_given", false):
			f.set_meta("xp_given", true)
			total += int(f.get_meta("monster", {}).get("xp", 0))
	if total > 0:
		award(world, total, "전투")
	return total


static func can_level_up(world: Dictionary, c: Node) -> bool:
	if not c.has_meta("spec") or c.dead:
		return false
	if world.get("turns") != null and world["turns"].in_combat:
		return false
	return c.level < level_for(int(world.get("xp", 0)))


## 한 레벨 올린다: 명세를 다시 적용하고, 잃은 HP는 그대로 둔다(최대치가 늘어난 만큼 현재 HP도 는다).
## cid를 주면 그 클래스에 레벨을 더한다(멀티클래스 — 처음 들어가는 클래스면 1레벨로 붙는다, 선행 조건 없음 BG3식).
## extra: 새 클래스 항목에 넣을 값(subclass·skills·cantrips·spells).
static func level_up(world: Dictionary, c: Node, cid: String = "", extra: Dictionary = {}) -> bool:
	if not can_level_up(world, c):
		return false
	var spec := next_spec(c, cid, extra)
	if spec.is_empty():
		return false
	Builder.reapply(c, spec)
	SpellPrep.open_window(c, "level_up")
	Dice.log_text("%s: %d레벨이 되었다" % [c.label(), c.level])
	return true


## 레벨 업한 명세(검사 통과 못 하면 {}). extra asi_pick = 이번 레벨 능력치 향상 칸 값({"str": 2} 또는 {"feat": id, ...} — BG3 재주 고르기 창).
static func next_spec(c: Node, cid: String = "", extra: Dictionary = {}) -> Dictionary:
	var pick: Dictionary = extra.get("asi_pick", {})
	extra = extra.duplicate()
	extra.erase("asi_pick")
	var spec: Dictionary = c.get_meta("spec").duplicate(true)
	if cid == "" or (cid == c.class_id and spec.get("classes", []).is_empty()):
		if spec.get("classes", []).is_empty():
			spec["level"] = c.level + 1
		else:
			spec["classes"][0]["level"] = int(spec["classes"][0]["level"]) + 1
			spec["level"] = c.level + 1
	else:
		if spec.get("classes", []).is_empty():
			spec["classes"] = [{"class": spec.get("class", c.class_id), "level": int(spec.get("level", c.level)), "subclass": spec.get("subclass", "")}]
		var found := false
		for e: Dictionary in spec["classes"]:
			if str(e["class"]) == cid:
				e["level"] = int(e["level"]) + 1
				e.merge(extra, true)
				found = true
		if not found:
			var ne := {"class": cid, "level": 1}
			ne.merge(extra, true)
			spec["classes"].append(ne)
		spec["level"] = c.level + 1
	fill_choices(c, spec)
	if not pick.is_empty():
		var lv := asi_level_for(c, cid)
		if lv > 0:
			var primary: bool = cid == "" or cid == c.class_id
			if primary:
				if not spec.has("asi"):
					spec["asi"] = {}
				spec["asi"][str(lv)] = pick.duplicate()
			else:
				for e: Dictionary in spec.get("classes", []):
					if str(e["class"]) == cid:
						if not e.has("asi"):
							e["asi"] = {}
						e["asi"][str(lv)] = pick.duplicate()
	Builder.fill_asi(spec)
	if not Builder.validate(spec).is_empty():
		return {}
	return spec


## 이번 레벨 업으로 그 클래스가 능력치 향상(재주) 레벨에 닿으면 그 클래스 레벨, 아니면 0.
static func asi_level_for(c: Node, cid: String = "") -> int:
	var k := cid if cid != "" else str(c.class_id)
	var cur: int = c.class_level(k) if c.class_levels.has(k) or k == c.class_id else 0
	var lv := cur + 1
	for a: Variant in RulesDB.get_entry("class", k).get("asi_levels", []):
		if int(a) == lv:
			return lv
	return 0


## 재주 고르기 창의 선택지(BG3식): 능력치 +2(능력 6개)와 일반 재주. 재주의 고르는 +1은 그 목록에서 가장 높은 능력에 자동.
## 명세 검사를 통과하는 것만: [{"pick": asi 칸 값, "name": {ko, en}}]
static func feat_choices(c: Node, cid: String = "") -> Array:
	var out: Array = []
	if asi_level_for(c, cid) <= 0:
		return out
	var ab_ko := {"str": "근력", "dex": "민첩", "con": "건강", "int": "지능", "wis": "지혜", "cha": "매력"}
	for a: String in ["str", "dex", "con", "int", "wis", "cha"]:
		var p := {a: 2}
		if not next_spec(c, cid, {"asi_pick": p}).is_empty() and int(c.abilities.get(a, 10)) <= 18:
			out.append({"pick": p, "name": {"ko": "능력치 향상: %s +2" % ab_ko[a], "en": "Ability Improvement: %s +2" % a.to_upper()}})
	for ft: Dictionary in RulesDB.entries("feat"):
		if str(ft.get("category", "")) != "general" or str(ft["id"]) == "ability_score_improvement":
			continue
		var p := {"feat": ft["id"]}
		var inc: Dictionary = ft.get("ability_increase", {})
		if inc.has("choose"):
			var best := ""
			for a: String in inc["choose"]:
				if best == "" or int(c.abilities.get(a, 0)) > int(c.abilities.get(best, 0)):
					best = a
			if best != "":
				p[best] = int(inc.get("total", 1))
		if next_spec(c, cid, {"asi_pick": p}).is_empty():
			continue
		out.append({"pick": p, "name": ft.get("name", {"ko": ft["id"], "en": ft["id"]})})
	return out


## 새로 얻은 고르는 기능(choice_kind)의 선택이 명세에 없으면 채운다: 그 클래스 추천 빌드 값 → 첫 선택지(재주는 이미 고른 것 빼고).
## 전문화 선택지가 비어 있으면(로그 6레벨) 전문화하지 않은 숙련 기능에서 고른다.
static func fill_choices(c: Node, spec: Dictionary) -> void:
	for e: Dictionary in Builder.class_entries(spec):
		var cls: Dictionary = e["cls"]
		var feats: Array = cls.get("features", []).duplicate()
		feats.append_array((e["sub"] as Dictionary).get("features", []))
		var db: Dictionary = cls.get("default_build", {})
		for f: Dictionary in feats:
			var fid := str(f["id"])
			var kind := str(f.get("choice_kind", ""))
			if kind == "" or int(f["level"]) > int(e["level"]) or spec.has(fid):
				continue
			var n := int(f.get("count", 1))
			if db.has(fid):
				spec[fid] = db[fid].duplicate() if db[fid] is Array else db[fid]
				continue
			var opts: Array = f.get("choices", []).duplicate()
			if kind == "expertise" and opts.is_empty():
				var expert: Array = spec.get("expertise", [])
				for sk: String in c.skill_bonuses:
					if int(c.skill_bonuses[sk]) == c.proficiency_bonus and not sk in expert:
						opts.append(sk)
			if kind == "feat":
				opts = opts.filter(func(o: String) -> bool: return not spec.values().has(o))
			if opts.is_empty():
				continue
			spec[fid] = opts.slice(0, n) if n > 1 else opts[0]


## 새 클래스에 처음 들어갈 때 명세 항목에 넣을 기본 선택(그 클래스 추천 빌드 — 하위 클래스·소마법·주문·멀티클래스 기능 숙련).
static func new_class_extra(c: Node, cid: String) -> Dictionary:
	var cls := RulesDB.get_entry("class", cid)
	var db: Dictionary = cls.get("default_build", {})
	var out := {"subclass": str(db.get("subclass", ""))}
	if db.has("cantrips"):
		out["cantrips"] = db["cantrips"].duplicate()
	if db.has("spells"):
		out["spells"] = db["spells"].duplicate()
	var mc: Dictionary = cls.get("multiclass", {}).get("skills", {})
	if int(mc.get("choose", 0)) > 0:
		var from: Array = cls.get("skills", {}).get("from", []) if str(mc.get("from", "class")) == "class" else Builder.SKILL_ABILITY.keys()
		var pick: Array = []
		for s: String in db.get("skills", []) + from:
			if not c.skill_bonuses.has(s) and not s in pick:
				pick.append(s)
		out["skills"] = pick.slice(0, int(mc["choose"]))
	return out


## 레벨 업 때 고를 수 있는 클래스: 지금 클래스들(주 클래스 먼저) + 아직 없는 모든 클래스(선행 조건 없음 — BG3식).
static func level_up_choices(c: Node) -> Array:
	var have: Array = [str(c.class_id)]
	for k: String in c.class_levels:
		if not k in have:
			have.append(k)
	var out: Array = have.duplicate()
	for k: String in RulesDB.ids("class"):
		if not k in out:
			out.append(k)
	return out


# ---------- 동료 영입 ----------

## 동료를 영입한다. 활성 파티가 4명이면 캠프에서 쉰다(world["roster"]).
static func recruit(world: Dictionary, c: Node) -> String:
	if c.team == "party" and (c in world.get("party", []) or c in world.get("roster", [])):
		return ""
	c.team = "party"
	c.awareness.clear()
	# 경험치는 모두 같다: 영입한 동료를 파티 레벨로 맞춘다
	while can_level_up(world, c):
		level_up(world, c)
	var party: Array = world.get("party", [])
	if party.size() < PARTY_MAX:
		party.append(c)
		world["party"] = party
		if world.get("explore") != null:
			var ex: Node = world["explore"]
			if not c in ex.party:
				ex.party.append(c)
			ex.linked[c] = true
		Dice.log_text("%s가 파티에 합류했다" % c.label())
		return "party"
	if not world.has("roster"):
		world["roster"] = []
	world["roster"].append(c)
	Dice.log_text("%s가 캠프에서 기다린다" % c.label())
	return "camp"


## 캠프에서 활성 파티 교체(캠프에서만 — world["at_camp"]).
static func swap(world: Dictionary, out_c: Node, in_c: Node) -> bool:
	if not world.get("at_camp", false):
		return false
	var party: Array = world.get("party", [])
	var roster: Array = world.get("roster", [])
	if not out_c in party or not in_c in roster:
		return false
	party[party.find(out_c)] = in_c
	roster[roster.find(in_c)] = out_c
	if world.get("explore") != null:
		var ex: Node = world["explore"]
		ex.party = party.duplicate()
		ex.linked[in_c] = true
	return true
