extends RefCounted
## 주문 준비·교체·주문서 학습(룰북 6단계 주문 시전·주문서, 7단계 휴식). 주문 이름·클래스 이름을 모른다.
## 클래스 데이터 spellcasting.type: prepared(클래스 주문 목록 전체에서 준비) · spellbook(주문서에서 준비) · 그 밖(바꾸지 않음).
## 교체 창: 긴 휴식이 끝나면 열리고(spellcasting.swap.long_rest: -1 = 전부, n = n개), 다음 전투가 시작되면 닫힌다.
##   능력 태그 prepare_swap_short_rest(주문 암기)는 짧은 휴식 뒤 1개를 바꿀 수 있게 연다.
##   교체 수는 창이 열릴 때의 목록(prep_base)과 비교해 새로 넣은 주문 수로 센다(뺐다가 다시 넣으면 공짜).
## 주문서 학습(BG3식): 두루마리를 소모하고 주문 레벨 × 50gp, 시간 없음. 전투 밖, 준비할 수 있는 레벨까지만.
## 고른 결과는 명세(meta spec)의 spells·spellbook에도 남겨 레벨 업·불러오기 뒤에도 유지된다.

const GP_PER_LEVEL := 50


static func _sc(c: Node) -> Dictionary:
	return RulesDB.get_entry("class", c.class_id).get("spellcasting", {})


## prepared · spellbook · ""(교체 없음)
static func prep_type(c: Node) -> String:
	var t := str(_sc(c).get("type", ""))
	return t if t in ["prepared", "spellbook"] else ""


static func max_slot_level(c: Node) -> int:
	var best := 0
	for lv in range(1, 10):
		if c.resources.has("spell_slot_%d" % lv) and int(c.resources["spell_slot_%d" % lv]["max"]) > 0:
			best = lv
	return best


static func max_prepared(c: Node) -> int:
	var table: Dictionary = _sc(c).get("prepared", {})
	var best := 0
	var best_lv := 0
	for k: String in table:
		if c.level >= int(k) and int(k) >= best_lv:
			best_lv = int(k)
			best = int(table[k])
	return best


## 주문서 기본 크기(SRD: 1레벨 6개, 레벨마다 2개). 두루마리로 배운 것은 이 수에 상관없이 더한다.
static func spellbook_size(c: Node) -> int:
	var sb: Dictionary = _sc(c).get("spellbook", {})
	if sb.is_empty():
		return 0
	return int(sb.get("1", 6)) + int(sb.get("per_level", 2)) * (c.level - 1)


## 준비할 수 있는 주문(1레벨 이상, 가진 슬롯 레벨 이하, 고정 주문 제외).
static func pool(c: Node) -> Array:
	var t := prep_type(c)
	if t == "":
		return []
	var top := max_slot_level(c)
	var source: Array = []
	if t == "spellbook":
		source = c.spellbook
	else:
		var list := str(_sc(c).get("list", ""))
		for sp: Dictionary in RulesDB.entries("spell"):
			if list in sp.get("classes", []) and str(sp.get("game_status", "")) == "included":
				source.append(sp["id"])
	var fixed := fixed_spells(c)
	return source.filter(func(sid: String) -> bool:
		var lv := int(RulesDB.get_entry("spell", sid).get("level", 0))
		return lv >= 1 and lv <= top and not sid in fixed)


## 준비 수에 세지 않는 주문(항상 준비·종족·재주 — 소마법 제외).
static func fixed_spells(c: Node) -> Array:
	return c.spells.filter(func(sid: String) -> bool:
		return not sid in c.prepared and int(RulesDB.get_entry("spell", sid).get("level", 0)) > 0)


static func in_combat(world: Dictionary) -> bool:
	return world.get("turns") != null and world["turns"].in_combat


## 교체할 수 없는 이유("" = 가능).
static func change_blocked(world: Dictionary, c: Node) -> String:
	if prep_type(c) == "":
		return "준비 주문을 바꾸지 않는 클래스"
	if in_combat(world):
		return "전투 중에는 바꿀 수 없다"
	if c.prep_swaps == 0:
		return "긴 휴식 뒤에 바꿀 수 있다"
	return ""


## 창이 열린 뒤 바꾼 주문 수: 새로 넣은 주문 수에서 창이 열릴 때 비어 있던 준비 칸 수를 뺀다(빈 칸 채우기는 공짜).
static func changes(c: Node, list: Array) -> int:
	var added := list.filter(func(sid: String) -> bool: return not sid in c.prep_base).size()
	return maxi(0, added - maxi(0, max_prepared(c) - c.prep_base.size()))


## 남은 교체 수(-1 = 제한 없음).
static func swaps_left(c: Node) -> int:
	if c.prep_swaps < 0:
		return -1
	return maxi(0, c.prep_swaps - changes(c, c.prepared))


## 준비 목록을 통째로 바꾼다. 결과 {"ok", "reason"}.
static func set_prepared(world: Dictionary, c: Node, list: Array) -> Dictionary:
	var why := change_blocked(world, c)
	if why != "":
		return {"ok": false, "reason": why}
	var uniq: Array = []
	for sid: Variant in list:
		if not str(sid) in uniq:
			uniq.append(str(sid))
	var p := pool(c)
	for sid: String in uniq:
		if not sid in p:
			return {"ok": false, "reason": "준비할 수 없는 주문: %s" % sid}
	if uniq.size() > max_prepared(c):
		return {"ok": false, "reason": "준비 수 초과(%d)" % max_prepared(c)}
	if c.prep_swaps >= 0 and changes(c, uniq) > c.prep_swaps:
		return {"ok": false, "reason": "이번에 바꿀 수 있는 주문은 %d개" % c.prep_swaps}
	var kept: Array = c.spells.filter(func(sid: String) -> bool: return not sid in c.prepared)
	c.spells = kept + uniq
	c.prepared = uniq
	_sync_reactions(c)
	_save_spec(c)
	return {"ok": true}


