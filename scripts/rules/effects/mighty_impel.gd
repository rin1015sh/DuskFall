extends "res://scripts/rules/effect_script.gd"
## 강력한 내던지기(거인 10레벨, BG3): 보너스 행동, 옆의 보통 크기 이하 생물(적·아군)을 나에게서 먼 쪽 곧은 선으로 6칸(9m)까지 던진다.
## 떨어진 생물은 무게 피해(던지기 피해 구간) + 분노 피해 두 배, 넘어짐, 높이가 낮아지면 낙하. 적이면 근력 내성(DC 8 + 숙련 + 근력)으로 버틴다.
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
	if str(t.size) in ["large", "huge", "gargantuan"]:
		return {"ok": false, "reason": "보통 크기 이하만"}
	if t.is_hostile_to(c) and Resolver.saving_throw(t, "str", 8 + c.proficiency_bonus + c.ability_mod("str"), {"source": c})["success"]:
		return {"ok": true, "thrown": false}
	var at: Vector2i = grid.cell_of(t)
	var dir := Vector2i(signi(at.x - grid.cell_of(c).x), signi(at.y - grid.cell_of(c).y))
	var cur := at
	for i in 6:
		var nxt := cur + dir
		if Physics._push_step_blocked(grid, t, cur, nxt) != "":
			break
		cur = nxt
	var drop := maxi(grid.height(at) - grid.height(cur), 0)
	if cur != at:
		grid.move_creature(t, cur)
	var dmg: int = Dice.roll(Physics.throw_damage_dice(float(t.weight_kg)), "강력한 내던지기")["total"] + 2 * Resolver.rage_bonus(c)
	Resolver.apply_damage(t, [{"amount": dmg, "damage_type": "bludgeoning"}], {"attacker": c})
	if not t.dead:
		t.apply_condition("prone", -1, c)
		if drop > 0:
			Physics.fall(t, drop)
	return {"ok": true, "thrown": true, "landing": cur}
