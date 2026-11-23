extends "res://scripts/rules/effect_script.gd"
## 연타(몽크 2레벨, SRD): 기 1, 보너스 행동으로 비무장 공격 2회. 열린 손 기법(열린 손 3레벨, 능력 태그 open_hand_technique):
## 연타로 맞히면 설정(options.open_hand_technique: topple 넘어뜨리기·push 밀기·addle 기회 공격 막기)대로 — DC 8 + 지혜 + 숙련.

const Combat := preload("res://scripts/rules/combat.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const STRIKES := 2


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	var w: Dictionary = ctx.get("world", {})
	if not (t is Node) or t.dead or not c.is_hostile_to(t):
		return {"ok": false, "reason": "적을 골라야 한다"}
	if w.has("grid") and w["grid"].distance_between(c, t) > 1:
		return {"ok": false, "reason": "인접해야 한다"}
	var hits := 0
	var n := STRIKES + (1 if c.has_cap("heightened_focus") else 0)  # 고양된 집중(10레벨): 3회
	for i in n:
		if t.dead:
			break
		var res := Combat._do_attack(w, c, t, Combat.build_weapon_attack(c, "unarmed"))
		if res.get("hit", false):
			hits += 1
			_technique(w, c, t)
	return {"ok": true, "hits": hits}


func _technique(w: Dictionary, c: Node, t: Node) -> void:
	if not c.has_cap("open_hand_technique") or t.dead:
		return
	var dc: int = 8 + c.ability_mod("wis") + c.proficiency_bonus
	match str(c.options.get("open_hand_technique", "topple")):
		"topple":
			if not Resolver.saving_throw(t, "dex", dc)["success"]:
				t.apply_condition("prone", -1)
		"push":
			if not Resolver.saving_throw(t, "str", dc)["success"] and w.has("grid"):
				Combat._push_up_to(w, c, t, 3)
		"addle":
			t.extra_modifiers.append({"effect": {"type": "modify", "stat": "no_reactions"}, "source": "addle", "until_turn_start_of": t})
