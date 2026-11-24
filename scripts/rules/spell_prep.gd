extends RefCounted
## 주문 준비·교체·주문서 학습(룰북 6단계 주문 시전·주문서, 7단계 휴식). 주문 이름·클래스 이름을 모른다.
## 클래스 데이터 spellcasting.type: prepared(클래스 주문 목록 전체에서 준비) · spellbook(주문서에서 준비) · 그 밖(바꾸지 않음).
## BG3식(2026-11-24): spellcasting.swap.out_of_combat이면 전투 밖에서 언제나 몇 개든 바꾼다(클레릭·드루이드·팔라딘·위저드).
##   준비 수 spellcasting.prepared = "level_plus_ability"면 클래스 레벨 + 시전 능력 수정치(최소 1), 표면 레벨 → 수(아는 주문형).
## 그 밖의 교체 창: 긴 휴식이 끝나면 열리고(spellcasting.swap.long_rest: -1 = 전부, n = n개), 다음 전투가 시작되면 닫힌다.
##   능력 태그 prepare_swap_short_rest(주문 암기)는 짧은 휴식 뒤 1개를 바꿀 수 있게 연다.
##   교체 수는 창이 열릴 때의 목록(prep_base)과 비교해 새로 넣은 주문 수로 센다(뺐다가 다시 넣으면 공짜).
## 주문서 학습(BG3식): 두루마리를 소모하고 주문 레벨 × 50gp, 시간 없음. 전투 밖, 준비할 수 있는 레벨까지만.
## 고른 결과는 명세(meta spec)의 spells·spellbook에도 남겨 레벨 업·불러오기 뒤에도 유지된다.

const GP_PER_LEVEL := 50


## 멀티클래스: 함수마다 cid(클래스)를 줄 수 있다. 안 주면 주 클래스. 준비·교체는 클래스마다(c.prepared_by_class),
## 교체 창(prep_swaps)은 하나를 함께 쓴다(가장 너그러운 클래스 기준 — 1차 단순화).
static func _cid(c: Node, cid: String) -> String:
	return cid if cid != "" else str(c.class_id)


static func _sc(c: Node, cid: String = "") -> Dictionary:
	return RulesDB.get_entry("class", _cid(c, cid)).get("spellcasting", {})


## 준비 주문을 바꾸는 클래스들(주 클래스 먼저).
static func prep_classes(c: Node) -> Array:
	var ids: Array = [str(c.class_id)]
	for k: String in c.class_levels:
		if not k in ids:
			ids.append(k)
	return ids.filter(func(k: String) -> bool: return prep_type(c, k) != "")


## prepared · spellbook · ""(교체 없음)
static func prep_type(c: Node, cid: String = "") -> String:
	var t := str(_sc(c, cid).get("type", ""))
	return t if t in ["prepared", "spellbook"] else ""


## 그 클래스가 준비할 수 있는 가장 높은 주문 레벨 = 그 클래스만 있는 것처럼(자기 표 — SRD 멀티클래스).
static func max_slot_level(c: Node, cid: String = "") -> int:
	var sc := _sc(c, cid)
	if not sc.is_empty() and not c.class_levels.is_empty():
		return sc.get("slots", {}).get(str(c.class_level(_cid(c, cid))), []).size()
	var best := 0
	for lv in range(1, 10):
		if c.resources.has("spell_slot_%d" % lv) and int(c.resources["spell_slot_%d" % lv]["max"]) > 0:
			best = lv
	return best


static func max_prepared(c: Node, cid: String = "") -> int:
	var sc := _sc(c, cid)
	return prepared_limit(sc, c.class_level(_cid(c, cid)), c.ability_mod(str(sc.get("ability", "int"))))


## 준비(아는) 주문 수: prepared = "level_plus_ability"면 클래스 레벨 + 능력 수정치(최소 1 — BG3), 표면 레벨 → 수.
static func prepared_limit(sc: Dictionary, lv: int, ability_mod: int) -> int:
	var table: Variant = sc.get("prepared", {})
	if typeof(table) == TYPE_STRING:
		return maxi(1, lv + ability_mod) if str(table) == "level_plus_ability" else 0
	var best := 0
	var best_lv := 0
	for k: String in (table as Dictionary):
		if lv >= int(k) and int(k) >= best_lv:
			best_lv = int(k)
			best = int(table[k])
	return best


## 전투 밖에서 언제나 바꾸는 클래스(swap.out_of_combat — BG3 준비형).
static func swaps_anytime(c: Node, cid: String = "") -> bool:
	return bool(_sc(c, cid).get("swap", {}).get("out_of_combat", false))


## 주문서 기본 크기(SRD: 1레벨 6개, 레벨마다 2개). 두루마리로 배운 것은 이 수에 상관없이 더한다.
static func spellbook_size(c: Node) -> int:
	var cid := _book_class(c)
	var sb: Dictionary = _sc(c, cid).get("spellbook", {})
	if sb.is_empty():
		return 0
	return int(sb.get("1", 6)) + int(sb.get("per_level", 2)) * (c.class_level(cid) - 1)


