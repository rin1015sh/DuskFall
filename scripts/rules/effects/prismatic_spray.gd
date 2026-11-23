extends "res://scripts/rules/effect_script.gd"
## Prismatic Spray(SRD 7레벨): 12칸 원뿔, 대상마다 1d8 색. 1~5(빨강 화염·주황 산·노랑 번개·초록 독·파랑 냉기): 민첩 내성 12d6(성공 절반).
## 6 남색: 민첩 내성 실패 시 속박(턴 끝 건강 내성 — 석화 진행은 생략). 7 보라: 실패 시 실명(턴 시작 지혜 내성 — 이계 이동은 생략).
## 8: 두 번 굴려 둘 다(8은 다시).

const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const TYPES := ["fire", "acid", "lightning", "poison", "cold"]


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var world: Dictionary = ctx["world"]
	var spell: Dictionary = ctx["spell"]
	var cells := Spellcasting.area_cells(world, c, spell, ctx["aim"])
	var dc: int = Spellcasting.spell_dc(c)
	var targets: Array = load("res://scripts/rules/area.gd").creatures_in(world["grid"], cells).filter(func(o: Node) -> bool: return o != c and not o.dead)
	for t: Node in targets:
		var rays: Array = [Dice.die(8)]
		if rays[0] == 8:
			rays = [Dice.die(7), Dice.die(7)]
		for ray: int in rays:
			if t.dead:
				break
			if ray <= 5:
				var dt: String = TYPES[ray - 1]
				Resolver.save_effect([t], {"ability": "dex", "dc": dc}, [{"type": "damage", "dice": "12d6", "damage_type": dt}],
					[{"type": "damage", "dice": "12d6", "damage_type": dt, "scale": 0.5}], {"source": c, "magic": true})
			elif ray == 6:
				if not Resolver.saving_throw(t, "dex", dc, {"source": c, "magic": true})["success"]:
					t.apply_condition("restrained", -1, c, {"repeat_save": {"ability": "con", "dc": dc}})
			else:
				if not Resolver.saving_throw(t, "dex", dc, {"source": c, "magic": true})["success"]:
					t.apply_condition("blinded", -1, c, {"repeat_save": {"ability": "wis", "dc": dc}})
	return {"ok": true, "targets": targets.size()}
