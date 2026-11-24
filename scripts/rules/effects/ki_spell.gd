extends "res://scripts/rules/effect_script.gd"
## 기 주문(몽크 그림자 기술·4원소 수련, BG3): 기능 spell을 슬롯 없이 지혜로 시전한다(DC 8 + 숙련 + 지혜). 기 비용은 기능 resource_amount.
## 기능 slot = 시전 레벨(없으면 주문 레벨), upcast_cap = 그 능력 태그가 있으면 한 레벨 높여(향상된 원소 시전).
func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var f: Dictionary = ctx.get("feature", {})
	var w: Dictionary = ctx["world"]
	var sid := str(f.get("spell", ""))
	var sp := RulesDB.get_entry("spell", sid)
	if sp.is_empty():
		return {"ok": false, "reason": "주문이 없다"}
	var slot := int(f.get("slot", sp.get("level", 0)))
	if str(f.get("upcast_cap", "")) != "" and c.has_cap(str(f["upcast_cap"])) and slot > 0:
		slot += 1
	var t: Variant = ctx.get("target")
	var aim: Vector2i = t if t is Vector2i else (w["grid"].cell_of(t) if t is Node and w.has("grid") else (w["grid"].cell_of(c) if w.has("grid") else Vector2i.ZERO))
	var opts := {"free": true, "granted": true, "ability": "wis", "slot": slot}
	opts.merge(ctx.get("opts", {}), false)
	return load("res://scripts/rules/spellcasting.gd").cast(w, c, sid, aim, opts)
