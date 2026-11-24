extends "res://scripts/rules/effect_script.gd"
## 야생 마법: 무형의 정령(BG3): 효과 중 매 턴 보너스 행동, 6칸 안 칸에 정령을 불러 터뜨린다 — 3칸(4.5m) 안 생물(나 빼고)
## 민첩 내성(DC 8 + 숙련 + 건강) 실패 시 1d6 역장. [변형] 턴 끝에 터지는 대신 바로 터진다.
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	var grid: Node = ctx["world"]["grid"]
	var cell: Vector2i = t if t is Vector2i else (grid.cell_of(t) if t is Node else grid.cell_of(c))
	if grid.distance(grid.cell_of(c), cell) > 6:
		return {"ok": false, "reason": "6칸 안"}
	var dc: int = 8 + c.proficiency_bonus + c.ability_mod("con")
	var n: int = Dice.roll("1d6", "무형의 정령")["total"]
	for o: Node in grid.creatures():
		if o != c and not o.dead and grid.distance(cell, grid.cell_of(o)) <= 3:
			if not Resolver.saving_throw(o, "dex", dc, {"source": c, "magic": true})["success"]:
				Resolver.apply_damage(o, [{"amount": n, "damage_type": "force"}], {"attacker": c, "magic": true})
	return {"ok": true}