## 주문서를 쓰는 클래스(없으면 "").
static func _book_class(c: Node) -> String:
	for k: String in [str(c.class_id)] + c.class_levels.keys():
		if prep_type(c, k) == "spellbook":
			return k
	return ""


## 그 클래스가 지금 준비한 주문.
static func prepared_of(c: Node, cid: String = "") -> Array:
	var k := _cid(c, cid)
	return c.prepared_by_class.get(k, c.prepared if k == str(c.class_id) else [])


## 준비할 수 있는 주문(1레벨 이상, 그 클래스가 준비할 수 있는 레벨 이하, 고정 주문 제외).
static func pool(c: Node, cid: String = "") -> Array:
	var t := prep_type(c, cid)
	if t == "":
		return []
	var top := max_slot_level(c, cid)
	var source: Array = []
	if t == "spellbook":
		source = c.spellbook
	else:
		var lists: Array = [str(_sc(c, cid).get("list", ""))]
		var ccid := _cid(c, cid)
		lists.append_array(load("res://scripts/rules/character_builder.gd").extra_lists(RulesDB.get_entry("class", ccid), c.class_level(ccid)))
		for sp: Dictionary in RulesDB.entries("spell"):
			if lists.any(func(l: String) -> bool: return l in sp.get("classes", [])) and str(sp.get("game_status", "")) == "included":
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
static func change_blocked(world: Dictionary, c: Node, cid: String = "") -> String:
	if prep_type(c, cid) == "":
		return "준비 주문을 바꾸지 않는 클래스"
	if in_combat(world):
		return "전투 중에는 바꿀 수 없다"
	if swaps_anytime(c, cid):
		return ""
	if c.prep_swaps == 0 and prepared_of(c, cid).size() < max_prepared(c, cid):
		return ""  # 빈 칸 채우기는 언제나(전투 밖) — 교체 수는 set_prepared가 센다
	if c.prep_swaps == 0:
		return "긴 휴식 뒤에 바꿀 수 있다"
	return ""


## 창이 열린 뒤 그 클래스에서 바꾼 주문 수: 새로 넣은 주문 수에서 창이 열릴 때 비어 있던 준비 칸 수를 뺀다(빈 칸 채우기는 공짜).
static func changes(c: Node, list: Array, cid: String = "") -> int:
	var k := _cid(c, cid)
	var base: Array = c.prep_base.filter(func(sid: String) -> bool: return str(c.spell_class.get(sid, c.class_id)) == k)
	var added := list.filter(func(sid: String) -> bool: return not sid in base).size()
	return maxi(0, added - maxi(0, max_prepared(c, k) - base.size()))


## 남은 교체 수(-1 = 제한 없음).
static func swaps_left(c: Node, cid: String = "") -> int:
	if c.prep_swaps < 0 or (cid != "" and swaps_anytime(c, cid)):
		return -1
	var used := 0
	for k: String in prep_classes(c):
		if not swaps_anytime(c, k):
			used += changes(c, prepared_of(c, k), k)
	return maxi(0, c.prep_swaps - used)


## 그 클래스의 준비 목록을 통째로 바꾼다. 결과 {"ok", "reason"}.
static func set_prepared(world: Dictionary, c: Node, list: Array, cid: String = "") -> Dictionary:
	var k := _cid(c, cid)
	var why := change_blocked(world, c, k)
	if why != "":
		return {"ok": false, "reason": why}
	var uniq: Array = []
	for sid: Variant in list:
		if not str(sid) in uniq:
			uniq.append(str(sid))
	var p := pool(c, k)
	var old: Array = prepared_of(c, k)
	for sid: String in uniq:
		if not sid in p and not sid in old:
			return {"ok": false, "reason": "준비할 수 없는 주문: %s" % sid}
	if uniq.size() > max_prepared(c, k):
		return {"ok": false, "reason": "준비 수 초과(%d)" % max_prepared(c, k)}
	if c.prep_swaps >= 0 and not swaps_anytime(c, k):
		var used := changes(c, uniq, k)
		for other: String in prep_classes(c):
			if other != k and not swaps_anytime(c, other):
				used += changes(c, prepared_of(c, other), other)
		if used > c.prep_swaps:
			return {"ok": false, "reason": "이번에 바꿀 수 있는 주문은 %d개" % c.prep_swaps}
	var kept: Array = c.spells.filter(func(sid: String) -> bool: return not sid in old)
	c.spells = kept + uniq
	c.prepared_by_class[k] = uniq
	for sid: String in uniq:
		c.spell_class[sid] = k
	var all: Array = []
	for kk: String in c.prepared_by_class:
		for sid: String in c.prepared_by_class[kk]:
			if not sid in all:
				all.append(sid)
	c.prepared = all
	_sync_reactions(c)
	_save_spec(c)
	return {"ok": true}


