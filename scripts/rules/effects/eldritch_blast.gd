extends "res://scripts/rules/effect_script.gd"
## 섬뜩한 화살(워락 소마법, SRD): 광선 1개(5레벨 2개), 광선마다 원거리 주문 공격, 명중 1d10 역장.
## 능력 태그 agonizing_blast(고통의 화살): 피해 + 매력 수정치. repelling_blast(밀어내는 화살): 명중한 큰 생물 이하를 2칸 밀어낸다.

const Spellcasting := preload("res://scripts/rules/spellcasting.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")
const Combat := preload("res://scripts/rules/combat.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var w: Dictionary = ctx["world"]
	var grid: Node = w["grid"]
	var c: Node = ctx["self"]
	var t: Node = grid.creature_at(ctx["aim"])
	if t == null:
		return {"ok": false, "reason": "대상이 없다"}
	var beams := 2 if c.level >= 5 else 1
	var dice := "1d10"
	if c.has_cap("agonizing_blast"):
		dice += "%+d" % c.ability_mod("cha")
	var hits := 0
	for i in beams:
		if t.dead:
			break
		var atk := {"name": "Eldritch Blast", "bonus": Spellcasting.spell_attack_bonus(c), "kind": "ranged", "weapon": false,
			"spell": "eldritch_blast", "damage": [{"dice": dice, "damage_type": "force"}]}
		var actx: Dictionary = grid.attack_context(c, t)
		if Combat.is_threatened(w, c):
			actx["disadvantage"].append("근접 위협")
		if Resolver.attack(c, t, atk, actx)["hit"]:
			hits += 1
			if c.has_cap("repelling_blast") and not t.dead and grid.size_of(t) <= 2:
				Combat._push_up_to(w, c, t, 2)
	return {"ok": true, "hits": hits}
