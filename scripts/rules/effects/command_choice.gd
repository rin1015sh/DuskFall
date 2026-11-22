extends "res://scripts/rules/effect_script.gd"
## Command(SRD): 지혜 내성 실패 시 다음 턴에 명령을 따른다. 1차: 엎드려(넘어짐)·떨궈(무기 세트 빈손)·멈춰(다음 턴 이동·행동 불가).
## 다가와·도망쳐는 AI 강제 이동이 필요해 6단계에서(지금은 멈춰와 같게 처리하지 않고 효과 없음).
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Area := preload("res://scripts/rules/area.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var grid: Node = ctx["world"]["grid"]
	var targets: Array = ctx["opts"].get("targets", [])
	if targets.is_empty() and grid.creature_at(ctx["aim"]) != null:
		targets = [grid.creature_at(ctx["aim"])]
	targets = targets.slice(0, Spellcasting.max_targets(ctx["spell"], ctx["slot"]))
	var order: String = ctx["opts"].get("choice", "grovel")
	for t: Node in targets:
		if Resolver.saving_throw(t, "wis", Spellcasting.spell_dc(c), {"source": c})["success"]:
			continue
		match order:
			"grovel":
				t.apply_condition("prone", -1, c)
			"drop":
				t.weapon_sets[t.active_set]["main"] = ""
			"halt":
				t.apply_condition("surprised", -1, "command_halt")  # 다음 턴 이동·행동 불가(첫 턴이 끝나면 풀림)
	return {"ok": true}
