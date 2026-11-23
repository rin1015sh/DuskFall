extends SceneTree
## 밸런스 점검 시뮬레이션(/balance-check). 같은 조우를 시드만 바꿔 여러 번 돌린다.
## 실행: godot --headless --path . -s res://tools/sim_battle.gd -- --encounter=example_1 --runs=200
##   --swap=<클래스>: 기준 파티에서 같은 역할(ai_role: melee 전사·ranged 로그·caster 위저드·healer 클레릭)의 한 명을 그 클래스 추천 빌드로 바꾼다.
##   --classes: 모든 클래스를 하나씩 바꿔 넣어 표로(승률·바꿔 넣은 캐릭터의 피해·쓰러짐).
##   --gear: 레벨에 맞는 마법 물품을 끼운다(5~: 무기·갑옷·방패 +1, 11~: 보호의 망토, 13~: 무기 +2, 15~: 갑옷·방패 +2 — SRD 등급 기준 1차 가정).
## 파티·적 모두 단순 AI(scripts/ai/simple_ai.gd). 조우 난이도는 SRD 5.2.1 XP Budget per Character.

const ENCOUNTERS := {
	"example_1": {"note": "룰북 9단계 예시 전투 1(1레벨, 고블린 전사 4)", "level": 1, "map": "test_arena",
		"foes": [["goblin_warrior", "goblin_a"], ["goblin_warrior", "goblin_b"], ["goblin_warrior", "goblin_c"], ["goblin_warrior", "goblin_d"]]},
	"example_2": {"note": "룰북 9단계 예시 전투 2(3레벨, 고블린 두목 + 고블린 전사 3)", "level": 3, "map": "test_arena",
		"foes": [["goblin_boss", "goblin_a"], ["goblin_warrior", "goblin_b"], ["goblin_warrior", "goblin_c"], ["goblin_warrior", "goblin_d"]]},
	"example_3": {"note": "룰북 9단계 예시 전투 3(5레벨, 오우거 2 + 고블린 전사 4)", "level": 5, "map": "test_arena",
		"foes": [["ogre", "goblin_a"], ["ogre", "goblin_c"], ["goblin_warrior", "goblin_b"], ["goblin_warrior", "goblin_d"],
			["goblin_warrior", "x:9,9"], ["goblin_warrior", "x:13,6"]]},
	"tier1_l7": {"note": "1구간 시험(7레벨, 와이번 + 키메라)", "level": 7, "map": "test_arena",
		"foes": [["wyvern", "goblin_a"], ["chimera", "goblin_c"]]},
	"tier1_l10": {"note": "1구간 시험(10레벨, 젊은 적룡 + 바위 거인)", "level": 10, "map": "test_arena",
		"foes": [["young_red_dragon", "goblin_a"], ["stone_giant", "goblin_c"]]},
	"tier2_l13": {"note": "2구간 시험(13레벨, 뿔 악마 + 레모라즈)", "level": 13, "map": "test_arena",
		"foes": [["horned_devil", "goblin_a"], ["remorhaz", "goblin_c"]]},
	"tier2_l15": {"note": "2구간 시험(15레벨, 성룡 녹룡 + 얼음 악마)", "level": 15, "map": "test_arena",
		"foes": [["adult_green_dragon", "goblin_a"], ["ice_devil", "goblin_c"]]},
	"tier3_l17": {"note": "3구간 시험(17레벨, 성룡 청룡 + 강철 골렘)", "level": 17, "map": "test_arena",
		"foes": [["adult_blue_dragon", "goblin_a"], ["iron_golem", "goblin_c"]]},
	"tier3_l20": {"note": "3구간 시험(20레벨, 구덩이 악마 + 발로르)", "level": 20, "map": "test_arena",
		"foes": [["pit_fiend", "goblin_a"], ["balor", "goblin_c"]]},
	"hill_path": {"note": "시범 맵 hill_path(1레벨, 고원 궁수 2·둔덕 1·지면 1 고블린 전사 + 동굴 입구 고블린 두목)", "level": 1, "map": "hill_path", "zone": "hill",
		"foes": [["goblin_warrior", "hill_archer_a"], ["goblin_warrior", "hill_archer_b"], ["goblin_warrior", "mound_goblin"],
			["goblin_boss", "cave_guard"], ["goblin_warrior", "path_goblin"]]},
}
## SRD XP Budget per Character(낮음·보통·높음)
const BUDGET := {1: [50, 75, 100], 2: [100, 150, 200], 3: [150, 225, 400], 4: [250, 375, 500], 5: [500, 750, 1100],
	6: [600, 1000, 1400], 7: [750, 1300, 1700], 8: [1000, 1700, 2100], 9: [1300, 2000, 2600], 10: [1600, 2300, 3100],
	11: [1900, 2900, 4100], 12: [2200, 3700, 4700], 13: [2600, 4200, 5400], 14: [2900, 4900, 6200], 15: [3300, 5400, 7800],
	16: [3800, 6100, 9800], 17: [4500, 7200, 11700], 18: [5000, 8700, 14200], 19: [5500, 10700, 17200], 20: [6400, 13200, 22000]}

var _done := false
var _gear := false


## 레벨에 맞는 마법 물품(--gear): 칸의 무기·갑옷·방패를 +N 변형으로, 11레벨부터 보호의 망토.
static func gear_up(c: Node, lv: int) -> void:
	if lv < 5 or not c.has_meta("spec"):
		return
	var Builder: Variant = load("res://scripts/rules/character_builder.gd")
	var spec: Dictionary = c.get_meta("spec").duplicate(true)
	var slots: Dictionary = c.equipment.duplicate()
	for k: String in slots:
		var id := str(slots[k])
		if id == "" or id.contains("_plus_"):
			continue
		var is_armor: bool = k == "armor" or id == "shield"
		var n := (2 if lv >= 15 else 1) if is_armor else (2 if lv >= 13 else 1)
		if Engine.get_main_loop().root.get_node("RulesDB").has_entry("item", "%s_plus_%d" % [id, n]):
			slots[k] = "%s_plus_%d" % [id, n]
	if lv >= 11 and str(slots.get("cloak", "")) == "":
		slots["cloak"] = "cloak_of_protection"
	spec["equipment"] = slots
	for k: String in ["armor", "shield", "weapons"]:
		spec.erase(k)
	Builder.reapply(c, spec)


