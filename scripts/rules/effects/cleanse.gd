extends "res://scripts/rules/effect_script.gd"
## Lesser Restoration(SRD): 실명·마비·중독 중 하나를 끝낸다(귀먹음은 삭제된 상태). 고를 수 있으면 opts.choice.
## Remove Curse: 저주(bestow_curse 등 저주 표지)를 끝낸다.
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Area := preload("res://scripts/rules/area.gd")


func is_implemented() -> bool:
	return true


const LESSER := ["paralyzed", "poisoned", "blinded"]
const GREATER := ["charmed", "petrified"]


func apply(ctx: Dictionary) -> Dictionary:
	var t: Node = ctx["world"]["grid"].creature_at(ctx["aim"])
	if t == null:
		return {"ok": false, "reason": "대상이 없다"}
	if ctx["spell"]["id"] == "remove_curse":
		for cond in t.conditions.duplicate():
			if cond.get("params", {}).get("curse", false):
				t.remove_condition(cond["id"])
		return {"ok": true}
	var pick: String = ctx["opts"].get("choice", "")
	var order: Array = LESSER
	if ctx["spell"]["id"] == "greater_restoration":
		order = GREATER  # 상급 회복: 매혹·석화·저주(탈진·능력치·최대 HP 감소 규칙은 없음)
		for cond in t.conditions.duplicate():
			if cond.get("params", {}).get("curse", false) and pick == "":
				t.remove_condition(cond["id"])
				return {"ok": true, "removed": cond["id"]}
	for id: String in ([pick] if pick != "" else order):
		if t.has_condition(id):
			t.remove_condition(id)
			return {"ok": true, "removed": id}
	return {"ok": true, "removed": ""}
