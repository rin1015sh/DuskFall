extends "res://scripts/rules/effect_script.gd"
## Gust of Wind(2레벨, BG3 수치): 조준 방향으로 길이 8칸(12m)·폭 2칸 선, 즉시. 근력 내성 실패 → 3칸(5m) 밀려나고 균형 잃음 2턴,
## 선 안 구름이 흩어지고 불 표면이 꺼진다.

const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var g := U.grid(ctx)
	var c: Node = ctx["self"]
	var o: Vector2i = g.cell_of(c)
	var aim := U.aim_cell(ctx)
	var dir := Vector2(aim - o).normalized()
	if dir == Vector2.ZERO:
		return {"ok": false, "reason": "방향을 골라야 한다"}
	var side := Vector2(-dir.y, dir.x)
	var cells: Array[Vector2i] = []
	for i in range(1, 9):
		for w: float in [0.0, 1.0]:
			var p := Vector2(o) + dir * i + side * w
			var cell := Vector2i(roundi(p.x), roundi(p.y))
			if g.in_bounds(cell) and not cell in cells:
				cells.append(cell)
	for cell in cells:
		if g.cloud(cell) != null:
			g.set_cloud(cell, null)
		if g.surface_id(cell) == "fire":
			g.set_surface(cell, null)
	var pushed := 0
	for t: Node in U.creatures_in(ctx, cells):
		if t == c or t.dead:
			continue
		if not Resolver.saving_throw(t, "str", U.dc(ctx))["success"]:
			pushed += load("res://scripts/rules/combat.gd")._push_up_to(ctx["world"], c, t, 3)
			U.add_condition(ctx, t, "off_balance", 2)
	return {"ok": true, "cells": cells, "pushed": pushed}