## 한 주문을 준비하거나 뺀다(화면의 토글). 클래스를 안 주면 그 주문을 준비한 클래스 → 준비할 수 있는 첫 클래스.
static func toggle(world: Dictionary, c: Node, sid: String, cid: String = "") -> Dictionary:
	var k := cid
	if k == "":
		for kk: String in prep_classes(c):
			if sid in prepared_of(c, kk):
				k = kk
				break
	if k == "":
		for kk: String in prep_classes(c):
			if sid in pool(c, kk):
				k = kk
				break
	k = _cid(c, k)
	var list: Array = prepared_of(c, k).duplicate()
	if sid in list:
		list.erase(sid)
	else:
		list.append(sid)
	return set_prepared(world, c, list, k)


## 교체 창을 연다. kind: "long"(긴 휴식 — swap.long_rest, 기본 -1) · "short"(짧은 휴식 — 주문 암기 태그면 1)
## · "level_up"(레벨 업 — swap.level_up, 기본 0: 바드·소서러·워락식 레벨마다 1개). 멀티클래스면 가장 너그러운 클래스 값.
static func open_window(c: Node, kind: String) -> void:
	var ks := prep_classes(c)
	if ks.is_empty():
		return
	var n := 0
	for k: String in ks:
		var swap: Dictionary = _sc(c, k).get("swap", {})
		var v := 0
		match kind:
			"long":
				v = int(swap.get("long_rest", -1))
			"short":
				v = 1 if c.has_cap("prepare_swap_short_rest") else 0
			"level_up":
				v = int(swap.get("level_up", 0))
		if v < 0 or n < 0:
			n = -1
		else:
			n = maxi(n, v)
	if n == 0 or c.prep_swaps < 0:
		return  # 열 것이 없거나 이미 전부 바꿀 수 있다
	c.prep_swaps = n
	c.prep_base = c.prepared.duplicate()


## 전투가 시작되면 창을 닫는다.
static func close_window(c: Node) -> void:
	c.prep_swaps = 0
	c.prep_base = c.prepared.duplicate()


# ---------- 주문서 학습(두루마리) ----------

static func learn_cost(sid: String, c: Node = null) -> int:
	var sp := RulesDB.get_entry("spell", sid)
	var per := GP_PER_LEVEL
	if c != null and str(sp.get("school", "")) in c.get_meta("scribe_discount", []):
		per = GP_PER_LEVEL / 2  # 학파 위저드(BG3): 자기 학파 주문은 절반(25gp)
	return per * int(sp.get("level", 0))


## 두루마리에서 배울 수 없는 이유("" = 가능).
static func learn_blocked(world: Dictionary, c: Node, item_id: String) -> String:
	var item := RulesDB.get_entry("item", item_id)
	var sid := str(item.get("spell", ""))
	var sp := RulesDB.get_entry("spell", sid)
	var book := _book_class(c)
	if book == "":
		return "주문서가 없다"
	if item.get("category", "") != "scroll" or sp.is_empty():
		return "주문 두루마리가 아니다"
	if int(c.inventory.get(item_id, 0)) <= 0:
		return "두루마리가 없다"
	if not str(_sc(c, book).get("list", "")) in sp.get("classes", []):
		return "내 클래스 주문 목록에 없는 주문"
	if int(sp.get("level", 0)) < 1:
		return "소마법은 주문서에 적지 않는다"
	if int(sp["level"]) > max_slot_level(c, book):
		return "아직 준비할 수 없는 레벨"
	if sid in c.spellbook:
		return "이미 주문서에 있다"
	if in_combat(world):
		return "전투 중에는 적을 수 없다"
	if int(c.inventory.get("gold", 0)) < learn_cost(sid, c):
		return "금화가 모자라다(%dgp)" % learn_cost(sid, c)
	return ""


static func learn_from_scroll(world: Dictionary, c: Node, item_id: String) -> Dictionary:
	var why := learn_blocked(world, c, item_id)
	if why != "":
		return {"ok": false, "reason": why}
	var sid := str(RulesDB.get_entry("item", item_id)["spell"])
	var inv: Dictionary = c.inventory  # 배우는 캐릭터의 두루마리·금화(BG3식 캐릭터별)
	inv["gold"] = int(inv["gold"]) - learn_cost(sid, c)
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
	Dice.log_text("%s: 주문서에 %s를 적었다(%dgp)" % [c.label(), RulesDB.get_entry("spell", sid)["name"]["en"], learn_cost(sid, c)])
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


## 고른 결과를 명세에 남긴다(레벨 업·불러오기 때 생성기가 다시 읽는다): 클래스마다 준비 주문을 앞에, 나머지는 뒤에.
## 주 클래스는 명세 spells·spellbook, 다른 클래스는 명세 classes 항목의 spells.
static func _save_spec(c: Node) -> void:
	if not c.has_meta("spec"):
		return
	var spec: Dictionary = c.get_meta("spec")
	for k: String in prep_classes(c):
		var src: Dictionary = spec
		if k != str(c.class_id):
			for e: Dictionary in spec.get("classes", []):
				if str(e.get("class", "")) == k:
					src = e
		var prep: Array = prepared_of(c, k)
		var rest: Array = src.get("spells", []).filter(func(s: Variant) -> bool: return not str(s) in prep)
		src["spells"] = prep.duplicate() + rest
		if prep_type(c, k) == "spellbook":
			src["spellbook"] = c.spellbook.duplicate()
	c.set_meta("spec", spec)
