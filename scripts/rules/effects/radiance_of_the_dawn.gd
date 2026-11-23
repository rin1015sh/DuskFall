extends "res://scripts/rules/effect_script.gd"
## 새벽의 광휘(빛 영역 2레벨, BG3): 행동 + 신성 변환. 6칸(9m) 안 적 건강 내성 — 실패 2d10 + 캐릭터 레벨 광휘, 성공 절반.
## 그 안의 마법 어둠(구름)을 걷어 낸다.
const Resolver := preload("res://scripts/rules/resolver.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var w: Dictionary = ctx["world"]
	var grid: Node = w["grid"]
	var targets: Array = grid.creatures().filter(func(o: Node) -> bool:
		return not o.dead and c.is_hostile_to(o) and grid.distance_between(c, o) <= 6)
	var dice := "2d10+%d" % c.level
	Resolver.save_effect(targets, {"ability": "con", "dc": Spellcasting.spell_dc(c)},
		[{"type": "damage", "dice": dice, "damage_type": "radiant"}], [{"type": "damage", "dice": dice, "damage_type": "radiant", "scale": 0.5}],
		{"source": c, "magic": true})
	if w.get("surfaces") != null and w["surfaces"].has_method("clear_clouds_near"):
		w["surfaces"].clear_clouds_near(grid.cell_of(c), 6, "darkness")
	if w.get("turns") != null:
		w["turns"].notify_hostile_action(c)
	return {"ok": true, "targets": targets.size()}
