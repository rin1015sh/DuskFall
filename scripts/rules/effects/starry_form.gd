extends "res://scripts/rules/effect_script.gd"
## 별의 형상(별 회합 2레벨, BG3): 보너스 행동 + 야생 변신 1회, 긴 휴식까지 — 상시 설정 starry_form으로 궁수·성배·용.
const FORMS := ["archer", "chalice", "dragon"]


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	for f: String in FORMS:
		c.remove_condition("starry_" + f)
	var pick := str(c.options.get("starry_form", "archer"))
	c.apply_condition("starry_" + pick, -1, c)
	return {"ok": true, "form": pick}
