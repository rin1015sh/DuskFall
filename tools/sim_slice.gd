extends SceneTree
## 수직 슬라이스 자동 플레이(7단계 /balance-check·버그 찾기). 무너진 초소(fallen_watch)를 처음부터 끝까지 돈다:
##   동료 2명 영입 → 동굴(예시 전투 1) → 레벨 업·휴식 → 공터(예시 전투 2, 두목 대화에서 싸움을 고름) → 레벨 업·휴식 → 절벽 길(예시 전투 3).
## 실행: godot --headless --path . -s res://tools/sim_slice.gd -- --runs=50 [--talk=fight|intimidate] [--verbose]
## 전투는 양쪽 모두 단순 AI. 탐험 이동은 리더가 구역 안 목표 칸으로 걷고 묶인 파티원이 따라간다.

# 오토로드를 쓰는 스크립트는 -s 실행에서 컴파일 시점에 불러올 수 없어 실행 중에 load한다.
var WorldBuilder: Variant
var ExplorationScript: Variant
var Dialogue: Variant
var Progression: Variant
var Rest: Variant
var AI: Variant
var Spellcasting: Variant

## 구역 순서: [구역, 리더가 걸어갈 칸들, 끝나고 쉴 캠프 칸]
const ROUTE := [
	["cave", [Vector2i(14, 6), Vector2i(20, 6), Vector2i(26, 7)]],
	["clearing", [Vector2i(5, 15), Vector2i(7, 19), Vector2i(12, 21)]],
	["cliff", [Vector2i(28, 21), Vector2i(33, 20), Vector2i(35, 15), Vector2i(37, 9)]],
]
const CAMP := Vector2i(6, 6)

var _done := false
var args := {}


func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	WorldBuilder = load("res://scripts/rules/world_builder.gd")
	ExplorationScript = load("res://scripts/rules/exploration.gd")
	Dialogue = load("res://scripts/rules/dialogue.gd")
	Progression = load("res://scripts/rules/progression.gd")
	Rest = load("res://scripts/rules/rest.gd")
	AI = load("res://scripts/ai/simple_ai.gd")
	Spellcasting = load("res://scripts/rules/spellcasting.gd")
	for a: String in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	var runs := int(args.get("runs", "20"))
	var agg := {}
	var finished := 0
	var bugs := {}
	for i in runs:
		root.get_node("Dice").set_seed(5000 + i)
		var r := play()
		if r["finished"]:
			finished += 1
		for z: String in r["zones"]:
			if not agg.has(z):
				agg[z] = {"n": 0, "win": 0, "rounds": 0, "downs": 0, "deaths": 0, "level": 0, "surprised": 0, "dialogue": 0}
			var a: Dictionary = agg[z]
			var zr: Dictionary = r["zones"][z]
			a["n"] += 1
			for k: String in ["win", "rounds", "downs", "deaths", "level", "surprised", "dialogue"]:
				a[k] += int(zr.get(k, 0))
		for b: String in r["bugs"]:
			bugs[b] = int(bugs.get(b, 0)) + 1
	print("== 무너진 초소 슬라이스 %d회: 끝까지 간 비율 %.0f%%" % [runs, 100.0 * finished / runs])
	for z: String in agg:
		var a: Dictionary = agg[z]
		var n: float = maxf(a["n"], 1)
		print("   %s: 도달 %d회, 승률 %.0f%%, 레벨 %.1f, 평균 %.1f라운드, 쓰러짐 %.2f, 사망 %.2f, 파티 기습 %.0f%%, 대화로 시작 %.0f%%" % [
			z, a["n"], 100.0 * a["win"] / n, a["level"] / n, a["rounds"] / n, a["downs"] / n, a["deaths"] / n,
			100.0 * a["surprised"] / n, 100.0 * a["dialogue"] / n])
	for b: String in bugs:
		print("   [이상] %s — %d회" % [b, bugs[b]])
	quit()
	return true


