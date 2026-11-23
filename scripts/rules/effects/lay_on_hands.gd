extends "res://scripts/rules/effect_script.gd"
## 신성한 손길(팔라딘 1레벨, SRD): 치유 풀(자원 lay_on_hands = 팔라딘 레벨 × 5). 보너스 행동으로 만진 생물(자신 포함).
## BG3식 자동: 대상이 중독이면 풀 5로 먼저 해독(그 5는 회복하지 않는다), 남은 풀에서 잃은 HP만큼 회복.

const Resolver := preload("res://scripts/rules/resolver.gd")
const CURE_COST := 5


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var t: Variant = ctx.get("target")
	if not (t is Node):
		t = c
	if t.dead:
		return {"ok": false, "reason": "대상이 없다"}
	var pool: int = c.resource("lay_on_hands")
	var cured := false
	if t.has_condition("poisoned") and pool >= CURE_COST:
		t.remove_condition("poisoned")
		pool -= CURE_COST
		cured = true
	# 회복의 손길(팔라딘 14레벨): 풀 5마다 실명·매혹·공포·마비·기절 하나씩 해제(그 5는 회복하지 않는다)
	var lifted: Array = []
	if c.has_cap("restoring_touch"):
		for cid: String in ["paralyzed", "stunned", "frightened", "charmed", "blinded"]:
			if t.has_condition(cid) and pool >= CURE_COST:
				t.remove_condition(cid)
				pool -= CURE_COST
				lifted.append(cid)
				cured = true
	var want: int = t.hp_max - t.hp
	var amount := mini(pool, want)
	if amount <= 0 and not cured:
		return {"ok": false, "reason": "회복할 것이 없다"}
	if amount > 0:
		Resolver.heal(t, amount, c)
	c.resources["lay_on_hands"]["current"] = pool - amount
	Dice.log_text("%s: 신성한 손길 → %s %d 회복%s(남은 풀 %d)" % [c.label(), t.label(), amount, ", 해독" if cured else "", pool - amount])
	return {"ok": true, "healed": amount, "cured": cured, "keep_resource": true}
