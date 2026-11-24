extends "res://scripts/rules/effect_script.gd"
## 야생 변신(드루이드 2레벨, SRD 5.2.1): 보너스 행동으로 아는 짐승 형태가 된다(형태 = 기능 데이터 forms 레벨표의 몬스터 ID,
## 최대 도전 등급 cr_by_level, 비행 불가). 고르는 형태는 opts.form → 설정 options.wild_shape_form → 첫 형태.
## 변신 중: 근력·민첩·건강·AC·속도·크기·공격은 짐승 것(공격 = 짐승의 첫 근접 공격 — combat.attack), HP는 그대로 +
## 임시 HP = 드루이드 레벨, 주문 불가(상태 wild_shaped). 보너스 행동으로 풀거나, 0 HP·긴 휴식에 풀린다(revert).

const Resolver := preload("res://scripts/rules/resolver.gd")


func is_implemented() -> bool:
	return true


## 지금 고를 수 있는 형태(레벨표 + 도전 등급 상한 + 비행 없음).
static func forms_for(c: Node) -> Array:
	var f: Dictionary = c.feature_data.get("wild_shape", {})
	var out: Array = []
	# 다른 기능의 형태(달 회합 전투 형태 — forms + ignore_cr): 도전 등급 상한 없이, 그 기능 레벨표대로
	for fid: String in c.feature_data:
		var g: Dictionary = c.feature_data[fid]
		if fid == "wild_shape" or not g.has("forms"):
			continue
		for k: String in g["forms"]:
			if c.feature_level(fid) >= int(k):
				for id: String in g["forms"][k]:
					if not RulesDB.get_entry("monster", id).is_empty() and not id in out:
						out.append(id)
	var max_cr := 0.0
	for k: String in f.get("cr_by_level", {}):
		if c.feature_level("wild_shape") >= int(k):
			max_cr = maxf(max_cr, float(f["cr_by_level"][k]))
	for k: String in f.get("forms", {}):
		if c.feature_level("wild_shape") < int(k):
			continue
		for id: String in f["forms"][k]:
			var m := RulesDB.get_entry("monster", id)
			if not m.is_empty() and float(m.get("cr", 99)) <= max_cr and int(m.get("fly_tiles", 0)) == 0 and not id in out:
				out.append(id)
	return out


func apply(ctx: Dictionary) -> Dictionary:
	var c: Node = ctx["self"]
	var forms := forms_for(c)
	if forms.is_empty():
		return {"ok": false, "reason": "아는 형태가 없다"}
	var want := str(ctx.get("opts", {}).get("form", c.options.get("wild_shape_form", forms[0])))
	if not want in forms:
		want = forms[0]
	if c.has_meta("beast_form"):
		revert(c)
	shape_stats(c, want)
	Resolver.grant_temp_hp(c, c.feature_level("wild_shape"))
	c.apply_condition("wild_shaped", -1, c)
	Dice.log_text("%s: 야생 변신 — %s" % [c.label(), RulesDB.get_entry("monster", want)["name"]["ko"]])
	return {"ok": true, "form": want}


## 짐승의 신체 능력치로 바꾼다(원래 값은 meta wild_shape_saved).
static func shape_stats(c: Node, id: String) -> void:
	var m := RulesDB.get_entry("monster", id)
	c.set_meta("wild_shape_saved", {"str": c.abilities["str"], "dex": c.abilities["dex"], "con": c.abilities["con"],
		"ac_base": c.ac_base, "speed_tiles": c.speed_tiles, "size": c.size, "weight_kg": c.weight_kg})
	for a: String in ["str", "dex", "con"]:
		c.abilities[a] = int(m["abilities"][a])
	c.ac_base = int(m["ac"])
	c.speed_tiles = int(m.get("speed_tiles", 6))
	c.size = str(m.get("size", "medium"))
	c.weight_kg = float(m.get("weight_kg", c.weight_kg))
	c.set_meta("beast_form", id)


## 원래 모습으로(보너스 행동·0 HP·긴 휴식).
static func revert(c: Node) -> void:
	if not c.has_meta("beast_form"):
		return
	var s: Dictionary = c.get_meta("wild_shape_saved", {})
	for a: String in ["str", "dex", "con"]:
		if s.has(a):
			c.abilities[a] = int(s[a])
	for k: String in ["ac_base", "speed_tiles", "size", "weight_kg"]:
		if s.has(k):
			c.set(k, s[k])
	c.remove_meta("beast_form")
	c.remove_meta("wild_shape_saved")
	c.remove_condition("wild_shaped")
	Dice.log_text("%s: 원래 모습으로" % c.label())
