extends "res://scripts/rules/effect_script.gd"
## Silence(2레벨, SRD): 반경 4칸 '침묵' 칸 — 음성 구성 요소 주문 시전 불가(천둥 면역·귀먹음은 1차 생략).

const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var g := U.grid(ctx)
	var cells := U.circle(ctx, U.aim_cell(ctx), 4)
	for cell in cells:
		g.set_flag(cell, "silence")
	U.entity(ctx, "silence", U.aim_cell(ctx))
	U.on_end(ctx, func() -> void:
		for cell in cells:
			g.set_flag(cell, "silence", false))
	return {"ok": true, "cells": cells.size()}
