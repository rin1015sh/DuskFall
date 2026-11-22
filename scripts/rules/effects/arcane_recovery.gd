extends "res://scripts/rules/effect_script.gd"
## 비전 회복(위저드 1레벨, SRD): 짧은 휴식 뒤 쓴 슬롯을 합계 레벨 ≤ 위저드 레벨 절반(올림)만큼 회복, 6레벨 이상 슬롯은 안 됨.
## 긴 휴식 1회. 자동으로 높은 슬롯부터 고른다(7단계 짧은 휴식 UI에서 고르게 바꿀 수 있다).


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var w: Dictionary = ctx.get("world", {})
	if w.get("turns") != null and w["turns"].in_combat:
		return {"ok": false, "reason": "전투 중에는 쓸 수 없다"}  # BG3식: 전투 밖이면 언제나(changes.md)
	var budget: int = ceili(c.level / 2.0)
	var got := 0
	for lv in range(5, 0, -1):
		var id := "spell_slot_%d" % lv
		if not c.resources.has(id):
			continue
		while budget >= lv and c.resources[id]["current"] < c.resources[id]["max"]:
			c.resources[id]["current"] += 1
			budget -= lv
			got += 1
	if got == 0:
		return {"ok": false, "reason": "회복할 슬롯이 없다"}
	return {"ok": true, "slots": got}
