extends "res://scripts/rules/effect_script.gd"
## 인내의 방어(몽크 2레벨, SRD): 보너스 행동으로 이탈. 기가 있으면 기 1로 이탈 + 회피(다음 자기 턴 시작까지
## 나를 노리는 공격 불리·민첩 내성 유리 — 공용 회피 행동은 없어 이 기능 안에서만).

const Combat := preload("res://scripts/rules/combat.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	c.turn["disengaged"] = true
	if c.resource("focus") > 0:
		c.spend_resource("focus")
		c.extra_modifiers.append({"effect": {"type": "advantage", "roll": "attack", "side": "against", "value": "disadvantage"}, "source": "dodge", "until_turn_start_of": c})
		c.extra_modifiers.append({"effect": {"type": "advantage", "roll": "save", "side": "self", "value": "advantage", "ability": ["dex"]}, "source": "dodge", "until_turn_start_of": c})
		if c.has_cap("heightened_focus"):
			var die: String = load("res://scripts/rules/combat.gd").martial_arts_die(c)
			var thp: int = Dice.roll(die, "고양된 집중")["total"] + Dice.roll(die, "고양된 집중")["total"]
			load("res://scripts/rules/resolver.gd").grant_temp_hp(c, thp)  # 고양된 집중(10레벨): 무술 주사위 2개 임시 HP
		Dice.log_text("%s 인내의 방어: 이탈 + 회피" % c.label())
		return {"ok": true, "dodge": true}
	Dice.log_text("%s 인내의 방어: 이탈" % c.label())
	return {"ok": true}