func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	var args := {}
	for a: String in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	_gear = args.has("gear")
	var ids: Array = [args.get("encounter", "")] if args.has("encounter") else ENCOUNTERS.keys()
	for id: String in ids:
		if args.has("classes"):
			class_table(id, int(args.get("runs", "100")))
		else:
			report(id, int(args.get("runs", "200")), str(args.get("swap", "")))
	quit()
	return true


## 모든 클래스를 하나씩 바꿔 넣어 비교한다.
func class_table(id: String, runs: int) -> void:
	var enc: Dictionary = ENCOUNTERS[id]
	print("== %s: %s — 클래스 비교(%d회씩)" % [id, enc["note"], runs])
	print("   | 클래스 | 바꾼 자리 | 승률 | 라운드 | 파티 쓰러짐 | 사망 | 그 캐릭터 피해/전투 | 그 캐릭터 쓰러짐 |")
	for cid: String in root.get_node("RulesDB").ids("class"):
		var st := {"wins": 0, "rounds": 0, "downs": 0, "deaths": 0, "dmg": 0, "self_downs": 0, "slot": ""}
		for s in runs:
			root.get_node("Dice").set_seed(1000 + s)
			var r := run_once(enc, cid)
			st["wins"] += 1 if r["win"] else 0
			st["rounds"] += r["rounds"]
			st["downs"] += r["downs"]
			st["deaths"] += r["deaths"]
			st["dmg"] += r["swap_damage"]
			st["self_downs"] += r["swap_downs"]
			st["slot"] = r["swap_slot"]
		print("   | %s | %s | %.0f%% | %.1f | %.2f | %.2f | %.1f | %.2f |" % [cid, st["slot"], 100.0 * st["wins"] / runs, float(st["rounds"]) / runs,
			float(st["downs"]) / runs, float(st["deaths"]) / runs, float(st["dmg"]) / runs, float(st["self_downs"]) / runs])


func report(id: String, runs: int, swap: String = "") -> void:
	var enc: Dictionary = ENCOUNTERS[id]
	var Dice: Node = root.get_node("Dice")
	var stats := {"wins": 0, "rounds": 0, "downs": 0, "deaths": 0, "slots": 0, "potions": 0}
	var xp := 0
	for f: Array in enc["foes"]:
		xp += int(root.get_node("RulesDB").get_entry("monster", f[0])["xp"])
	for s in runs:
		Dice.set_seed(1000 + s)
		var r := run_once(enc, swap)
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


const ROLE_SLOT := {"melee": "fighter", "ranged": "rogue", "caster": "wizard", "healer": "cleric"}


func run_once(enc: Dictionary, swap: String = "") -> Dictionary:
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
	var swapped: Node = null
	var slot_class := ""
	if swap != "":
		var cls: Dictionary = root.get_node("RulesDB").get_entry("class", swap)
		slot_class = str(ROLE_SLOT.get(str(cls.get("ai_role", "melee")), "fighter"))
		for i in b["party"].size():
			var old: Node = b["party"][i]
			if old.class_id == slot_class:
				var Builder: Variant = load("res://scripts/rules/character_builder.gd")
				var nc: Node = Builder.build(Builder.default_spec(swap, enc["level"]))["creature"]
				nc.name = old.name
				nc.inventory = old.inventory.duplicate()
				var at: Vector2i = grid.cell_of(old)
				grid.remove(old)
				old.free()
				grid.place(nc, at)
				b["party"][i] = nc
				w["party"] = b["party"]
				swapped = nc
				break
	if _gear:
		for pc: Node in b["party"]:
			gear_up(pc, int(enc["level"]))
	var dealt := {"n": 0, "downs": 0}
	var on_dmg := func(info: Dictionary) -> void:
		var a: Variant = info.get("opts", {}).get("attacker")
		if swapped != null and a == swapped and info["target"].team != "party":
			dealt["n"] += int(info.get("amount", 0))
	root.get_node("EventBus").on_damage_taken.connect(on_dmg)
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
			if info["creature"] == swapped:
				dealt["downs"] += 1
	root.get_node("EventBus").on_hp_zero.connect(on_zero)
	var tm: Node = w["turns"]
	tm.start_combat(enc.get("zone", "arena"))
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
	root.get_node("EventBus").on_damage_taken.disconnect(on_dmg)
	var slots_after := 0
	for c: Node in b["party"]:
		for k: String in c.resources.keys():
			if k.begins_with("spell_slot"):
				slots_after += int(c.resources[k]["current"])
	var out := {"win": tm.result == "victory", "rounds": tm.round_number, "downs": downs["n"],
		"deaths": b["party"].filter(func(c: Node) -> bool: return c.dead).size(), "slots": slots_before - slots_after,
		"swap_damage": dealt["n"], "swap_downs": dealt["downs"], "swap_slot": slot_class}
	var Sp: Variant = load("res://scripts/rules/spellcasting.gd")
	for id: Variant in Sp.instances.keys():
		Sp.end_instance(id)
	Sp.instances.clear()
	for n: Node in [w["grid"], w["surfaces"], w["reactions"], w["turns"]] + b["party"] + foes:
		if is_instance_valid(n):
			n.free()
	return out
