extends "res://scripts/rules/effect_script.gd"
## 휴식의 노래(바드 2레벨, BG3): 행동, 긴 휴식 1회. 전투 밖에서 파티가 짧은 휴식을 한 것처럼 회복 — 짧은 휴식 횟수는 쓰지 않는다.
const Rest := preload("res://scripts/rules/rest.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var w: Dictionary = ctx["world"]
	var party: Array = w.get("party", [ctx["self"]])
	if party.is_empty():
		party = [ctx["self"]]
	w["short_rests_left"] = int(w.get("short_rests_left", Rest.SHORT_RESTS)) + 1
	var r: Dictionary = Rest.short_rest(w, party)
	if not r.get("ok", false):
		w["short_rests_left"] = int(w["short_rests_left"]) - 1
	return r