func play() -> Dictionary:
	var out := {"finished": false, "zones": {}, "bugs": []}
	var b: Dictionary = WorldBuilder.build("fallen_watch")
	var w: Dictionary = b["world"]
	var grid: Node = w["grid"]
	var ex: Node = ExplorationScript.new().setup(w, b["party"])
	var nodes: Array = b["nodes"] + [ex]
	var downs := {"n": 0}
	var on_zero := func(info: Dictionary) -> void:
		if info["creature"].team == "party":
			downs["n"] += 1
	root.get_node("EventBus").on_hp_zero.connect(on_zero)
	var leader: Node = b["party"][0]
	# 1. 동료 영입
	for c: Node in b["foes"]:
		if c.team == "neutral" and c.has_meta("dialogue"):
			_talk(w, leader, c, "first")
	if w["party"].size() != 4:
		out["bugs"].append("동료 영입 실패(파티 %d명)" % w["party"].size())
	_level_all(w)
	# 2. 구역 차례로
	for step: Array in ROUTE:
		var zone: String = step[0]
		var zr := {"win": 0}
		downs["n"] = 0
		var started := false
		ex.regroup()
		for target: Vector2i in step[1]:
			ex.move_to(leader, target)
			ex.regroup()
			if w.has("pending_dialogue"):
				var pd: Dictionary = w["pending_dialogue"]
				w.erase("pending_dialogue")
				zr["dialogue"] = 1
				_talk(w, pd.get("speaker", leader) if pd.get("speaker") in w["party"] else leader, pd["npc"], args.get("talk", "fight"))
			if w["turns"].in_combat:
				started = true
				break
		if not started and not w["turns"].in_combat:
			# 아무도 못 봤으면 가장 가까운 적을 공격해 시작한다
			var foe := _nearest_enemy(w, leader, zone)
			if foe != null:
				ex.hostile_action(leader, foe)
		if w["turns"].in_combat:
			zr["surprised"] = 1 if w["party"].any(func(p: Node) -> bool: return p.has_condition("surprised")) else 0
			var tm: Node = w["turns"]
			var guard := 0
			while tm.in_combat and guard < 800:
				guard += 1
				var g: Array = tm.current_group()
				if g.is_empty():
					out["bugs"].append("%s: 턴 그룹이 비었다" % zone)
					break
				AI.take_turn(w, g[0])
				if tm.in_combat:
					tm.end_turn(g[0])
			if guard >= 800:
				out["bugs"].append("%s: 전투가 끝나지 않음" % zone)
			zr["rounds"] = tm.round_number
			if args.has("log") and zone == args["log"]:
				for e: Dictionary in root.get_node("Dice").roll_log:
					if e["kind"] == "text":
						print("    ", e["text"])
				for p: Node in w["party"]:
					print("    파티 %s %s hp %d/%d" % [p.name, grid.cell_of(p), p.hp, p.hp_max])
			zr["win"] = 1 if tm.result == "victory" else 0
		elif zone != "clearing" or args.get("talk", "fight") == "fight":
			out["bugs"].append("%s: 전투가 시작되지 않음" % zone)
		zr["downs"] = downs["n"]
		zr["deaths"] = w["party"].filter(func(p: Node) -> bool: return p.dead).size()
		zr["level"] = leader.level
		out["zones"][zone] = zr
		if w["turns"].result == "defeat":
			break
		ex.check_zone_rewards()
		if not w.get("zones_cleared", {}).has(zone):
			var left: Array = grid.creatures().filter(func(o: Node) -> bool: return o.team == "enemy" and not o.dead)
			out["bugs"].append("%s: 구역 보상을 못 받음(남은 적 %s)" % [zone, ", ".join(left.map(func(o: Node) -> String: return "%s@%s" % [o.name, grid.cell_of(o)]))])
		# 죽은 동료는 캠프 부활(200gp), 레벨 업, 캠프로 돌아가 긴 휴식
		for p: Node in w["party"]:
			if p.dead:
				w["inventory"]["gold"] = int(w["inventory"].get("gold", 0)) + 200
				Rest.camp_revive(w, p)
		_level_all(w)
		if leader.dead or leader.is_down():
			leader = w["party"].filter(func(p: Node) -> bool: return not p.dead)[0]
			ex.leader = leader
		ex.move_to(leader, CAMP)
		var rr: Dictionary = Rest.long_rest(w, w["party"])
		if not rr.get("ok", false):
			var blocker: Variant = grid.creature_at(CAMP)
			out["bugs"].append("%s 뒤 긴 휴식 불가: %s (리더 %s, 캠프 칸 %s)" % [zone, rr.get("reason", ""), grid.cell_of(leader),
				blocker.name if blocker != null else "-"])
		if w["party"].any(func(p: Node) -> bool: return p.hp < p.hp_max and not rr.get("partial", false) and rr.get("ok", false)):
			out["bugs"].append("긴 휴식 뒤 HP가 덜 찼다")
	out["finished"] = out["zones"].size() == ROUTE.size() and out["zones"].values().all(func(z: Dictionary) -> bool: return z["win"] == 1 or z.get("dialogue", 0) == 1)
	root.get_node("EventBus").on_hp_zero.disconnect(on_zero)
	Spellcasting.instances.clear()
	for n: Node in nodes:
		if is_instance_valid(n):
			n.free()
	return out


## 대화 정책: first = 첫 선택지를 계속, fight = 싸움을 고름, intimidate = 위협(없으면 싸움).
func _talk(w: Dictionary, speaker: Node, npc: Node, policy: String) -> void:
	var d: RefCounted = Dialogue.start(w, npc.get_meta("dialogue"), speaker, npc)
	if d == null:
		return
	var guard := 0
	while not d.finished and guard < 20:
		guard += 1
		var opts: Array = d.options()
		if opts.is_empty():
			break
		var pick: Dictionary = opts[0]
		if policy != "first":
			for o: Dictionary in opts:
				var en: String = o["text"]["en"]
				if policy == "intimidate" and en.begins_with("[Intimidation]"):
					pick = o
					break
				if en.begins_with("Steel"):
					pick = o
		d.choose(pick["index"])
		if args.has("verbose"):
			print("  대화 %s: %s" % [npc.name, d.node_id])


func _level_all(w: Dictionary) -> void:
	for p: Node in w["party"]:
		while Progression.level_up(w, p):
			pass


func _nearest_enemy(w: Dictionary, c: Node, zone: String) -> Node:
	var grid: Node = w["grid"]
	var best: Node = null
	for o: Node in grid.creatures():
		if o.dead or o.team != "enemy" or not zone in grid.zones(grid.cell_of(o)):
			continue
		if best == null or grid.distance_between(c, o) < grid.distance_between(c, best):
			best = o
	return best
