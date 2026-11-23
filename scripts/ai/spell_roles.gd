extends RefCounted
## AI가 쓸 주문 고르기(주문 이름 목록 대신 주문 데이터로 분류). 주문 데이터 "ai": {"role", "priority"}가 있으면 그것을 따른다.
## 역할: heal(회복 — 쓰러진 아군), attack_cantrip(공격 소마법), area(범위 피해·제압 — 적 둘 이상 또는 강한 적 하나), aura(자신 중심 지속 범위),
##       single(단일 대상 슬롯 주문 — HP가 많은 적에게),
##       light(빛 — 보이지 않는 적 밝히기), none(AI가 쓰지 않음).


static func role_of(spell: Dictionary) -> String:
	if spell.has("ai"):
		return str(spell["ai"].get("role", "none"))
	var eff: Dictionary = spell.get("effects", {})
	var all: Array = []
	for k: String in ["apply", "hit", "fail"]:
		all.append_array(eff.get(k, []))
	var types: Array = all.map(func(e: Dictionary) -> String: return str(e.get("type", "")))
	var area: Variant = spell.get("area")
	if "heal" in types and area == null:
		return "heal"
	if "light" in types:
		return "light"
	var check := str(eff.get("check", {}).get("type", ""))
	if area != null and check == "save" and ("damage" in types or "apply_condition" in types):
		return "aura" if str(spell.get("range", {}).get("type", "")) == "self" and str(spell.get("duration", {}).get("type", "")) != "instant" else "area"
	if int(spell.get("level", 0)) == 0 and area == null and check in ["attack", "save"] and "damage" in types:
		return "attack_cantrip"
	if int(spell.get("level", 0)) > 0 and area == null and check in ["attack", "save"] and ("damage" in types or "apply_condition" in types) \
			and str(spell.get("range", {}).get("type", "")) != "self":
		return "single"  # 단일 대상 슬롯 주문(고사·괴물 속박·추방 등) — 강한 적에게
	return "none"


static func _deals_damage(spell: Dictionary) -> bool:
	var eff: Dictionary = spell.get("effects", {})
	for k: String in ["apply", "hit", "fail"]:
		for e: Dictionary in eff.get(k, []):
			if str(e.get("type", "")) == "damage":
				return true
	return false


## c가 가진 그 역할의 주문(우선순위: 데이터 ai.priority 높은 순 → 주문 레벨 높은 순, 회복은 보너스 행동·낮은 레벨 먼저)
static func known(c: Node, role: String) -> Array:
	var out: Array = []
	for sid: String in c.spells:
		var sp := RulesDB.get_entry("spell", sid)
		if not sp.is_empty() and role_of(sp) == role and str(sp.get("game_status", "included")) == "included":
			out.append(sp)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := int(a.get("ai", {}).get("priority", 0))
		var pb := int(b.get("ai", {}).get("priority", 0))
		if pa != pb:
			return pa > pb
		if role in ["area", "single"]:
			var da := _deals_damage(a)
			var db := _deals_damage(b)
			if da != db:
				return da  # 범위 주문: 피해를 주는 것 먼저(같은 우선순위일 때)
		if role == "heal":
			var ba := str(a.get("cast", {}).get("cost", "")) == "bonus_action"
			var bb := str(b.get("cast", {}).get("cost", "")) == "bonus_action"
			if ba != bb:
				return ba
			return int(a["level"]) < int(b["level"])
		return int(a["level"]) > int(b["level"]))
	return out.map(func(sp: Dictionary) -> String: return str(sp["id"]))
