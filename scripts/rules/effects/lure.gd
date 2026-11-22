extends "res://scripts/rules/effect_script.gd"
## Minor Illusion·Silent Image·Major Image(환영): 조준 칸에 환영. 근처 적(12칸, 시야선)이 그쪽을 돌아보고 의심 없이 시선을 빼앗긴다(미끼). Silent·Major Image는 시야를 가리는 환영(3×3·4×4)도 세운다. 조사(지능) 판정으로 간파하는 AI는 1차 생략.

const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var g := U.grid(ctx)
	var cell := U.aim_cell(ctx)
	var sid: String = ctx["spell"]["id"]
	var c: Node = ctx["self"]
	var lured := 0
	for o: Node in g.creatures():
		if o.dead or not o.is_hostile_to(c) or g.distance(g.cell_of(o), cell) > 12 or not g.has_line_of_sight(g.cell_of(o), cell):
			continue
		var d: Vector2i = cell - g.cell_of(o)
		if d != Vector2i.ZERO:
			o.facing = Vector2i(signi(d.x), signi(d.y))
		o.set_meta("lured_to", cell)
		lured += 1
	if sid != "minor_illusion":
		var r := 1 if sid == "silent_image" else 2
		var key := "spell_%d" % ctx["instance"]["id"]
		for dy in range(-r + (1 if r == 2 else 0), r + 1):
			for dx in range(-r + (1 if r == 2 else 0), r + 1):
				var cc := cell + Vector2i(dx, dy)
				if g.in_bounds(cc) and not g.has_flag(cc, "wall") and g.cloud(cc) == null:
					g.set_cloud(cc, {"id": "illusory_image", "turns_left": -1, "source": key, "dc": U.dc(ctx)})
	U.entity(ctx, "illusion", cell)
	return {"ok": true, "lured": lured}
