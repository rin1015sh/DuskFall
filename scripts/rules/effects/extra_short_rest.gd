extends "res://scripts/rules/effect_script.gd"
## Prayer of Healing(2레벨, SRD): 6칸 안 아군 최대 5명이 짧은 휴식 효과(짧은 휴식 횟수를 쓰지 않음) + 2d8(+1d8/슬롯). 대상마다 긴 휴식당 1회(룰북 7단계).

const U := preload("res://scripts/rules/spell_util.gd")
const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var g := U.grid(ctx)
	var c: Node = ctx["self"]
	var dice := "%dd8" % (2 + maxi(int(ctx.get("slot", 2)) - 2, 0))
	var n := 0
	for t: Node in g.creatures():
		if n >= 5 or t.dead or t.is_hostile_to(c) or t.team != c.team or g.distance_between(c, t) > 6:
			continue
		if t.get_meta("prayed", false):
			continue
		t.set_meta("prayed", true)
		t.hp = mini(t.hp_max, t.hp + t.hp_max / 2)
		for id: String in t.resources:
			var r: Dictionary = t.resources[id]
			match r.get("recharge", ""):
				"short":
					r["current"] = r["max"]
				"short_one":
					r["current"] = mini(r["max"], r["current"] + 1)
		Resolver.heal(t, Dice.roll(dice, "Prayer of Healing")["total"], c)
		n += 1
	if not ctx["world"].has("on_long_rest"):
		ctx["world"]["on_long_rest"] = []
	ctx["world"]["on_long_rest"].append(func() -> void:
		for t2: Node in g.creatures():
			t2.remove_meta("prayed"))
	return {"ok": true, "targets": n}
