extends "res://scripts/rules/effect_script.gd"
## 눈앞에 숨기(레인저 10레벨, BG3): 행동, 긴 휴식 1회. 투명(공격·주문으로 풀림 — [변형] 움직이면 풀림·은신 +10은 생략).
func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	c.apply_condition("invisible", -1, "hide_in_plain_sight", {"ends_on_attack": true})
	return {"ok": true}
