extends "res://scripts/rules/effect_script.gd"
## Arcane Lock(2레벨, SRD): 닫힌 상자·문을 마법으로 잠근다 — 도둑 도구로 열 수 없고(DC +10 표시), 파티는 그대로 연다. Knock은 풀 수 있다.

const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var g := U.grid(ctx)
	var obj: Dictionary = g.object_at(U.aim_cell(ctx))
	if obj.is_empty():
		return {"ok": false, "reason": "잠글 물체가 없다"}
	var lk: Dictionary = obj.get("lock", {"dc": 15})
	lk["locked"] = true
	lk["arcane"] = true
	lk["dc"] = int(lk.get("dc", 15)) + 10
	lk["owner_team"] = ctx["self"].team
	obj["lock"] = lk
	return {"ok": true}
