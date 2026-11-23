extends "res://scripts/rules/effect_script.gd"
## 그림자 망토(기만 영역 6레벨, BG3): 행동 + 신성 변환. 2턴 동안 투명(공격·주문으로 풀림). 가려진 곳 조건은 생략.
func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	c.apply_condition("invisible", 2, "cloak_of_shadows", {"ends_on_attack": true})
	return {"ok": true}
