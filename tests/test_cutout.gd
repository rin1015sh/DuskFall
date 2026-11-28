extends "res://tests/test_case.gd"
## 2D 일러스트 컷아웃(룰북 1단계): 모습 데이터, 뼈대·부위, 방향 반전, 애니메이션, 장비 교체.

const Builder := preload("res://scripts/rules/character_builder.gd")
const Cutout := preload("res://scripts/rules/cutout.gd")
const Rig := preload("res://scenes/battle/cutout_rig.gd")


func _pc(cls: String, species: String = "") -> Node:
	var spec := Builder.default_spec(cls, 1)
	if species != "":
		spec["species"] = species
	var r := Builder.build(spec)
	assert_eq(r["errors"].size(), 0, str(r["errors"]))
	return own(r["creature"])


func test_templates_and_looks_data() -> void:
	for id: String in ["medium", "small", "dwarf"]:
		var t := Cutout.template(id)
		assert_eq(str(t.get("id", "")), id)
		var names := {}
		for b: Dictionary in t["bones"]:
			names[b["id"]] = true
			assert_true(str(b["parent"]) == "" or names.has(str(b["parent"])), "%s: 부모 뼈가 먼저 나온다 %s" % [id, b["id"]])
		for anim: String in ["idle", "walk", "attack_melee", "attack_ranged", "cast", "hit"]:
			for bone: String in t["animations"][anim]["keys"]:
				assert_true(names.has(bone), "%s %s: 없는 뼈 %s" % [id, anim, bone])
	for sp: Dictionary in RulesDB.entries("species"):
		assert_false(Cutout.species_look(str(sp["id"])).is_empty(), "종족 모습 %s" % sp["id"])
	for w: Dictionary in RulesDB.entries("weapon"):
		assert_false(Cutout.item_look(str(w["id"])).is_empty(), "무기 모양 %s" % w["id"])
	for a: Dictionary in RulesDB.entries("armor"):
		assert_false(Cutout.item_look(str(a["id"])).is_empty(), "갑옷 모양 %s" % a["id"])


func test_look_follows_species_and_equipment() -> void:
	var dw := _pc("cleric", "dwarf")
	var lk := Cutout.look(dw)
	assert_eq(str(lk["template"]), "dwarf", "드워프 체형")
	assert_true("beard" in lk["extras"])
	assert_true(Cutout.enabled_for(dw), "사람은 컷아웃")
	var f := _pc("fighter")
	var before := Cutout.look(f)
	assert_eq(str(before["armor"].get("shape", "")), "chain", "사슬 갑옷")
	f.equipment["armor"] = "plate_armor"
	var after := Cutout.look(f)
	assert_eq(str(after["armor"]["shape"]), "plate", "갑옷을 바꾸면 모양이 바뀐다")
	assert_true(str(before["key"]) != str(after["key"]), "모습 key가 바뀌면 부위를 다시 만든다")
	var m := make_creature({"team": "enemy"})
	m.set_meta("monster", {"id": "x"})
	assert_false(Cutout.enabled_for(m), "몬스터는 그림 그대로")


func test_rig_builds_bones_parts_facing_and_animation() -> void:
	var f := _pc("fighter")
	var rig: Node2D = Rig.new()
	tree.root.add_child(rig)
	own(rig)
	rig.apply_look(Cutout.look(f))
	assert_eq(rig.bones.size(), Cutout.template("medium")["bones"].size(), "체형 틀의 뼈 전부")
	assert_true(rig.skeleton is Skeleton2D, "Skeleton2D 뼈대")
	assert_true(rig.bones["hand_near"].get_children().any(func(n: Node) -> bool: return str(n.get_meta("part_id", "")) == "weapon"), "무기는 손 뼈에")
	rig.set_facing(1)
	assert_eq(rig.scale.x, -1.0, "왼쪽 = 앞쪽 대각선 좌우 반전")
	rig.set_facing(3)
	assert_eq(rig.view, "back", "위쪽 = 뒤쪽 대각선")
	rig.play("attack_melee")
	rig.pose("attack_melee", 0.18)
	assert_near(rad_to_deg(rig.bones["upper_arm_near"].rotation), -150.0, 0.5, "키 애니메이션")
	rig._process(5.0)
	assert_eq(rig.anim, "idle", "한 번짜리 동작이 끝나면 서 있기")
	assert_true(rig.height_px() > 150.0 and rig.height_px() < 200.0, "보통 체형 키")


## 간이 3D 인형(2026-11-28): 관절·4방향 돌리기·걷기·장비·키·창 크기
func test_doll_rig_joints_facing_walk_and_size() -> void:
	const Doll := preload("res://scenes/battle/doll_rig.gd")
	var f := _pc("fighter")
	var d: Node3D = Doll.new()
	tree.root.add_child(d)
	own(d)
	d.apply_look(Cutout.look(f))
	for id: String in ["hips", "chest", "neck", "head", "shoulder_r", "elbow_r", "hand_r", "shoulder_l", "hip_r", "knee_r", "foot_r", "hip_l", "knee_l", "foot_l"]:
		assert_true(d.j.has(id), "관절 %s" % id)
	assert_true(d.j.has("weapon_r"), "무기는 오른손에")
	assert_true(d.cam.projection == Camera3D.PROJECTION_ORTHOGONAL, "직교 카메라")
	assert_near(rad_to_deg(-d.cam.rotation.x), Doll.PITCH, 0.01, "위에서 내려다보는 각")
	d.set_facing(0)
	assert_near(d.root.rotation_degrees.y, 0.0, 0.01, "아래 = 카메라 쪽 앞모습")
	d.set_facing(2)
	assert_near(d.root.rotation_degrees.y, 90.0, 0.01, "오른쪽 = 돌림(반전 없음)")
	d.set_facing(3)
	assert_near(absf(d.root.rotation_degrees.y), 180.0, 0.01, "위 = 뒷모습")
	d.pose("walk", 0.2)
	assert_true(absf(d.j["hip_r"].rotation.x) > 0.3 and signf(d.j["hip_r"].rotation.x) != signf(d.j["hip_l"].rotation.x), "걷기: 다리가 엇갈려 흔들림")
	d.play("attack_melee")
	d._process(5.0)
	assert_eq(d.anim, "idle", "한 번짜리 동작이 끝나면 서 있기")
	assert_true(d.height_px() > 150.0 and d.height_px() < 200.0, "보통 체형 키(컷아웃과 비슷)")
	var c: Vector2i = d.canvas_px()
	assert_true(c.x % 2 == 0 and c.y > 60, "창 크기")
	d.dot = Doll.BASE_DOT * 0.8
	assert_true(d.canvas_px().y < c.y, "작은 생물은 창도 작게")
