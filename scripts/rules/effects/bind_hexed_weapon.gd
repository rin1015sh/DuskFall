extends "res://scripts/rules/effect_script.gd"
## 저주 무기 결속(주술검사 1레벨, BG3): 행동, 주 무기를 결속 — 숙련, 마법 피해, 명중·피해에 매력(근력·민첩보다 높으면 — BG3 주술검사),
## 맞힐 때 20% 확률로 주술검사의 저주(아직 저주받지 않은 대상). 긴 휴식까지(무기를 바꾸면 풀림).
func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var wid: String = c.weapon_sets.get("melee", {}).get("main", "")
	if wid == "":
		return {"ok": false, "reason": "주 무기가 없다"}
	c.set_meta("hexed_weapon", wid)
	return {"ok": true, "weapon": wid}
