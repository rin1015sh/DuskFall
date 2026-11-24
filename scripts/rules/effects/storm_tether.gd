extends "res://scripts/rules/effect_script.gd"
## 번개 올가미(자체 이름, BG3 수치): 3칸(4.5m) 안 생물 하나 근력 내성. 실패 → 시전자 쪽으로 3칸 끌려오고, 옆 칸(1.5m)에 닿으면 1d8 번개(5레벨 2d8, 10레벨 3d8).
const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Node = U.target(ctx)
	if t == null or t == c:
		return {"ok": false, "reason": "대상이 없다"}
	if Resolver.saving_throw(t, "str", U.dc(ctx), {"source": c})["success"]:
		return {"ok": true, "pulled": 0}
	var g := U.grid(ctx)
	var moved := U.pull(ctx, t, g.cell_of(c), 3)
	if g.distance_between(c, t) <= 1:
		var n := 3 if c.level >= 10 else (2 if c.level >= 5 else 1)
		Resolver.apply_damage(t, [{"amount": Dice.roll("%dd8" % n, "번개 올가미")["total"], "damage_type": "lightning"}], {"attacker": c})
	return {"ok": true, "pulled": moved}
