extends "res://scripts/rules/effect_script.gd"
## 마법의 샘 — 마법 점수로 슬롯 만들기(소서러 2레벨, SRD): 보너스 행동. 1레벨 2점(2레벨~), 2레벨 3점(3레벨~), 3레벨 5점(5레벨~).
## opts.level이 없으면 낼 수 있는 가장 높은 슬롯. 만든 슬롯은 최대치를 넘을 수 있고 긴 휴식에 사라진다(긴 휴식이 최대치로 되돌린다).

const COST := {1: [2, 2], 2: [3, 3], 3: [5, 5], 4: [6, 7], 5: [7, 9]}  # 슬롯 레벨: [점수, 최소 소서러 레벨]


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var points: int = c.resource("sorcery_points")
	var want := int(ctx.get("opts", {}).get("level", 0))
	var pick := 0
	for lv: int in COST:
		if c.level >= COST[lv][1] and points >= COST[lv][0] and (want == 0 or lv == want):
			pick = maxi(pick, lv)
	if pick == 0:
		return {"ok": false, "reason": "마법 점수가 모자라다"}
	c.resources["sorcery_points"]["current"] = points - int(COST[pick][0])
	var id := "spell_slot_%d" % pick
	if not c.resources.has(id):
		c.resources[id] = {"current": 0, "max": 0, "recharge": "long"}
	c.resources[id]["current"] = int(c.resources[id]["current"]) + 1
	Dice.log_text("%s: 마법 점수 %d → %d레벨 슬롯" % [c.label(), COST[pick][0], pick])
	return {"ok": true, "level": pick}
