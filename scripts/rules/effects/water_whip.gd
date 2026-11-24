extends "res://scripts/rules/effect_script.gd"
## 물 채찍(4원소, BG3): 행동 + 기 2, 6칸 안 대상 민첩 내성(DC 8 + 숙련 + 지혜) — 실패 3d10 타격(향상 4d10)에 설정 water_whip
## pull(6칸까지 끌어옴, 기본) 또는 prone(넘어짐). 성공 절반.
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	var w: Dictionary = ctx["world"]
	var grid: Node = w["grid"]
	if not (t is Node) or t.dead or t == c:
		return {"ok": false, "reason": "대상을 골라야 한다"}
	if grid.distance_between(c, t) > 6:
		return {"ok": false, "reason": "6칸 안"}
	var dice := "4d10" if c.has_cap("improved_elemental_casting") else "3d10"
	var n: int = Dice.roll(dice, "물 채찍")["total"]
	var ok: bool = Resolver.saving_throw(t, "dex", 8 + c.proficiency_bonus + c.ability_mod("wis"), {"source": c, "magic": true})["success"]
	Resolver.apply_damage(t, [{"amount": n / 2 if ok else n, "damage_type": "bludgeoning"}], {"attacker": c, "magic": true})
	if ok or t.dead:
		return {"ok": true, "saved": ok}
	if str(c.options.get("water_whip", "pull")) == "prone":
		t.apply_condition("prone", -1, c)
		return {"ok": true, "saved": false}
	var me: Vector2i = grid.cell_of(c)
	var cur: Vector2i = grid.cell_of(t)
	while grid.distance(cur, me) > 1:
		var nxt := cur + Vector2i(signi(me.x - cur.x), signi(me.y - cur.y))
		if grid.creature_at(nxt) != null or grid.blocks_movement(nxt):
			break
		cur = nxt
	if cur != grid.cell_of(t):
		grid.move_creature(t, cur)
	return {"ok": true, "saved": false}
