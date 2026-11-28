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
	# 잎 덩어리: 덤불·나무는 조각 자리·덩어리 크기를 받는다
	var mat := (sp as Sprite3D).material_override as ShaderMaterial
	assert_true(float(mat.get_shader_parameter("leaf")) > 0.0, "잎 덩어리 켜짐")
	var fr: Vector4 = mat.get_shader_parameter("frame_rect")
	assert_true(fr.z > 1.0 and fr.w > 1.0, "조각 크기")
	assert_true(float(mat.get_shader_parameter("clump_px")) >= 18.0, "큰 덩어리")
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


## 몬스터 도트 그림: 그림 쓰는 몬스터마다 변환본이 있고 키 = 84 × 크기 배율(지형 도트보다 2배 촘촘).
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
			assert_eq(t.get_height(), roundi(84.0 * float(want[img])), "%s 키" % alt)



## 도트 화면 확대 단계: 그림 1도트가 화면 정수 칸(1·2·3·4px)이 되는 단계로 끊는다.
func test_zoom_steps() -> void:
	var PixelView := preload("res://scenes/battle/pixel_view.gd")
	for z: float in PixelView.ZOOM_STEPS:
		var px := PixelView.DOTS_PX * z
		assert_true(absf(px - roundf(px)) < 1e-6 and px >= 1.0, "단계 %.2f → 그림 1도트 %.1fpx(정수)" % [z, px])
	assert_eq(PixelView.snap_zoom(0.92), 1.0, "기본 확대 0.92 → 1")
	assert_eq(PixelView.snap_zoom(1.3), 1.5)
	assert_eq(PixelView.snap_zoom(0.45), 0.5)
	assert_eq(PixelView.snap_zoom(2.2), 2.0)


## 빛과 그림자 층: 광원 이름으로 빛 색(불 = 주황, 빛남·달 = 청백), 빛 판 셰이더가 있다.
func test_light_colors() -> void:
	var MapView := preload("res://scenes/battle/map_view.gd")
	var mv: Node = MapView.new()
	var fire: Color = mv._light_color("camp_fire")
	var glow: Color = mv._light_color("cave_glow")
	assert_true(fire.r > fire.b + 0.4, "불빛은 따뜻하게")
	assert_true(glow.b > glow.r + 0.2, "동굴 빛은 차갑게")
	mv.free()
	assert_true(ResourceLoader.exists("res://scenes/battle/pixel_light.gdshader"))


## 외곽선: 검은 선 대신 제 색을 어둡게(곱하기 sel-out), 빛을 내는 물건은 외곽선 없음, 몬스터 도트 그림은 테두리를 굽지 않는다.
func test_outline_selout() -> void:
	var sh: Shader = load("res://scenes/battle/pixel_outline.gdshader")
	assert_true(sh.code.contains("blend_mul"), "외곽선은 곱하기")
	var Kit3D := preload("res://scenes/kit/kit3d.gd")
	for id: String in ["firepit", "brazier", "torch_wall", "candles", "lantern"]:
		assert_true(Kit3D.GLOWING.has(id), "%s 외곽선 없음" % id)
	# 몬스터 변환본: 윤곽 바깥 1화소에 어두운 테를 굽지 않았다 — 가장자리 화소 평균이 안쪽보다 아주 어둡지 않다
	var img: Image = (load("res://assets/pixel_actors/goblin.webp") as Texture2D).get_image()
	img.decompress()
	var edge := 0.0
	var inner := 0.0
	var ne := 0
	var ni := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var border := false
			for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q := Vector2i(x, y) + o
				if q.x < 0 or q.y < 0 or q.x >= img.get_width() or q.y >= img.get_height() or img.get_pixelv(q).a < 0.5:
					border = true
			if border:
				edge += c.get_luminance()
				ne += 1
			else:
				inner += c.get_luminance()
				ni += 1
	assert_true(ne > 0 and ni > 0)
	assert_true(edge / ne > inner / ni * 0.6, "굽은 검은 테 없음(가장자리 %.2f, 안 %.2f)" % [edge / ne, inner / ni])


## 물 반사: 거울 카메라 자세(물 높이에 뒤집은 위치·위를 보는 방향, 오른손 좌표 그대로), 표면 반사 세기, 층 비트가 겹치지 않는다.
func test_water_reflection() -> void:
	var PixelView := preload("res://scenes/battle/pixel_view.gd")
	var MapView := preload("res://scenes/battle/map_view.gd")
	var pitch := 0.8956648938
	var xf := Transform3D(Basis(Vector3.RIGHT, -pitch), Vector3(3.0, 20.0, 30.0))
	var m: Transform3D = PixelView.mirror_xform(xf, 1.5)
	assert_near(m.origin.y, 2.0 * 1.5 - 20.0, 1e-5, "위치는 거울상")
	assert_near(m.origin.x, 3.0, 1e-5)
	assert_near(m.origin.z, 30.0, 1e-5)
	var f_main := -xf.basis.z
	var f_m := -m.basis.z
	assert_true(f_main.y < 0.0 and f_m.y > 0.0, "도트 카메라는 내려다보고 거울 카메라는 올려다본다")
	assert_near(f_m.z, f_main.z, 1e-5, "북쪽으로 보는 성분은 같다")
	assert_near(m.basis.determinant(), 1.0, 1e-5, "회전만(뒤집기 없음 — 면 방향이 바뀌지 않게)")
	assert_eq(PixelView.MAIN_MASK & PixelView.REFL_LAYER, 0, "도트 카메라는 거울 전용 층을 안 본다")
	assert_eq(PixelView.REFL_MASK & (PixelView.WATER_LAYER | PixelView.MAIN_ONLY_LAYER | PixelView.OUTLINE_LAYER), 0, "거울 카메라는 물·원본·외곽선을 안 본다")
	assert_true(PixelView.MAIN_MASK & PixelView.WATER_LAYER != 0 and PixelView.MAIN_MASK & PixelView.MAIN_ONLY_LAYER != 0)
	assert_true(MapView.SURFACE_REFLECT.has("water") and not MapView.SURFACE_REFLECT.has("mud"), "물은 비치고 진흙은 안 비친다")
	var sh: Shader = load("res://scenes/battle/overlay.gdshader")
	assert_true(sh.code.contains("refl_mat") and sh.code.contains("shadow_tex") and sh.code.contains("glow_tex"), "물 셰이더 층: 반사·그림자·빛")


