extends SceneTree
## 밸런스 점검 시뮬레이션(/balance-check). 같은 조우를 시드만 바꿔 여러 번 돌린다.
## 실행: godot --headless --path . -s res://tools/sim_battle.gd -- --encounter=example_1 --runs=200
## 파티·적 모두 단순 AI(scripts/ai/simple_ai.gd). 조우 난이도는 SRD 5.2.1 XP Budget per Character.

const ENCOUNTERS := {
	"example_1": {"note": "룰북 9단계 예시 전투 1(1레벨, 고블린 전사 4)", "level": 1, "map": "test_arena",
		"foes": [["goblin_warrior", "goblin_a"], ["goblin_warrior", "goblin_b"], ["goblin_warrior", "goblin_c"], ["goblin_warrior", "goblin_d"]]},
	"example_2": {"note": "룰북 9단계 예시 전투 2(3레벨, 고블린 두목 + 고블린 전사 3)", "level": 3, "map": "test_arena",
		"foes": [["goblin_boss", "goblin_a"], ["goblin_warrior", "goblin_b"], ["goblin_warrior", "goblin_c"], ["goblin_warrior", "goblin_d"]]},
	"example_3": {"note": "룰북 9단계 예시 전투 3(5레벨, 오우거 2 + 고블린 전사 4)", "level": 5, "map": "test_arena",
		"foes": [["ogre", "goblin_a"], ["ogre", "goblin_c"], ["goblin_warrior", "goblin_b"], ["goblin_warrior", "goblin_d"],
			["goblin_warrior", "x:9,9"], ["goblin_warrior", "x:13,6"]]},
}
## SRD XP Budget per Character(낮음·보통·높음)
const BUDGET := {1: [50, 75, 100], 2: [100, 150, 200], 3: [150, 225, 400], 4: [250, 375, 500], 5: [500, 750, 1100]}

var _done := false


func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	var args := {}
	for a: String in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	var ids: Array = [args.get("encounter", "")] if args.has("encounter") else ENCOUNTERS.keys()
	for id: String in ids:
		report(id, int(args.get("runs", "200")))
	quit()
	return true


func report(id: String, runs: int) -> void:
	var enc: Dictionary = ENCOUNTERS[id]
	var Dice: Node = root.get_node("Dice")
	var stats := {"wins": 0, "rounds": 0, "downs": 0, "deaths": 0, "slots": 0, "potions": 0}
	var xp := 0
	for f: Array in enc["foes"]:
		xp += int(root.get_node("RulesDB").get_entry("monster", f[0])["xp"])
	for s in runs:
		Dice.set_seed(1000 + s)
		var r := run_once(enc)
		stats["wins"] += 1 if r["win"] else 0
		stats["rounds"] += r["rounds"]
		stats["downs"] += r["downs"]
		stats["deaths"] += r["deaths"]
		stats["slots"] += r["slots"]
	var b: Array = BUDGET[enc["level"]]
	var diff := "낮음 미만"
	if xp >= b[2] * 4:
		diff = "높음 이상"
	elif xp >= b[1] * 4:
		diff = "보통~높음"
	elif xp >= b[0] * 4:
		diff = "낮음~보통"
	print("== %s: %s" % [id, enc["note"]])
	print("   XP %d (파티 4명 예산 낮음 %d / 보통 %d / 높음 %d) → %s" % [xp, b[0] * 4, b[1] * 4, b[2] * 4, diff])
	print("   %d회: 승률 %.0f%%, 평균 %.1f라운드, 쓰러짐 %.2f회/전투, 사망 %.2f명/전투, 주문 슬롯 %.1f개/전투" % [
		runs, 100.0 * stats["wins"] / runs, float(stats["rounds"]) / runs, float(stats["downs"]) / runs,
		float(stats["deaths"]) / runs, float(stats["slots"]) / runs])


func run_once(enc: Dictionary) -> Dictionary:
	var Roster: Variant = load("res://scenes/battle/test_roster.gd")
	var MF: Variant = load("res://scripts/rules/monster_factory.gd")
	var AI: Variant = load("res://scripts/ai/simple_ai.gd")
	var b: Dictionary = Roster.build(enc["map"], enc["level"])
	var w: Dictionary = b["world"]
	var grid: Node = w["grid"]
	var spawns := {}
	for f: Node in b["foes"]:
		spawns[str(f.name)] = grid.cell_of(f)
		grid.remove(f)
		f.free()
	var foes: Array = []
	for f: Array in enc["foes"]:
		var m: Node = MF.spawn(f[0])
		var cell: Vector2i = spawns.get(f[1], Vector2i.ZERO)
		if str(f[1]).begins_with("x:"):
			var p: PackedStringArray = str(f[1]).trim_prefix("x:").split(",")
			cell = Vector2i(int(p[0]), int(p[1]))
		grid.place(m, cell, int(m.get_meta("cells", 1)))
		foes.append(m)
	var slots_before := 0
	for c: Node in b["party"]:
		for k: String in c.resources.keys():
			if k.begins_with("spell_slot"):
				slots_before += int(c.resources[k]["current"])
	var downs := {"n": 0}
	var on_zero := func(info: Dictionary) -> void:
		if info["creature"].team == "party":
			downs["n"] += 1
	root.get_node("EventBus").on_hp_zero.connect(on_zero)
	var tm: Node = w["turns"]
	tm.start_combat("arena")
	var steps := 0
	while tm.in_combat and steps < 600:
		steps += 1
		var g: Array = tm.current_group()
		if g.is_empty():
			break
		AI.take_turn(w, g[0])
		if tm.in_combat:
			tm.end_turn(g[0])
	root.get_node("EventBus").on_hp_zero.disconnect(on_zero)
	var slots_after := 0
	for c: Node in b["party"]:
		for k: String in c.resources.keys():
			if k.begins_with("spell_slot"):
				slots_after += int(c.resources[k]["current"])
	var out := {"win": tm.result == "victory", "rounds": tm.round_number, "downs": downs["n"],
		"deaths": b["party"].filter(func(c: Node) -> bool: return c.dead).size(), "slots": slots_before - slots_after}
	var Sp: Variant = load("res://scripts/rules/spellcasting.gd")
	for id: Variant in Sp.instances.keys():
		Sp.end_instance(id)
	Sp.instances.clear()
	for n: Node in [w["grid"], w["surfaces"], w["reactions"], w["turns"]] + b["party"] + foes:
		if is_instance_valid(n):
			n.free()
	return out
