extends "res://scripts/rules/effect_script.gd"
## Knock(2레벨, SRD): 12칸 안 잠긴 물체 하나를 연다(Arcane Lock도). 큰 소리 — 30칸 안 적이 시전자를 의심한다(5단계).

const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var g := U.grid(ctx)
	var cell := U.aim_cell(ctx)
	var obj: Dictionary = g.object_at(cell)
	if obj.is_empty() or not obj.get("lock", {}).get("locked", false):
		return {"ok": false, "reason": "잠긴 물체가 없다"}
	obj["lock"]["locked"] = false
	if obj.has("art_open"):
		obj["art"] = obj["art_open"]
	var c: Node = ctx["self"]
	for o: Node in g.creatures():
		if not o.dead and o.is_hostile_to(c) and g.distance(g.cell_of(o), cell) <= 60 and o.awareness.get(c, {}).get("state", "") == "":
			o.awareness[c] = {"state": "suspicious", "last": cell}
	Dice.log_text("쾅! 자물쇠가 열렸다")
	return {"ok": true}
