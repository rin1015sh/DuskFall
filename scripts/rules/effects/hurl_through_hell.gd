extends "res://scripts/rules/effect_script.gd"
## 지옥으로 내던지기(악마 후원자 14레벨, SRD): 턴당 1회 공격으로 맞히면 매력 내성(주문 DC), 실패 시 사라졌다가
## 8d10 정신(악마는 피해 없음) + 다음 내 턴 끝까지 추방(무력화·다른 차원). 긴 휴식 1회 — 없으면 계약 슬롯 1개로(자동).
## 설정 켬·끔(켬이면 첫 명중에 자동).

const Resolver := preload("res://scripts/rules/resolver.gd")
const Spellcasting := preload("res://scripts/rules/spellcasting.gd")


func is_implemented() -> bool:
	return true


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var res: Dictionary = ctx["res"]
	var t: Variant = res.get("target")
	if res.get("attacker") != c or not (t is Node) or t.dead or c.turn.get("hurl_used", false):
		return {"ok": false}
	if str(c.options.get("hurl_through_hell", "on")) != "on":
		return {"ok": false}
	var pay := ""
	if c.resource("hurl_through_hell") > 0:
		pay = "hurl_through_hell"
	else:
		for lv in range(1, 10):
			for key: String in ["spell_slot_%d", "pact_slot_%d"]:
				if pay == "" and c.resource(key % lv) > 0 and str(c.resources[key % lv].get("recharge", "")) == "short":
					pay = key % lv  # 계약 마법 슬롯(짧은 휴식 회복)
	if pay == "":
		return {"ok": false}
	c.turn["hurl_used"] = true
	c.spend_resource(pay)
	var s := Resolver.saving_throw(t, "cha", Spellcasting.spell_dc(c), {"source": c})
	if s["success"]:
		return {"ok": true}
	if t.creature_type != "fiend":
		Resolver.apply_damage(t, [{"amount": Dice.roll("8d10", "지옥으로 내던지기")["total"], "damage_type": "psychic"}], {"attacker": c})
	if not t.dead:
		t.apply_condition("banished", 2, c)
	return {"ok": true}