## 한 주문을 준비하거나 뺀다(화면의 토글).
static func toggle(world: Dictionary, c: Node, sid: String) -> Dictionary:
	var list: Array = c.prepared.duplicate()
	if sid in list:
		list.erase(sid)
	else:
		list.append(sid)
	return set_prepared(world, c, list)


## 교체 창을 연다. kind: "long"(긴 휴식 — swap.long_rest, 기본 -1) · "short"(짧은 휴식 — 주문 암기 태그면 1)
## · "level_up"(레벨 업 — swap.level_up, 기본 0: 바드·소서러·워락식 레벨마다 1개).
static func open_window(c: Node, kind: String) -> void:
	if prep_type(c) == "":
		return
	var swap: Dictionary = _sc(c).get("swap", {})
	var n := 0
	match kind:
		"long":
			n = int(swap.get("long_rest", -1))
		"short":
			n = 1 if c.has_cap("prepare_swap_short_rest") else 0
		"level_up":
			n = int(swap.get("level_up", 0))
	if n == 0 or c.prep_swaps < 0:
		return  # 열 것이 없거나 이미 전부 바꿀 수 있다
	c.prep_swaps = n
	c.prep_base = c.prepared.duplicate()


## 전투가 시작되면 창을 닫는다.
static func close_window(c: Node) -> void:
	c.prep_swaps = 0
	c.prep_base = c.prepared.duplicate()


# ---------- 주문서 학습(두루마리) ----------

static func learn_cost(sid: String) -> int:
	return GP_PER_LEVEL * int(RulesDB.get_entry("spell", sid).get("level", 0))


## 두루마리에서 배울 수 없는 이유("" = 가능).
static func learn_blocked(world: Dictionary, c: Node, item_id: String) -> String:
	var item := RulesDB.get_entry("item", item_id)
	var sid := str(item.get("spell", ""))
	var sp := RulesDB.get_entry("spell", sid)
	if prep_type(c) != "spellbook":
		return "주문서가 없다"
	if item.get("category", "") != "scroll" or sp.is_empty():
		return "주문 두루마리가 아니다"
	if int(c.inventory.get(item_id, 0)) <= 0:
		return "두루마리가 없다"
	if not str(_sc(c).get("list", "")) in sp.get("classes", []):
		return "내 클래스 주문 목록에 없는 주문"
	if int(sp.get("level", 0)) < 1:
		return "소마법은 주문서에 적지 않는다"
	if int(sp["level"]) > max_slot_level(c):
		return "아직 준비할 수 없는 레벨"
	if sid in c.spellbook:
		return "이미 주문서에 있다"
	if in_combat(world):
		return "전투 중에는 적을 수 없다"
	if int(c.inventory.get("gold", 0)) < learn_cost(sid):
		return "금화가 모자라다(%dgp)" % learn_cost(sid)
	return ""


static func learn_from_scroll(world: Dictionary, c: Node, item_id: String) -> Dictionary:
	var why := learn_blocked(world, c, item_id)
	if why != "":
		return {"ok": false, "reason": why}
	var sid := str(RulesDB.get_entry("item", item_id)["spell"])
	var inv: Dictionary = c.inventory  # 배우는 캐릭터의 두루마리·금화(BG3식 캐릭터별)
	inv["gold"] = int(inv["gold"]) - learn_cost(sid)
	if int(inv["gold"]) <= 0:
		inv.erase("gold")
	inv[item_id] = int(inv[item_id]) - 1
	if int(inv[item_id]) <= 0:
		inv.erase(item_id)
	c.spellbook.append(sid)
	if c.has_meta("spec"):
		var spec: Dictionary = c.get_meta("spec")
		spec["spellbook_learned"] = int(spec.get("spellbook_learned", 0)) + 1  # 주문서 크기에 더한다(생성기)
	_save_spec(c)
	Dice.log_text("%s: 주문서에 %s를 적었다(%dgp)" % [c.label(), RulesDB.get_entry("spell", sid)["name"]["en"], learn_cost(sid)])
	return {"ok": true, "spell": sid}


## 반응 주문(cast.cost reaction)은 준비했을 때만 반응 목록에.
static func _sync_reactions(c: Node) -> void:
	var out: Array = []
	for rid: String in c.known_reactions:
		var sp := RulesDB.get_entry("spell", rid)
		if sp.is_empty() or rid in c.spells:
			out.append(rid)
	for sid: String in c.spells:
		if str(RulesDB.get_entry("spell", sid).get("cast", {}).get("cost", "")) == "reaction" and not sid in out:
			out.append(sid)
	c.known_reactions = out


## 고른 결과를 명세에 남긴다(레벨 업·불러오기 때 생성기가 다시 읽는다): 준비 주문을 앞에, 나머지는 뒤에.
static func _save_spec(c: Node) -> void:
	if not c.has_meta("spec"):
		return
	var spec: Dictionary = c.get_meta("spec")
	var rest: Array = spec.get("spells", []).filter(func(s: Variant) -> bool: return not str(s) in c.prepared)
	spec["spells"] = c.prepared.duplicate() + rest
	if prep_type(c) == "spellbook":
		spec["spellbook"] = c.spellbook.duplicate()
	c.set_meta("spec", spec)
