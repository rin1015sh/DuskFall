extends RefCounted
## 행동·주문 설명(단축 막대 툴팁과 아이패드용 '고른 행동 설명 카드'가 함께 쓴다).
## 데이터에서 읽는다: 이름, 비용·대상, 주문이면 레벨·사거리·집중·내성·피해/회복 주사위, 설명, 못 쓰는 이유.

const Actions := preload("res://scripts/rules/actions.gd")
const UiText := preload("res://scenes/ui/ui_text.gd")


## {"title": 이름, "meta": 비용·대상 등 한 줄, "dice": 피해·회복 한 줄(없으면 ""), "desc": 설명, "why": 못 쓰는 이유}
static func describe(world: Dictionary, c: Node, key: String, explore: bool) -> Dictionary:
	var d := Actions.def_of(key)
	var meta: PackedStringArray = [UiText.t("cost_" + str(d.get("cost", "action")))]
	var dice := ""
	var sp: Dictionary = d.get("spell", {})
	if not sp.is_empty():
		var lv := int(sp.get("level", 0))
		meta.insert(0, UiText.t("info_cantrip") if lv == 0 else UiText.t("info_spell_level") % lv)
		var rng: Dictionary = sp.get("range", {})
		match str(rng.get("type", "")):
			"touch":
				meta.append(UiText.t("info_touch"))
			"tiles":
				meta.append(UiText.t("info_range") % _meters(int(rng.get("tiles", 0))))
			"self":
				meta.append(UiText.t("target_self"))
		if bool(sp.get("concentration", false)):
			meta.append(UiText.t("info_concentration"))
		if bool(sp.get("cast", {}).get("ritual", false)):
			meta.append(UiText.t("info_ritual"))
		dice = _dice_line(sp.get("effects", {}))
	else:
		meta.append(UiText.t("target_" + str(d.get("target", "self"))))
	var why := Actions.unavailable(world, c, key, explore) if c != null else ""
	return {"title": UiText.name_of(d.get("name", {})), "meta": " · ".join(meta), "dice": dice,
		"desc": UiText.name_of(d.get("desc", {})), "why": why}


## 툴팁 글(마우스 올리기)
static func tooltip(world: Dictionary, c: Node, key: String, explore: bool) -> String:
	var i := describe(world, c, key, explore)
	var out: PackedStringArray = [i["title"], i["meta"]]
	for k: String in ["dice", "desc"]:
		if i[k] != "":
			out.append(i[k])
	if i["why"] != "":
		out.append("— " + i["why"])
	return "\n".join(out)


static func _meters(tiles: int) -> String:
	var m := tiles * 1.5
	return str(int(m)) if is_equal_approx(m, roundf(m)) else "%.1f" % m


## 효과 목록에서 피해·회복 주사위를 모은다(내성 판정이면 능력치 이름도).
static func _dice_line(eff: Variant) -> String:
	if typeof(eff) != TYPE_DICTIONARY:
		return ""
	var parts: PackedStringArray = []
	var check: Dictionary = eff.get("check", {}) if typeof(eff.get("check")) == TYPE_DICTIONARY else {}
	if str(check.get("type", "")) == "save":
		parts.append(UiText.t("info_save") % UiText.ability_name(str(check.get("ability", ""))))
	var seen := {}
	for list_key: String in ["hit", "fail", "apply", "always"]:
		var list: Variant = eff.get(list_key, [])
		if typeof(list) != TYPE_ARRAY:
			continue
		for e: Variant in list:
			if typeof(e) != TYPE_DICTIONARY or not e.has("dice") or float(e.get("scale", 1.0)) < 1.0:
				continue
			var s := ""
			match str(e.get("type", "")):
				"damage":
					s = UiText.t("info_damage") % ("%s %s" % [e["dice"], UiText.damage_name(str(e.get("damage_type", "")))]).strip_edges()
				"heal":
					s = UiText.t("info_heal") % str(e["dice"])
			if s != "" and not seen.has(s):
				seen[s] = true
				parts.append(s)
	return " · ".join(parts) if parts.size() > (1 if str(check.get("type", "")) == "save" else 0) else ""
