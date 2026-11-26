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
