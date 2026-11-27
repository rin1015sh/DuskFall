extends "res://tests/test_case.gd"
## 도트 화면(scenes/battle/pixel_view.gd): 카메라 픽셀 맞춤·팔레트 색 공간. 표현 계층이지만 계산은 순수 함수라 헤드리스로 본다.

const PixelView := preload("res://scenes/battle/pixel_view.gd")
const V := preload("res://scenes/battle/view3d.gd")


## 맞춘 카메라가 격자 위에 있고, 옮긴 거리는 반 도트 이하, 깊이(앞뒤)는 그대로.
func test_snap_on_grid() -> void:
	var step := 3.0 / 64.0
	for target: Vector3 in [Vector3(10.3, 0, 7.77), Vector3(-4.01, 2, 3.5), Vector3(0.017, 1, 0.9)]:
		var xf := V.camera_transform(target)
		var sn: Dictionary = PixelView.snap(xf, step)
		var o: Vector3 = (sn["xform"] as Transform3D).origin
		assert_true(absf(sn["da"]) <= step * 0.5 + 1e-6 and absf(sn["db"]) <= step * 0.5 + 1e-6, "반 도트 이하로 옮김")
		var fa := o.dot(xf.basis.x) / step
		var fb := o.dot(xf.basis.y) / step
		assert_true(absf(fa - roundf(fa)) < 1e-3 and absf(fb - roundf(fb)) < 1e-3, "격자 위 %s" % str(target))
		assert_true(absf(o.dot(xf.basis.z) - xf.origin.dot(xf.basis.z)) < 1e-3, "깊이 축은 그대로")


## 한 도트만큼 카메라를 옮기면 격자 번호가 정확히 1 바뀐다(바닥 도트가 미끄러지지 않고 한 칸씩 넘어감).
func test_snap_one_dot_steps() -> void:
	var step := 2.0 / 64.0
	var xf := V.camera_transform(Vector3(5.2, 0, 5.2))
	var moved := Transform3D(xf.basis, xf.origin + xf.basis.x * step)
	assert_eq(int(PixelView.snap(moved, step)["ia"]) - int(PixelView.snap(xf, step)["ia"]), 1)


func test_oklab_reference() -> void:
	var w := PixelView.oklab(Color(1, 1, 1))
	assert_true(absf(w.x - 1.0) < 1e-3 and absf(w.y) < 1e-3 and absf(w.z) < 1e-3, "흰색 = L 1")
	var k := PixelView.oklab(Color(0, 0, 0))
	assert_true(absf(k.x) < 1e-6, "검정 = L 0")


## 팔레트 그림이 있고 셰이더 배열(128색)에 들어간다.
func test_palette_fits() -> void:
	var tex: Texture2D = load(PixelView.PALETTE_PATH)
	assert_true(tex != null, "팔레트 그림")
	if tex != null:
		assert_true(tex.get_width() >= 16 and tex.get_width() <= PixelView.PAL_MAX, "16~128색: %d" % tex.get_width())


## 도트 그림 폴더: 같은 이름 시트가 있으면 그것을, 없으면 원본을 쓴다(크기는 같아 그림 좌표 그대로).
func test_kit_art_dir_swap() -> void:
	var DungeonKit := preload("res://scenes/kit/dungeon_kit.gd")
	var before := DungeonKit.art_dir
	DungeonKit.art_dir = "res://assets/pixel_kit"
	var kit: RefCounted = DungeonKit.open()
	var t: Texture2D = kit._sheet("floors")
	assert_true(t != null and t.resource_path.begins_with("res://assets/pixel_kit"), "도트 시트")
	DungeonKit.art_dir = "res://no_such_dir"
	var kit2: RefCounted = DungeonKit.open()
	var t2: Texture2D = kit2._sheet("floors")
	assert_true(t2 != null and t2.resource_path.begins_with("res://assets/dungeon_kit"), "없으면 원본")
	if t != null and t2 != null:
		assert_eq(t.get_size(), t2.get_size(), "같은 크기")
	DungeonKit.art_dir = before


