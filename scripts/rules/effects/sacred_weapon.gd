extends "res://scripts/rules/effect_script.gd"
## 신성한 무기(헌신의 맹세 3레벨, BG3): 행동 + 신성 변환. 10턴 동안 무기 명중 굴림 + 매력 수정치(최소 +1), 밝은 빛(생략).
const TURNS := 10


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	for m in c.extra_modifiers.duplicate():
		if m.get("source", "") == "sacred_weapon":
			c.extra_modifiers.erase(m)
	var bonus := maxi(1, c.ability_mod("cha"))
	c.extra_modifiers.append({"effect": {"type": "modify", "stat": "weapon_attack", "add": bonus}, "source": "sacred_weapon", "turns_left": TURNS})
	Dice.log_text("%s: 신성한 무기(명중 %+d)" % [c.label(), bonus])
	return {"ok": true, "bonus": bonus}
