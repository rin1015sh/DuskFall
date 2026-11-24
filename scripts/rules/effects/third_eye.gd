extends "res://scripts/rules/effect_script.gd"
## 셋째 눈(예언학파 10레벨, BG3): 행동, 긴 휴식까지 — 상시 설정 third_eye로 암시야 24칸 또는 투명 보기. 긴 휴식 1회.
func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	if str(c.options.get("third_eye", "darkvision")) == "see_invisible":
		if not c.senses.has("see_invisible"):
			c.senses.append("see_invisible")
			c.set_meta("temp_senses", c.get_meta("temp_senses", []) + ["see_invisible"])  # 긴 휴식에 지운다
	else:
		if not c.has_meta("base_darkvision"):
			c.set_meta("base_darkvision", c.darkvision_tiles)
		c.darkvision_tiles = maxi(c.darkvision_tiles, 24)
		if not c.senses.has("darkvision"):
			c.senses.append("darkvision")
	return {"ok": true}
