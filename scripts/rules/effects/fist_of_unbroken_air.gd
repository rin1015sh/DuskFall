extends "res://scripts/rules/effect_script.gd"
## 꺾이지 않는 바람의 주먹(4원소, BG3): 행동 + 기 2, 6칸 안 대상 근력 내성(DC 8 + 숙련 + 지혜) — 실패 3d10 타격(향상된 원소 시전 4d10),
## 4칸(6m) 밀림 + 넘어짐. 성공 절반.
const Resolver := preload("res://scripts/rules/resolver.gd")
const Combat := preload("res://scripts/rules/combat.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	var w: Dictionary = ctx["world"]
	if not (t is Node) or t.dead or t == c:
		return {"ok": false, "reason": "대상을 골라야 한다"}
	if w["grid"].distance_between(c, t) > 6:
		return {"ok": false, "reason": "6칸 안"}
	var dice := "4d10" if c.has_cap("improved_elemental_casting") else "3d10"
	var n: int = Dice.roll(dice, "바람의 주먹")["total"]
	var ok: bool = Resolver.saving_throw(t, "str", 8 + c.proficiency_bonus + c.ability_mod("wis"), {"source": c, "magic": true})["success"]
	Resolver.apply_damage(t, [{"amount": n / 2 if ok else n, "damage_type": "bludgeoning"}], {"attacker": c, "magic": true})
	if not ok and not t.dead:
		Combat._push_up_to(w, c, t, 4)
		t.apply_condition("prone", -1, c)
	return {"ok": true, "saved": ok}
