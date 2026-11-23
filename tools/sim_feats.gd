extends SceneTree
## 재주 밸런스 점검(/balance-check — 공격 단위). 강타·저격수(−5/+10)를 켠 전사와 끈 전사가
## 대표 몬스터 AC에 공격 행동 한 번(추가 공격 포함)으로 내는 평균 피해·명중률을 비교한다.
## 실행: godot --headless --path . -s res://tools/sim_feats.gd -- --runs=3000
## 파티 전투 시뮬레이션(sim_battle)은 AI가 재주 설정을 켜지 않아 이 비교에 맞지 않는다.

# 규칙 스크립트는 오토로드가 붙은 뒤에 불러온다(미리 불러오면 RulesDB를 못 찾는다)
var Builder: Variant
var Combat: Variant
var GridWorld: Variant
var SurfaceSystem: Variant
var MF: Variant

## 레벨 → 대표 적(보통 AC·높은 AC)
const FOES := {4: ["ogre", "bugbear_warrior"], 8: ["troll", "young_white_dragon"], 12: ["frost_giant", "horned_devil"]}

var _done := false


func _process(_d: float) -> bool:
	if _done:
		return false
	_done = true
	Builder = load("res://scripts/rules/character_builder.gd")
	Combat = load("res://scripts/rules/combat.gd")
	GridWorld = load("res://scripts/rules/grid_world.gd")
	SurfaceSystem = load("res://scripts/rules/surface_system.gd")
	MF = load("res://scripts/rules/monster_factory.gd")
	var runs := 3000
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--runs="):
			runs = int(a.get_slice("=", 1))
	print("| 레벨 | 재주 | 무기 | 적(AC) | 명중률 끔 → 켬 | 공격 행동 평균 피해 끔 → 켬 | 차이 |")
	print("| --- | --- | --- | --- | --- | --- | --- |")
	for lv: int in [4, 8, 12]:
		for kind: String in ["gwm", "ss"]:
			for foe_id: String in FOES[lv]:
				var off := _run(lv, kind, foe_id, false, runs)
				var on := _run(lv, kind, foe_id, true, runs)
				var ac := int(root.get_node("RulesDB").get_entry("monster", foe_id)["ac"])
				print("| %d | %s | %s | %s(%d) | %.0f%% → %.0f%% | %.1f → %.1f | %+.1f |" % [lv, "대형 무기 강타" if kind == "gwm" else "저격수",
					"그레이트소드" if kind == "gwm" else "롱보우", foe_id, ac, off["hit"] * 100, on["hit"] * 100, off["dmg"], on["dmg"], on["dmg"] - off["dmg"]])
	quit(0)
	return false


## 4레벨 재주, 나머지 능력치 향상은 주 능력치(+2). 공격 행동 한 번(추가 공격 포함)의 평균 피해.
func _run(lv: int, kind: String, foe_id: String, toggle: bool, runs: int) -> Dictionary:
	var spec: Dictionary = Builder.default_spec("fighter", lv)
	var main := "str" if kind == "gwm" else "dex"
	spec["scores"] = {"str": 15, "dex": 15, "con": 14, "int": 8, "wis": 10, "cha": 8} if kind == "ss" else {"str": 15, "dex": 13, "con": 14, "int": 8, "wis": 12, "cha": 10}
	spec["bonus"] = {main: 2, "con": 1}
	spec["fighting_style"] = "great_weapon_fighting" if kind == "gwm" else "archery"
	spec["additional_fighting_style"] = "defense"
	spec["shield"] = false
	spec["weapons"] = {"melee": {"main": "greatsword", "off": ""}, "ranged": {"main": "longbow"}}
	var asi := {"4": {"feat": "great_weapon_master" if kind == "gwm" else "sharpshooter"}}
	for k in [6, 8, 12]:
		if lv >= k:
			asi[str(k)] = {main: 2}
	spec["asi"] = asi
	var r: Dictionary = Builder.build(spec)
	var c: Node = r["creature"]
	c.options["great_weapon_master" if kind == "gwm" else "sharpshooter"] = "on" if toggle else "off"
	var g: Node = GridWorld.new().setup_from_rows([".............", "............."], "stone")
	var w: Dictionary = {"grid": g, "surfaces": SurfaceSystem.new().setup(g)}
	var foe: Node = MF.spawn(foe_id, "enemy")
	g.place(c, Vector2i(0, 0))
	g.place(foe, Vector2i(1, 0) if kind == "gwm" else Vector2i(6, 0))
	var total := 0
	var hits := 0
	var swings := 0
	var dice: Node = root.get_node("Dice")
	for i in runs:
		dice.roll_log.clear()  # 굴림 기록이 쌓이면 느려진다
		foe.hp = 9999
		foe.hp_max = 9999
		c.reset_turn()
		c.active_set = "melee" if kind == "gwm" else "ranged"
		for k in c.attacks_per_action:
			var hp0: int = foe.hp
			var res: Dictionary = Combat.attack(w, c, foe, {} if kind == "gwm" else {"weapon": "longbow"})
			swings += 1
			if res.get("hit", false):
				hits += 1
			total += hp0 - foe.hp
	foe.free()
	c.free()
	g.free()
	return {"hit": float(hits) / swings, "dmg": float(total) / runs}