## 흩뿌림 장식 키트(assets/pixel_decor — tools/make_decor.py): 기본표가 쓰는 장식이 다 있고 조각이 시트 안에 있다.
func test_decor_kit() -> void:
	var DungeonKit := preload("res://scenes/kit/dungeon_kit.gd")
	var MapView := preload("res://scenes/battle/map_view.gd")
	var dk: RefCounted = DungeonKit.open(MapView.DECOR_KIT)
	assert_false(dk.data.is_empty(), "장식 키트")
	var size: Array = dk.data["sheets"]["decor"]["size"]
	for fid: String in MapView.SCATTER:
		for e: Array in MapView.SCATTER[fid][1]:
			assert_true(dk.has(String(e[0])), "%s의 장식 %s" % [fid, e[0]])
	for id: String in dk.data["assets"]:
		for vn: String in dk.variants(id):
			for f: Array in dk._frames(id, vn):
				assert_true(f[0] + f[2] <= size[0] and f[1] + f[3] <= size[1], "%s.%s 조각이 시트 안" % [id, vn])


func test_scatter_pick_weighted() -> void:
	var MapView := preload("res://scenes/battle/map_view.gd")
	var rows := [["a", 1.0], ["b", 3.0]]
	assert_eq(MapView._pick_weighted(rows, 0.1), "a")
	assert_eq(MapView._pick_weighted(rows, 0.5), "b")
	assert_eq(MapView._pick_weighted(rows, 0.999), "b")


## 맵 둘레: 놀이 영역 안은 거리 0·밝기 1, 바깥 끝으로 갈수록 어두워진다.
func test_surround_fade() -> void:
	var MapView := preload("res://scenes/battle/map_view.gd")
	var play := Rect2(1, 1, 10, 8)
	assert_eq(MapView._out_dist(Vector2(5, 5), play), 0.0, "안쪽")
	assert_true(absf(MapView._out_dist(Vector2(-2, 5), play) - 3.0) < 1e-5, "서쪽 3칸")
	assert_eq(MapView._surround_fade(Vector2(5, 5), play, 16), 1.0)
	assert_eq(MapView._surround_fade(Vector2(-5, 5), play, 16), 1.0, "가까운 둘레는 밝기 그대로")
	var far := MapView._surround_fade(Vector2(-14, 5), play, 16)
	assert_true(far < 1.0 and far >= 0.55, "먼 둘레만 살짝 어둡게(검게 사라지지 않음): %f" % far)
	var kit: RefCounted = preload("res://scenes/kit/dungeon_kit.gd").open()
	for b: String in MapView.SURROUND_BIOMES:
		var bio: Dictionary = MapView.SURROUND_BIOMES[b]
		for f: String in ["floor", "patch"]:
			if String(bio[f]) != "":
				assert_true(kit.has(String(bio[f])), "%s %s 바닥 %s" % [b, f, bio[f]])
		for list: String in ["wall", "low", "far"]:
			for row: Array in bio[list]:
				assert_true(kit.has(String(row[0])), "%s.%s 그림 %s" % [b, list, row[0]])
				if row[2] is Array:
					for v: String in row[2]:
						assert_true(kit.variants(String(row[0])).has(v), "%s.%s" % [row[0], v])


## 바람: 흔들 그림이 키트에 있고, 켜면 흔들림 재질이 붙고 꺼져 있으면 안 붙는다.
func test_wind_sway() -> void:
	var Kit3D := preload("res://scenes/kit/kit3d.gd")
	var DungeonKit := preload("res://scenes/kit/dungeon_kit.gd")
	var kit: RefCounted = DungeonKit.open()
	var dk: RefCounted = DungeonKit.open(preload("res://scenes/battle/map_view.gd").DECOR_KIT)
	for id: String in Kit3D.SWAY:
		assert_true(kit.has(id) or dk.has(id), "흔들 그림 %s" % id)
	var before := Kit3D.wind
	Kit3D.wind = true
	var n: Node3D = Kit3D.make(kit, "bush", "a")
	var sp: Variant = n.get_meta("sprite", null)
	assert_true(sp is Sprite3D and (sp as Sprite3D).material_override is ShaderMaterial, "흔들림 재질")
	n.free()
	Kit3D.wind = false
	var n2: Node3D = Kit3D.make(kit, "bush", "a")
	var sp2: Variant = n2.get_meta("sprite", null)
	assert_true(sp2 is Sprite3D and (sp2 as Sprite3D).material_override == null, "바람 끄면 없음")
	n2.free()
	Kit3D.wind = before