## 잎 방식: 넓은 잎·바늘잎·단풍(+0.5)·눈 덮임·죽은 나무는 원래 그림
func test_leaf_modes() -> void:
	var Kit3D := preload("res://scenes/kit/kit3d.gd")
	assert_eq(Kit3D.leaf_mode("tree_broadleaf", "a"), 1.0)
	assert_eq(Kit3D.leaf_mode("tree_broadleaf", "autumn"), 1.5)
	assert_eq(Kit3D.leaf_mode("tree_pine", "a"), 2.0)
	assert_eq(Kit3D.leaf_mode("tree_pine", "snowy"), 0.0)
	assert_eq(Kit3D.leaf_mode("tree_pine", "dead"), 0.0)
	assert_eq(Kit3D.leaf_mode("bush", "dry"), 0.0)
	assert_eq(Kit3D.leaf_mode("grass_tall", "a"), 3.0, "풀은 줄마다 흔들림")
	assert_eq(Kit3D.leaf_mode("tuft", "a"), 3.0)
	assert_eq(Kit3D.leaf_mode("boulder_mossy", "a"), 0.0)


## 빛을 내는 물건: 불꽃 살리고 몸통 누르는 재질(깊이 안 씀 — 외곽선 없음), 뒤집힌 잎 판은 빛 방향을 되돌린다.
func test_glow_prop_and_leaf_flip() -> void:
	var Kit3D := preload("res://scenes/kit/kit3d.gd")
	var DungeonKit := preload("res://scenes/kit/dungeon_kit.gd")
	var kit: RefCounted = DungeonKit.open()
	var n: Node3D = Kit3D.make(kit, "firepit", "lit")
	var sp: Variant = n.get_meta("sprite", null)
	assert_true(sp is SpriteBase3D and (sp as SpriteBase3D).material_override is ShaderMaterial, "모닥불 재질")
	var sh: Shader = ((sp as SpriteBase3D).material_override as ShaderMaterial).shader
	assert_true(sh.code.contains("depth_draw_never"), "깊이 안 씀")
	n.free()
	var before := Kit3D.wind
	Kit3D.wind = true
	var a: Node3D = Kit3D.make(kit, "bush", "a", {"flip": true})
	var m: ShaderMaterial = (a.get_meta("sprite") as Sprite3D).material_override
	assert_true(bool(m.get_shader_parameter("flip_x")), "뒤집힌 덤불은 빛 방향 되돌림")
	a.free()
	Kit3D.wind = before


## 도트 효과: 굽기 목록의 효과가 다 구워져 있고, 모든 주문이 고르는 효과가 실제로 있다(없으면 화면에 아무것도 안 뜬다).
func test_pixel_fx_catalog() -> void:
	var PFX := preload("res://scenes/battle/pixel_fx.gd")
	var Vfx := preload("res://scenes/battle/vfx.gd")
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/pixelfx_bake.json"))
	for n: String in cfg["fx"]:
		assert_true(PFX.has(n), "구운 효과 %s" % n)
	assert_eq(Vfx.spell_look(RulesDB.get_entry("spell", "fire_bolt"))["kind"], "bolt", "공격 굴림 주문 = 탄")
	assert_eq(Vfx.spell_look(RulesDB.get_entry("spell", "fireball")), {"kind": "area", "family": "fire"})
	assert_eq(Vfx.spell_look(RulesDB.get_entry("spell", "burning_hands"))["kind"], "cone")
	assert_eq(Vfx.spell_look(RulesDB.get_entry("spell", "cure_wounds"))["kind"], "heal")
	for sp: Dictionary in RulesDB.entries("spell"):
		var d: Dictionary = Vfx.spell_look(sp)
		var fam: String = d["family"]
		var want := ""
		match String(d["kind"]):
			"bolt":
				want = "bolt_" + ("acid" if fam == "poison" else fam)
				assert_true(PFX.has("hit_" + fam), "%s 맞는 자리 hit_%s" % [sp["id"], fam])
			"area":
				want = "area_" + fam if PFX.has("area_" + fam) else "hit_" + fam
			"hit":
				want = "hit_" + fam
			"heal", "heal_area", "shield", "buff", "hex", "charm":
				want = "heal" if d["kind"] == "heal" else String(d["kind"])
		if want != "":
			assert_true(PFX.has(want), "%s → %s" % [sp["id"], want])
	for id: String in Vfx.STATUS_FX:
		assert_true(PFX.has(String(Vfx.STATUS_FX[id][0])), "상태 %s" % id)
	assert_true(PFX.frame_at("st_burning", 100.0) >= 0, "고리 효과는 돈다")
	assert_eq(PFX.frame_at("hit", 100.0), -1, "한 번 효과는 끝난다")
