extends "res://scripts/rules/effect_script.gd"
## 거인의 발길질(거인 5레벨, BG3): 보너스 행동, 옆의 적을 걷어찬다 — 비무장 피해(1 + 근력 타격), 밀치기 무게 한계 두 배로
## 밀어낸다(내성 — 밀치기와 같다).
const Physics := preload("res://scripts/rules/physics.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	var grid: Node = ctx["world"]["grid"]
	if not (t is Node) or t.dead or t == c or grid.distance_between(c, t) > 1:
		return {"ok": false, "reason": "옆의 생물을 골라야 한다"}
	Resolver.apply_damage(t, [{"amount": maxi(1 + c.ability_mod("str"), 1), "damage_type": "bludgeoning"}], {"attacker": c})
	if t.dead:
		return {"ok": true}
	var r := Physics.shove(grid, c, t, false, 2.0)
	r["ok"] = true
	return r
