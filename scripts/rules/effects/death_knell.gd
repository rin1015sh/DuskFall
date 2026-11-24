extends "res://scripts/rules/effect_script.gd"
## 조종(자체 이름, BG3 수치): 12칸 생물 하나 지혜 내성. 실패 → 1d12 사령, 대상 HP가 가득이면 1d8(5레벨 2배, 10레벨 3배). 성공 → 없음.
const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Node = U.target(ctx)
	if t == null or t == c:
		return {"ok": false, "reason": "대상이 없다"}
	var n := 3 if c.level >= 10 else (2 if c.level >= 5 else 1)
	var dice := "%dd%d" % [n, 8 if t.hp >= t.hp_max else 12]
	var r := Resolver.save_effect([t], {"ability": "wis", "dc": U.dc(ctx)}, [{"type": "damage", "dice": dice, "damage_type": "necrotic"}], [], {"source": c})
	return {"ok": true, "dice": dice, "result": r}
