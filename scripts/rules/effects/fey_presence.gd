extends "res://scripts/rules/effect_script.gd"
## 요정의 존재감(요정 후원자 1레벨, BG3): 행동, 짧은 휴식 1회. 2칸(3m) 안 적 지혜 내성(주문 DC) 실패 시 1턴 매혹 또는 공포(설정 fey_presence).
const Resolver := preload("res://scripts/rules/resolver.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var grid: Node = ctx["world"]["grid"]
	var cond := "frightened" if str(c.options.get("fey_presence", "charmed")) == "frightened" else "charmed"
	var n := 0
	for o: Node in grid.creatures():
		if not o.dead and o.is_hostile_to(c) and grid.distance_between(c, o) <= 2:
			if not Resolver.saving_throw(o, "wis", Spellcasting.spell_dc(c), {"source": c, "magic": true, "vs_condition": cond})["success"]:
				o.apply_condition(cond, 2, c)
				n += 1
	return {"ok": true, "targets": n}
