extends SceneTree
## 콘텐츠 현황 보고서: docs/content_status.md를 데이터에서 새로 만든다(손으로 고치지 않는다).
## 실행: godot --headless --path . -s res://tools/content_report.gd
## 클래스 기능마다 동작 장치(스크립트·태그·부여·고르기·설정) 또는 '설명만'(동작 없음), 주문 상태·스크립트 구현 여부·아이콘, 아이템·출신 수.

const OUT := "res://docs/content_status.md"
var _done := false


func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	var db: Node = root.get_node("RulesDB")
	var lines := PackedStringArray()
	lines.append("# 콘텐츠 현황")
	lines.append("")
	lines.append("> `tools/content_report.gd`가 데이터에서 만든다(손으로 고치지 않는다). 레벨 상한 %d(data/rules/progression.json)." % int(db.get_entry("progression", "standard").get("level_cap", 5)))
	lines.append("")
	# 요약
	lines.append("## 요약")
	lines.append("")
	lines.append("| 종류 | 수 |")
	lines.append("| --- | --- |")
	for kind: String in ["class", "spell", "weapon", "armor", "item", "feat", "species", "background", "monster", "capability", "terrain_preset", "map"]:
		lines.append("| %s | %d |" % [kind, db.ids(kind).size()])
	lines.append("")
	# 클래스
	lines.append("## 클래스 기능")
	lines.append("")
	lines.append("동작 장치: `스크립트`(effects/<id>.gd), `태그`(caps → 엔진 메커니즘), `부여`(grants), `고르기`(choice_kind), `설정`(toggle), `반응`(kind reaction).")
	lines.append("**설명만** = 데이터에 설명은 있으나 엔진이 이 기능으로 하는 일이 없다(생성기가 명세로 처리하는 무기 마스터리·전문화 등 포함) — 새 기능이면 장치를 달아야 한다.")
	lines.append("")
	var effects_dir := "res://scripts/rules/effects/%s.gd"
	for cid: String in db.ids("class"):
		var cls: Dictionary = db.get_entry("class", cid)
		lines.append("### %s (%s) — 생명 주사위 d%d, 역할 %s" % [cls["name"]["ko"], cid, int(cls["hit_die"]), cls.get("ai_role", "-")])
		lines.append("")
		lines.append("| 레벨 | 기능 | 하위 | 장치 | 상태 |")
		lines.append("| --- | --- | --- | --- | --- |")
		var rows: Array = []
		for f: Dictionary in cls.get("features", []):
			rows.append([f, ""])
		for sc: Dictionary in cls.get("subclasses", []):
			for f: Dictionary in sc.get("features", []):
				rows.append([f, sc["id"]])
		rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0].get("level", 1)) < int(b[0].get("level", 1)))
		for r: Array in rows:
			var f: Dictionary = r[0]
			var how := PackedStringArray()
			if f.has("script"):
				var path := effects_dir % f["script"]
				var ok := ResourceLoader.exists(path)
				if ok:
					var inst: Object = load(path).new()
					ok = inst.has_method("is_implemented") and inst.is_implemented()
				how.append("스크립트 %s%s" % [f["script"], "" if ok else " **(미구현)**"])
			if not f.get("caps", []).is_empty():
				how.append("태그 " + ", ".join(PackedStringArray(f["caps"])))
			if f.has("grants"):
				how.append("부여 " + ", ".join(PackedStringArray(f["grants"].keys())))
			if f.has("choice_kind"):
				how.append("고르기(%s)" % f["choice_kind"])
			if f.has("toggle"):
				how.append("설정")
			if str(f.get("kind", "")) == "reaction":
				how.append("반응")
			if f.has("handled_by"):
				how.append("처리: " + str(f["handled_by"]))
			var status := "보류(deferred)" if str(f.get("status", "")) == "deferred" else ("" if not how.is_empty() else "**설명만**")
			lines.append("| %d | %s (%s) | %s | %s | %s |" % [int(f.get("level", 1)), f["name"].get("ko", f["id"]), f["id"], r[1], "; ".join(how), status])
		lines.append("")
	# 주문
	lines.append("## 주문")
	lines.append("")
	var by_status := {}
	var scripted := 0
	var unimpl := PackedStringArray()
	var no_icon := PackedStringArray()
	var by_level := {}
	for sid: String in db.ids("spell"):
		var sp: Dictionary = db.get_entry("spell", sid)
		var st := str(sp.get("game_status", "included"))
		by_status[st] = by_status.get(st, 0) + 1
		if st == "included":
			by_level[int(sp["level"])] = by_level.get(int(sp["level"]), 0) + 1
			if not sp.has("icon"):
				no_icon.append(sid)
		if sp.has("script"):
			scripted += 1
			var path := effects_dir % sp["script"]
			var ok := ResourceLoader.exists(path)
			if ok:
				var inst: Object = load(path).new()
				ok = inst.has_method("is_implemented") and inst.is_implemented()
			if not ok and st == "included":
				unimpl.append(sid)
	lines.append("- 상태: " + ", ".join(PackedStringArray(by_status.keys().map(func(k: String) -> String: return "%s %d" % [k, by_status[k]]))))
	lines.append("- 포함 주문 레벨별: " + ", ".join(PackedStringArray(by_level.keys().map(func(k: int) -> String: return "%d레벨 %d" % [k, by_level[k]]))))
	lines.append("- 스크립트 주문 %d개, 그중 포함인데 미구현: %s" % [scripted, ", ".join(unimpl) if not unimpl.is_empty() else "없음"])
	lines.append("- 아이콘(icon) 없는 포함 주문(학파 색 별로 표시): %s" % (", ".join(no_icon) if not no_icon.is_empty() else "없음"))
	var lists := {}
	for sid: String in db.ids("spell"):
		for cl: Variant in db.get_entry("spell", sid).get("classes", []):
			lists[str(cl)] = lists.get(str(cl), 0) + 1
	lines.append("- 클래스 주문 목록: " + ", ".join(PackedStringArray(lists.keys().map(func(k: String) -> String: return "%s %d" % [k, lists[k]]))))
	lines.append("")
	# 아이템
	lines.append("## 아이템")
	lines.append("")
	var cats := {}
	for iid: String in db.ids("item"):
		var c := str(db.get_entry("item", iid).get("category", ""))
		cats[c] = cats.get(c, 0) + 1
	lines.append("- 분류: " + ", ".join(PackedStringArray(cats.keys().map(func(k: String) -> String: return "%s %d" % [k, cats[k]]))))
	lines.append("- 동작하는 분류: potion(마시기·먹이기·던지기), scroll(두루마리 읽기), food(캠프 보급품), tool(자물쇠·함정). **magic(장착 효과)은 아직 동작 없음** — 장비 칸 설계가 먼저 필요")
	lines.append("")
	lines.append("## 능력 태그 사용")
	lines.append("")
	var used := {}
	for cid: String in db.ids("class"):
		var cls: Dictionary = db.get_entry("class", cid)
		var feats: Array = cls.get("features", []).duplicate()
		for sc: Dictionary in cls.get("subclasses", []):
			feats.append_array(sc.get("features", []))
		for f: Dictionary in feats:
			for cap: Variant in f.get("caps", []) + f.get("grants", {}).get("caps", []):
				used[str(cap)] = used.get(str(cap), PackedStringArray()) + PackedStringArray([cid])
	for fid: String in db.ids("feat"):
		for cap: Variant in db.get_entry("feat", fid).get("tags", []):
			used[str(cap)] = used.get(str(cap), PackedStringArray()) + PackedStringArray(["재주 " + fid])
	for sid: String in db.ids("species"):
		for f: Dictionary in db.get_entry("species", sid).get("features", []):
			for cap: Variant in f.get("caps", []):
				used[str(cap)] = used.get(str(cap), PackedStringArray()) + PackedStringArray(["종족 " + sid])
	lines.append("| 태그 | 이름 | 쓰는 곳 |")
	lines.append("| --- | --- | --- |")
	for cap: String in db.ids("capability"):
		var e: Dictionary = db.get_entry("capability", cap)
		lines.append("| %s | %s | %s |" % [cap, e["name"]["ko"], ", ".join(used.get(cap, PackedStringArray(["(몬스터 특성 또는 아직 없음)"])))])
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("썼다: ", OUT)
	quit()
	return true
