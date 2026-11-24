extends "res://scripts/rules/effect_script.gd"
## 휘감는 덩굴(자체 이름, BG3 수치): 6칸 안 칸에 덩굴을 세운다(집중 10턴). 세울 때와 다시 쓰기(보너스 행동, 슬롯 없음) 때
## 덩굴 6칸 안 적 하나(겨눈 생물, 없으면 가장 가까운 적)가 민첩 내성 실패면 덩굴 쪽으로 4칸 끌려온다.
const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func _yank(ctx: Dictionary, vine: Vector2i, aim: Vector2i) -> Dictionary:
	var c: Node = ctx["self"]
	var g := U.grid(ctx)
	var t: Node = g.creature_at(aim)
	if t == null or not t.is_hostile_to(c) or g.distance(g.cell_of(t), vine) > 6:
		t = null
		for o: Node in g.creatures():
			if o.dead or not o.is_hostile_to(c) or g.distance(g.cell_of(o), vine) > 6:
				continue
			if t == null or g.distance(g.cell_of(o), vine) < g.distance(g.cell_of(t), vine):
				t = o
	if t == null:
		return {"ok": true, "pulled": 0}
	if Resolver.saving_throw(t, "dex", U.dc(ctx), {"source": c})["success"]:
		return {"ok": true, "pulled": 0}
	return {"ok": true, "pulled": U.pull(ctx, t, vine, 4)}


func apply(ctx: Dictionary) -> Dictionary:
	var vine := U.aim_cell(ctx)
	U.entity(ctx, "vine", vine)
	ctx["instance"]["vine"] = vine
	return _yank(ctx, vine, vine)


func recast(ctx: Dictionary) -> Dictionary:
	return _yank(ctx, ctx["instance"].get("vine", U.aim_cell(ctx)), U.aim_cell(ctx))
