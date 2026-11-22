extends "res://scripts/rules/effect_script.gd"
## Slow(SRD): 40피트 정육면체(8×8칸) 안 최대 6체 지혜 내성. 실패하면 속도 절반, AC −2, 민첩 내성 −2, 반응 불가.
## 행동·보너스 행동 중 하나만(1차는 반응 불가·수치만 — 행동 제한은 확인 필요), 턴 끝 반복 내성.
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Area := preload("res://scripts/rules/area.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var cells := Spellcasting.area_cells(ctx["world"], c, ctx["spell"], ctx["aim"])
	var foes: Array = Area.creatures_in(ctx["world"]["grid"], cells).filter(func(o: Node) -> bool:
		return not o.dead and o.is_hostile_to(c)).slice(0, 6)
	var id: int = ctx["instance"]["id"]
	var dc := Spellcasting.spell_dc(c)
	var n := 0
	for t: Node in foes:
		var s := Resolver.saving_throw(t, "wis", dc, {"source": c})
		if s["success"]:
			continue
		n += 1
		for e: Dictionary in [{"type": "modify", "stat": "speed_tiles", "add": -(t.speed_tiles / 2)}, {"type": "modify", "stat": "ac", "add": -2},
				{"type": "modify", "stat": "saving_throw_dex", "add": -2}, {"type": "modify", "stat": "no_reactions"}]:
			t.extra_modifiers.append({"effect": e, "source": "slow", "instance": id, "turns_left": -1})
		# 반복 내성은 표지 상태로 건다(턴 끝 처리가 같은 인스턴스 효과를 함께 걷는다)
		t.apply_condition("slowed", -1, c, {"instance": id, "repeat_save": {"ability": "wis", "dc": dc}})
		ctx["instance"]["targets"].append(t)
	return {"ok": true, "affected": n}
