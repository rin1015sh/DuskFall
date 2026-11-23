extends "res://scripts/rules/effect_script.gd"
## 신성 감지(팔라딘 3레벨, SRD): 보너스 행동, 신성 변환 1회. 10분(100턴) 동안 12칸 안 천상체·악마·언데드의 위치와 종류를 안다 —
## 그 생물에게 상태 divine_sensed(표시, 숨기로 얻은 투명이 통하지 않음)를 걸고 기록에 남긴다. 축성·모독된 곳 감지는 생략.

const RANGE := 12
const TYPES := ["celestial", "fiend", "undead"]


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var w: Dictionary = ctx.get("world", {})
	var found: Array = []
	if w.has("grid"):
		var grid: Node = w["grid"]
		for o: Node in grid.creatures():
			if o == c or o.dead or not str(o.creature_type) in TYPES or grid.distance_between(c, o) > RANGE:
				continue
			var hide: Dictionary = o.condition_instance("invisible")
			if not hide.is_empty() and hide["source"] is String and hide["source"] == "hide":
				o.remove_condition("invisible")  # 숨어 있어도 위치를 안다
			o.apply_condition("divine_sensed", 100, c)
			found.append("%s(%s)" % [o.label(), o.creature_type])
	Dice.log_text("%s 신성 감지: %s" % [c.label(), ", ".join(found) if not found.is_empty() else "없음"])
	return {"ok": true, "found": found.size()}
