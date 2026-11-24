extends "res://scripts/rules/effect_script.gd"
## 변환자의 돌(변환학파 6레벨, BG3): 행동, 곁의 아군(또는 자신)에게 긴 휴식까지 고른 이득(상시 설정 transmuters_stone) —
## 속도 +2칸 또는 산·냉기·화염·번개·천둥 저항. 새로 만들면 예전 돌은 사라진다. 긴 휴식 1회.
const KINDS := ["speed", "acid", "cold", "fire", "lightning", "thunder"]


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	var grid: Node = ctx["world"]["grid"]
	if not (t is Node) or t.dead or c.is_hostile_to(t) or grid.distance_between(c, t) > 1:
		t = c
	var kind := str(c.options.get("transmuters_stone", "speed"))
	for o: Node in grid.creatures():
		for k: String in KINDS:
			var a: Dictionary = o.condition_instance("transmuters_stone_" + k)
			if not a.is_empty() and a["source"] == c:
				o.remove_condition("transmuters_stone_" + k)
	t.apply_condition("transmuters_stone_" + kind, -1, c)
	return {"ok": true}