## 폐허 벽: 높이 배율은 0.3~1(무너진 홈 포함), 칸마다 같은 값(매번 같은 모양), 윗면 그림이 있다.
func test_ruin_wall_heights() -> void:
	var MapView := preload("res://scenes/battle/map_view.gd")
	var mv: Node = MapView.new()
	var lo := 9.0
	var hi := 0.0
	for y in 20:
		for x in 30:
			var f: float = mv._ruin_f(Vector2i(x, y))
			lo = minf(lo, f)
			hi = maxf(hi, f)
			assert_eq(f, mv._ruin_f(Vector2i(x, y)), "같은 칸은 같은 높이")
	assert_true(lo >= 0.3 and hi <= 1.0, "범위 %f~%f" % [lo, hi])
	assert_true(hi - lo > 0.3, "들쭉날쭉")
	mv.free()
	var tex: Texture2D = load(MapView.RUIN_TOP_TEX)
	assert_true(tex != null and tex.get_width() == 2 * 64, "윗돌 재질(돌·이끼 2칸)")


## 맵 안 숲(hill_path): 맵 안 나무 소품 칸은 통행 막힘(impassable) — 그림과 규칙이 맞는다.
func test_hill_path_trees_block() -> void:
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/hill_path.json"))
	var blocked := {}
	for f: Dictionary in m.get("flags", []):
		if "impassable" in f["flags"] or "wall" in f["flags"]:
			blocked[Vector2i(int(f["cell"][0]), int(f["cell"][1]))] = true
	var rows: Array = m["rows"]
	var n := 0
	for p: Dictionary in m["art"]["props"]:
		var c := Vector2i(int(p["at"][0]), int(p["at"][1]))
		var inner: bool = c.x > 0 and c.y > 0 and c.x < String(rows[0]).length() - 1 and c.y < rows.size() - 1
		if String(p["id"]).begins_with("tree") and inner and String(rows[c.y])[c.x] != "#" and not (c in [Vector2i(13, 12)]):
			n += 1
			assert_true(blocked.has(c), "나무 칸 %s 막힘" % str(c))
	assert_true(n >= 6, "맵 안 나무 무리 %d" % n)


## 캐릭터 도트 그림: 뼈대를 도트 배율로 줄여 그린다(캔버스·크기), 장비 부위는 그대로 붙는다.
func test_cutout_pixel_rig() -> void:
	var Rig := preload("res://scenes/battle/cutout_rig.gd")
	var rig: Node2D = Rig.new()
	rig.dot = 0.28
	rig.apply_look({"template": "medium", "key": "t1", "armor": {"shape": "chain", "color": "#8a8f96"}, "weapon": {"shape": "sword", "length": 40}, "helmet": true, "cloak": true})
	assert_eq(rig.canvas_px(), Vector2i(ceili(160 * 0.28), ceili(240 * 0.28)), "도트 캔버스")
	assert_true(absf(rig.scale.y - 0.28) < 1e-6, "뼈대 배율 = 도트 배율")
	var ids := []
	for p: Node in rig._parts:
		ids.append(String(p.get_meta("part_id")))
	for want: String in ["torso", "head", "weapon", "helmet", "cloak"]:
		assert_true(want in ids, "장비·부위 %s" % want)
	rig.set_facing(1)
	assert_true(rig.scale.x < 0.0 and absf(absf(rig.scale.x) - 0.28) < 1e-6, "왼쪽은 좌우 반전(배율 유지)")
	rig.free()


## 몬스터 도트 그림: 그림 쓰는 몬스터마다 변환본이 있고 도트 키 = 42 × 크기 배율.
func test_pixel_actor_art() -> void:
	var size_k := {"tiny": 0.5, "small": 0.8, "medium": 1.0, "large": 1.7, "huge": 2.4}
	var want := {}
	for f: String in DirAccess.get_files_at("res://data/monsters"):
		if not f.ends_with(".json"):
			continue
		var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters/" + f))
		var img := String(m.get("art", {}).get("image", ""))
		if img != "":
			want[img] = maxf(float(want.get(img, 0.0)), float(size_k.get(m.get("size", "medium"), 1.0)))
	assert_true(want.size() > 0)
	for img: String in want:
		var alt := "res://assets/pixel_actors/" + img.get_file().get_basename() + ".webp"
		assert_true(ResourceLoader.exists(alt), "변환본 %s" % alt)
		if ResourceLoader.exists(alt):
			var t: Texture2D = load(alt)
			assert_eq(t.get_height(), roundi(42.0 * float(want[img])), "%s 도트 키" % alt)

