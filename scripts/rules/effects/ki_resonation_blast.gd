extends "res://scripts/rules/effect_script.gd"
## 기 공명: 폭발(열린 손 9레벨, BG3): 기 1, 턴당 1회. 12칸 안 내가 공명시킨 생물을 터뜨린다 — 그 생물과 3칸(5m) 안 아군 아닌 생물
## 민첩 내성(DC 8 + 숙련 + 지혜) 실패 3d6 역장(성공 절반). 폭발 안의 다른 공명 생물도 연쇄로 터진다.
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	var grid: Node = ctx["world"]["grid"]
	if c.turn.get("ki_blast_used", false):
		return {"ok": false, "reason": "턴당 1회"}
	if not (t is Node) or t.dead or t.condition_instance("resonating_ki").get("source") != c:
		return {"ok": false, "reason": "내가 공명시킨 생물만"}
	if grid.distance_between(c, t) > 12:
		return {"ok": false, "reason": "12칸 안"}
	c.turn["ki_blast_used"] = true
	var dc: int = 8 + c.proficiency_bonus + c.ability_mod("wis")
	var queue: Array = [t]
	var blasts := 0
	while not queue.is_empty():
		var center: Node = queue.pop_front()
		center.remove_condition("resonating_ki")
		blasts += 1
		var n: int = Dice.roll("3d6", "기 공명 폭발")["total"]
		for o: Node in grid.creatures():
			if o.dead or (o != center and (not o.is_hostile_to(c) or grid.distance_between(center, o) > 3)):
				continue
			var ok: bool = Resolver.saving_throw(o, "dex", dc, {"source": c})["success"]
			Resolver.apply_damage(o, [{"amount": n / 2 if ok else n, "damage_type": "force"}], {"attacker": c})
			if o != center and not o.dead and o.condition_instance("resonating_ki").get("source") == c and not queue.has(o):
				queue.append(o)
	return {"ok": true, "blasts": blasts}
