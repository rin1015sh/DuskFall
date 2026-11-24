extends "res://scripts/rules/effect_script.gd"
## 호랑이의 피의 갈망(호랑이의 심장, BG3): 행동, 1칸 안 적 3명까지(대상 쪽부터) 무기 공격 — 무기 피해 절반(수정치 그대로), 맞으면 출혈.
const Combat := preload("res://scripts/rules/combat.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	var w: Dictionary = ctx["world"]
	var grid: Node = w["grid"]
	if not (t is Node) or t.dead or not t.is_hostile_to(c) or grid.distance_between(c, t) > 1:
		return {"ok": false, "reason": "옆의 적을 골라야 한다"}
	var foes: Array = [t]
	for o: Node in grid.creatures():
		if foes.size() >= 3:
			break
		if o != t and o != c and not o.dead and o.is_hostile_to(c) and grid.distance_between(c, o) <= 1 \
				and grid.distance_between(o, t) <= 1:
			foes.append(o)
	if c.active_set != "melee":
		Combat.switch_weapon_set(c)
	var hits := 0
	for o: Node in foes:
		var atk := Combat.build_weapon_attack(c, c.weapon("main"))
		atk["name"] = "피의 갈망"
		atk["half_damage"] = true  # 쪼개기와 같은 절반 피해(Resolver)
		var r := Combat._do_attack(w, c, o, atk)
		if r.get("hit", false) and not o.dead:
			hits += 1
			o.apply_condition("bleeding", 0, c)
	return {"ok": true, "hits": hits}
