extends RefCounted
## 대화(룰북 5단계 '대화 판정과 영감', 2단계 보이는 굴림·자동 판정). 대화 하나 = 이 객체 하나.
##   데이터: data/dialogues/<id>.json (dialogue_v1) — 노드마다 대사·선택지·자동 판정·효과.
##   선택지 판정(check): 말하는 캐릭터가 굴린다. DC를 미리 보여 주고, 보조 주사위·영감 재굴림(Interact.visible_check).
##     DC를 적지 않으면 기본 15, 상대가 적대면 +5, 우호면 −5.
##   대화 중 내성(save): 자연 20 자동 성공·자연 1 자동 실패(2단계 결정 1).
##   자동 판정(auto): 노드에 들어갈 때 숨은 굴림(통찰 = 지혜, 지식 = 지능). 성공하면 태그 + 추가 대사.
##   requires: world["dialogue_tags"]·world["flags"]에 있어야 보이는 선택지(주문 해금 태그 포함).
##   전투 중에는 대화하지 않는다(3단계).

const Interact := preload("res://scripts/rules/interact.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Goals := preload("res://scripts/rules/goals.gd")
const Progression := preload("res://scripts/rules/progression.gd")

const ATTITUDE_DC := {"friendly": -5, "indifferent": 0, "hostile": 5}
const BASE_DC := 15

var world: Dictionary
var data: Dictionary
var speaker: Node
var npc: Node
var node_id := ""
var finished := false
## 이번 노드에서 자동 판정으로 덧붙은 대사
var extra_lines: Array = []
## 대화 결과: "" | "hostile"(적대로 넘어감)
var outcome := ""
var history: Array = []


static func start(w: Dictionary, id: String, who: Node, with_npc: Node = null) -> RefCounted:
	if w.get("turns") != null and w["turns"].in_combat:
		return null
	var d := RulesDB.get_entry("dialogue", id)
	if d.is_empty():
		return null
	var s: RefCounted = load("res://scripts/rules/dialogue.gd").new()
	s.world = w
	s.data = d
	s.speaker = who
	s.npc = with_npc
	s._enter(d["start"])
	return s


func node() -> Dictionary:
	for n: Dictionary in data["nodes"]:
		if n["id"] == node_id:
			return n
	return {}


func text() -> Dictionary:
	return node().get("text", {"ko": "", "en": ""})


## 지금 고를 수 있는 선택지: [{"index", "text", "kind": "goto|check|save", "dc", "chance"}]
func options() -> Array:
	var out: Array = []
	var opts: Array = node().get("options", [])
	for i in opts.size():
		var o: Dictionary = opts[i]
		if not _has_all(o.get("requires", [])) or Interact.count(world, "gold") < int(o.get("cost_gold", 0)):
			continue
		var row := {"index": i, "text": o["text"], "kind": "goto"}
		if o.has("check"):
			var ck: Dictionary = o["check"]
			row["kind"] = "check"
			row["dc"] = dc_of(ck)
			row["skill"] = ck.get("skill", "")
			row["chance"] = Interact.preview_check(speaker, ck["ability"], ck.get("skill", ""), row["dc"])["chance"]
		elif o.has("save"):
			row["kind"] = "save"
			row["dc"] = int(o["save"]["dc"])
			row["ability"] = o["save"]["ability"]
		out.append(row)
	return out


## 선택지의 능력 판정({ability, skill, dc}, 없으면 빈 사전) — 화면이 판정 창을 먼저 띄울 때 쓴다.
func option_check(index: int) -> Dictionary:
	var o: Dictionary = node()["options"][index]
	if not o.has("check"):
		return {}
	var ck: Dictionary = o["check"]
	return {"ability": ck["ability"], "skill": ck.get("skill", ""), "dc": dc_of(ck)}


func dc_of(ck: Dictionary) -> int:
	if ck.has("dc"):
		return int(ck["dc"])
	return BASE_DC + int(ATTITUDE_DC.get(data.get("attitude", "indifferent"), 0))


## 선택. opts: {"assist": [주사위], "inspiration": bool(실패하면 영감으로 다시 굴림)}
func choose(index: int, opts: Dictionary = {}) -> Dictionary:
	if finished:
		return {"ok": false}
	var o: Dictionary = node()["options"][index]
	if not _has_all(o.get("requires", [])):
		return {"ok": false, "reason": "고를 수 없다"}
	history.append({"node": node_id, "option": index})
	var res := {"ok": true}
	var next: String = o.get("goto", "")
	if o.has("check"):
		var ck: Dictionary = o["check"]
		var r: Dictionary = Interact.visible_check(world, speaker, ck["ability"], ck.get("skill", ""), dc_of(ck), opts)
		res["check"] = r
		next = o["success"] if r["success"] else o["fail"]
	elif o.has("save"):
		var sv: Dictionary = o["save"]
		var r := Resolver.saving_throw(speaker, sv["ability"], int(sv["dc"]), {"natural_rules": true})
		res["save"] = r
		next = o["success"] if r["success"] else o["fail"]
	# 판정·내성 선택지의 효과는 성공했을 때만(영감 목표 '달성' — 5단계)
	var passed: bool = res.get("check", res.get("save", {"success": true}))["success"]
	if passed:
		_apply(o.get("effects", []))
	if next == "" or finished:
		finished = true
	else:
		_enter(next)
	return res


func _enter(id: String) -> void:
	node_id = id
	extra_lines.clear()
	var n := node()
	for a: Dictionary in n.get("auto", []):
		var tag: String = a["tag"]
		if world.get("dialogue_tags", {}).has(tag):
			continue
		var best := false
		for c: Node in Goals.party_of(world) if not Goals.party_of(world).is_empty() else [speaker]:
			if c.dead:
				continue
			# 자동 판정: 숨은 굴림, 파티원 각자(대화 중 통찰·지식)
			if Resolver.ability_check(c, a["ability"], int(a["dc"]), {"skill": a.get("skill", "")})["success"]:
				best = true
				break
		if best:
			_tag(tag)
			extra_lines.append(a["line"])
	_apply(n.get("effects", []))
	if n.get("end", false) or n.get("options", []).is_empty():
		finished = true


func _apply(effects: Array) -> void:
	for e: Dictionary in effects:
		match e["type"]:
			"set_flag":
				if not world.has("flags"):
					world["flags"] = {}
				world["flags"][e["flag"]] = true
			"give_item":
				Interact.give(world, e["item"], int(e.get("count", 1)))
			"gold":
				Interact.give(world, "gold", maxi(int(e["add"]), -Interact.count(world, "gold")))
			"inspiration_goal":
				Goals.complete(world, e["goal"])
			"hostile":
				outcome = "hostile"
				finished = true
				if npc != null:
					# 소유자와 같은 세력이 모두 적대로 넘어간다
					for o: Node in world["grid"].creatures():
						if o == npc or (npc.faction != "" and o.faction == npc.faction):
							o.team = "enemy"
					if world.get("explore") != null:
						world["explore"].hostile_action(speaker, npc)
			"pacify":
				# 평화 해결: 상대 세력 전원이 중립이 된다(구역 보상은 적이 남지 않으면 받는다)
				if npc != null:
					for o: Node in world["grid"].creatures():
						if o == npc or (npc.faction != "" and o.faction == npc.faction):
							o.team = "neutral"
							o.awareness.clear()
			"recruit":
				if npc != null:
					Progression.recruit(world, npc)
			"xp":
				Progression.award(world, int(e["add"]), "대화")
			"end":
				finished = true


func _has_all(tags: Array) -> bool:
	for t: String in tags:
		if not world.get("dialogue_tags", {}).has(t) and not world.get("flags", {}).has(t):
			return false
	return true


func _tag(t: String) -> void:
	if not world.has("dialogue_tags"):
		world["dialogue_tags"] = {}
	world["dialogue_tags"][t] = true
