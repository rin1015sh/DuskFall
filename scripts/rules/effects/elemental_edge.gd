extends "res://scripts/rules/effect_script.gd"
## 원소 무기화(자체 이름, BG3 수치): 12칸 아군 하나의 무기 — 집중 동안 무기 명중 +1, 무기 명중마다 1d4 원소 피해(opts.choice: fire·cold·lightning·acid·thunder, 기본 화염).
## 5·6레벨 슬롯이면 2d4(명중 +2는 1차 생략 — 수정치가 하나다).
const U := preload("res://scripts/rules/spell_util.gd")

const TYPES := ["fire", "cold", "lightning", "acid", "thunder"]


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Node = U.target(ctx)
	if t == null:
		t = c
	if t.is_hostile_to(c):
		return {"ok": false, "reason": "아군 무기에만"}
	var kind := str(ctx["opts"].get("choice", "fire"))
	if not kind in TYPES:
		kind = "fire"
	U.add_condition(ctx, t, "elemental_edge_" + kind, 0, {"hit_dice": "2d4" if int(ctx["slot"]) >= 5 else "1d4"})
	return {"ok": true, "type": kind}
