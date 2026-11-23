extends "res://scripts/rules/effect_script.gd"
## 급소 공격(로그 1레벨, SRD): 턴당 1회. 교묘·원거리 무기로 명중했고, 유리이거나
## 대상 인접 8칸에 무력화되지 않은 아군이 있고 불리가 없을 때. 조건이 맞는 첫 명중에 자동(룰북 6단계).
## 교활한 일격(5레벨): turn["cunning_strike"]에 고른 효과가 있으면 주사위 1개를 쓴다.

const COST := 1
## 효과별 주사위 비용(SRD): 기본 1d6, 교묘한 일격(14레벨) 현혹 2d6·기절시키기 6d6·시야 가리기 3d6
const COSTS := {"poison": 1, "trip": 1, "withdraw": 1, "daze": 2, "knock_out": 6, "obscure": 3}


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var res: Dictionary = ctx["res"]
	if res.get("attacker") != c or c.turn.get("sneak_used", false):
		return {"ok": false}
	# 수동 설정(BG3식)이면 '급소 공격' 행동으로 한 공격에만
	if c.options.get("sneak_attack", "auto") == "manual" and not c.turn.get("sneak_armed", false):
		return {"ok": false}
	var atk: Dictionary = res["attack"]
	var props: Array = atk.get("properties", [])
	if not atk.get("weapon", false) or not ("finesse" in props or atk.get("kind", "") == "ranged"):
		return {"ok": false}
	var mode: int = res.get("mode", 0)
	var ok := mode > 0
	if not ok and mode == 0:
		ok = _ally_adjacent(c, res["target"])
	if not ok:
		return {"ok": false}
	var count := _dice_count(c)
	var option: String = c.turn.get("cunning_strike", c.options.get("cunning_strike", ""))
	if option != "" and c.has_cap("cunning_strike") and count > int(COSTS.get(option, COST)):
		count -= int(COSTS.get(option, COST))
		res["cunning_strike"] = option
	var option2 := str(c.options.get("improved_cunning_strike", ""))
	if option2 != "" and option2 != option and c.has_cap("improved_cunning_strike") and count > int(COSTS.get(option2, COST)):
		count -= int(COSTS.get(option2, COST))  # 향상된 교활한 일격(11레벨): 두 번째 효과도 비용을 낸다
		res["cunning_strike_2"] = option2
	# 최상급 은신(도둑 9레벨): 숨은 채 공격했으면 주사위 1개를 더 써서 숨기를 유지한다(resolver가 res.stealth_attack을 본다)
	var hide: Dictionary = c.condition_instance("invisible")
	if c.has_cap("stealth_attack") and str(c.options.get("supreme_sneak", "on")) == "on" and count > COST \
			and not hide.is_empty() and hide["source"] is String and hide["source"] == "hide":
		count -= COST
		res["stealth_attack"] = true
	c.turn["sneak_used"] = true
	if not res.has("extra_damage"):
		res["extra_damage"] = []
	res["extra_damage"].append({"dice": "%dd6" % count, "damage_type": atk["damage"][0]["damage_type"]})
	res["sneak_attack"] = count
	return {"ok": true}


func _dice_count(c: Node) -> int:
	var table: Dictionary = c.feature_data.get("sneak_attack", {}).get("dice_by_level", {"1": "1d6"})
	var best := "1d6"
	var best_lv := 0
	for lv: String in table.keys():
		if c.feature_level("sneak_attack") >= int(lv) and int(lv) > best_lv:
			best_lv = int(lv)
			best = table[lv]
	return int(best.get_slice("d", 0))


## 대상 인접 8칸의 무력화되지 않은 아군(격자 없이는 판정 정보의 ally_adjacent를 쓴다).
func _ally_adjacent(c: Node, target: Node) -> bool:
	var rq: Node = EventBus.reaction_queue
	if rq == null or not is_instance_valid(rq) or not rq.world.has("grid"):
		return false
	var grid: Node = rq.world["grid"]
	for o: Node in grid.creatures():
		if o != c and o != target and not o.dead and not o.is_hostile_to(c) and o.team == c.team \
				and not o.is_incapacitated() and grid.distance_between(o, target) <= 1:
			return true
	return false
