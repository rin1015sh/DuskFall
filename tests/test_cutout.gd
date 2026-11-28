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
	assert_true(d.j.has("weapon_r"), "착용 무기는 오른손에")
	assert_true(d.cam.projection == Camera3D.PROJECTION_ORTHOGONAL, "직교 카메라")
	assert_near(rad_to_deg(-d.cam.rotation.x), Doll.PITCH, 0.01, "위에서 내려다보는 각")
	d.set_facing(0)
	assert_near(d.root.rotation_degrees.y, 0.0, 0.01, "아래 = 카메라 쪽 앞모습")
	d.set_facing(2)
	assert_near(d.root.rotation_degrees.y, 90.0, 0.01, "오른쪽 = 돌림(반전 없음)")
	d.set_facing(3)
	assert_near(absf(d.root.rotation_degrees.y), 180.0, 0.01, "위 = 뒷모습")
	d.pose("walk", 0.0)
	assert_true(absf(d.j["hip_r"].rotation.x) > 0.3 and signf(d.j["hip_r"].rotation.x) != signf(d.j["hip_l"].rotation.x), "걷기: 다리가 엇갈려 흔들림")
	d.play("attack_melee")
	d._process(5.0)
	assert_eq(d.anim, "idle", "한 번짜리 동작이 끝나면 서 있기")
	assert_true(d.height_px() > 150.0 and d.height_px() < 200.0, "보통 체형 키(컷아웃과 비슷)")
	var c: Vector2i = d.canvas_px()
	assert_true(c.x % 2 == 0 and c.y > 60, "창 크기")
	d.dot = Doll.BASE_DOT * 0.8
	assert_true(d.canvas_px().y < c.y, "작은 생물은 창도 작게")


## 인형 동작 키(doll_anims): 박자 끊기·한 번 동작·쓰러져 누운 채·다른 체형은 보통 체형 키
func test_doll_anims_keys_hold_and_fallback() -> void:
	const Doll := preload("res://scenes/battle/doll_rig.gd")
	var d: Node3D = Doll.new()
	tree.root.add_child(d)
	own(d)
	d.apply_look(Cutout.look(_pc("fighter")))
	for a: String in ["idle", "walk", "attack_slash", "attack_thrust", "attack_blunt", "attack_ranged", "cast", "cast_point", "hit", "dodge", "jump", "shove", "rise", "down"]:
		assert_true(d.has_anim(a), "동작 %s" % a)
		for id: String in d.anims()[a]["keys"]:
			assert_true(id == "hips_pos" or d.j.has(id), "%s: 없는 관절 %s" % [a, id])
	# 근접: 0.14초 준비 자세에서 팔을 머리 위 뒤로, 맞는 순간(vfx SWING_HIT 0.26)엔 앞으로 내려침
	d.pose("attack_blunt", 0.16)
	assert_true(d.j["hand_r"].global_position.y > d.j["head"].global_position.y, "준비: 손을 머리 위로")
	d.pose("attack_blunt", preload("res://scenes/battle/vfx.gd").SWING_HIT)
	assert_true(rad_to_deg(d.j["shoulder_r"].rotation.x) > -60.0, "맞는 순간: 앞으로 내려침")
	assert_true(d.j["hips"].position.z > 1.0, "내딛음")
	# 박자 끊기(fps 12): 같은 장면 안에서는 자세가 같다
	d.pose("attack_blunt", 0.17)
	var r1: float = d.j["shoulder_r"].rotation.x
	d.pose("attack_blunt", 0.18)
	assert_near(d.j["shoulder_r"].rotation.x, r1, 0.0001, "한 장면 안은 같은 자세")
	# 쓰러짐: 끝나도 누운 채, 화면 가로로
	d.set_facing(0)
	d.play("down")
	d._process(3.0)
	assert_eq(d.anim, "down", "쓰러짐은 누운 채 유지")
	assert_true(d.j["hips"].position.y < 5.0, "바닥에 누움")
	assert_near(absf(d.root.rotation_degrees.y), 90.0, 0.5, "앞모습이어도 화면 가로로 눕는다")
	d.play("idle")
	d.pose("idle", 0.0)
	assert_near(d.root.rotation_degrees.y, 0.0, 0.5, "일어나면 바라보던 쪽")
	# 다른 체형은 보통 체형 키
	var dw: Node3D = Doll.new()
	tree.root.add_child(dw)
	own(dw)
	dw.apply_look(Cutout.look(_pc("cleric", "dwarf")))
	assert_true(dw.has_anim("attack_melee"), "드워프도 보통 체형 동작(attack_melee = attack_slash 옛 이름)")
	# 근접 세 모양 모두 맞는 순간(SWING_HIT)에 앞으로 내딛어 있다
	for st: String in ["attack_slash", "attack_thrust", "attack_blunt", "shove"]:
		d.pose(st, preload("res://scenes/battle/vfx.gd").SWING_HIT)
		assert_true(d.j["hips"].position.z > 1.0, "%s: 맞는 순간 내딛음" % st)
	# 일어나기: 누운 자세에서 시작해 끝엔 선다
	d.set_facing(0)
	d.pose("rise", 0.0)
	assert_true(d.j["hips"].position.y < 5.0, "일어나기 시작 = 누운 자세")
	d.pose("rise", 0.65)
	assert_near(d.j["hips"].position.y, 24.0, 0.01, "일어나기 끝 = 선 자세")
	assert_near(d.root.rotation_degrees.y, 0.0, 0.5, "일어나며 바라보던 쪽으로")


## 인형 장비(착용 아이템): 안 입으면 맨몸, 갑옷 cover 부위·투구·망토·장갑·장화·무기(활은 왼손)·방패
func test_doll_gear_follows_items() -> void:
	const Doll := preload("res://scenes/battle/doll_rig.gd")
	var f := _pc("fighter")
	var lk := Cutout.look(f)
	assert_false(lk["armor"].get("cover", []).is_empty(), "갑옷 모양에 덮는 부위")
	var d: Node3D = Doll.new()
	tree.root.add_child(d)
	own(d)
	d.apply_look(lk)
	assert_true(d.j.has("weapon_r"), "무기는 오른손")
	var bare := lk.duplicate(true)
	for k: String in ["armor", "weapon", "offhand", "head_look", "cloak_look", "hands_look", "feet_look"]:
		bare[k] = {}
	for k: String in ["helmet", "cloak", "gloves", "boots"]:
		bare[k] = false
	bare["key"] = "bare"
	var n_armed: int = d.root.find_children("*", "MeshInstance3D", true, false).size()
	d.apply_look(bare)
	await tree.process_frame
	var n_bare: int = d.root.find_children("*", "MeshInstance3D", true, false).size()
	assert_true(n_armed > n_bare + 8, "갑옷·무기를 벗으면 껍데기가 빠진다(%d → %d)" % [n_armed, n_bare])
	assert_false(d.j.has("weapon_r"), "맨손")
	var archer := bare.duplicate(true)
	archer["weapon"] = Cutout.item_look("longbow")
	archer["cloak_look"] = Cutout.item_look("cloak_of_elvenkind")
	archer["key"] = "archer"
	d.apply_look(archer)
	assert_true(d.j.has("weapon_l") and not d.j.has("weapon_r"), "활은 왼손(활 동작이 왼팔로 겨눔)")
	assert_eq(str(archer["cloak_look"].get("color", "")), "#3a5236", "아이템 색이 재질 색보다 먼저")
	for id: String in ["cloak_of_protection", "cloak_of_elvenkind", "boots_of_elvenkind", "gauntlets_of_ogre_power", "bracers_of_defense", "gloves_of_swimming_and_climbing", "headband_of_intellect"]:
		assert_false(Cutout.item_look(id).is_empty(), "착용 아이템 모양 %s" % id)


## 인형: 두손 무기는 왼손이 자루를 쥐고(IK), 갑옷이 없으면 기본 옷, 망치·곤봉 모양
func test_doll_two_handed_and_clothes() -> void:
	const Doll := preload("res://scenes/battle/doll_rig.gd")
	var gs := Cutout.item_look("greatsword")
	assert_true(bool(gs.get("two_handed", false)), "대검 = 두손")
	assert_true(bool(Cutout.item_look("longsword").get("versatile", false)), "장검 = 양손 겸용")
	assert_eq(str(Cutout.item_look("warhammer")["shape"]), "hammer", "전쟁망치 모양")
	var sp := Cutout.species_look("human")
	var lk := {"template": "medium", "skin": str(sp["skin"]), "hair": str(sp["hair"]), "extras": [], "tunic": "#2f4a6b",
		"armor": {}, "weapon": gs, "offhand": {}, "key": "2h"}
	var d: Node3D = Doll.new()
	tree.root.add_child(d)
	own(d)
	d.apply_look(lk)
	assert_true(d.j["weapon_r"].has_meta("grip2"), "두손 쥘 자리")
	for a: String in ["idle", "walk", "attack_slash"]:
		d.pose(a, 0.26)
		var grip: Vector3 = d.j["weapon_r"].global_transform * Vector3(d.j["weapon_r"].get_meta("grip2"))
		var hand: Vector3 = d.j["hand_l"].global_transform * Vector3(0, -0.6, 0)
		assert_true(hand.distance_to(grip) < 1.5, "%s: 왼손이 자루에 닿음(%.2f)" % [a, hand.distance_to(grip)])
	# 기본 옷: 갑옷이 없어도 몸통에 윗옷(클래스 색)이 덮인다
	var cloth := false
	for mi: MeshInstance3D in d.j["chest"].find_children("*", "MeshInstance3D", false, false):
		var m: ShaderMaterial = mi.material_override
		if m != null and Color(m.get_shader_parameter("col")).is_equal_approx(Color("#2f4a6b")):
			cloth = true
	assert_true(cloth, "갑옷이 없으면 기본 윗옷")
	# 한손 무기 + 방패면 두손 아님
	var lk2 := lk.duplicate(true)  # apply_look은 같은 key면 다시 만들지 않으니 새 사전으로
	lk2["weapon"] = Cutout.item_look("longsword")
	lk2["offhand"] = Cutout.item_look("shield")
	lk2["key"] = "1h"
	d.apply_look(lk2)
	assert_false(d.j["weapon_r"].has_meta("grip2"), "방패를 들면 양손 겸용도 한 손")


## 무기: 동작은 무기 종류가, 외형은 아이템이(장검 → 장검 +1 → 장검 +2: 같은 동작, 다른 모습)
func test_item_looks_override_type_but_keep_motion() -> void:
	var base := Cutout.item_look("longsword")
	var p1 := Cutout.item_look("longsword_plus_1")
	var p2 := Cutout.item_look("longsword_plus_2")
	assert_eq(str(base["motion"]), "slash", "장검 종류 동작 = 베기")
	assert_eq(str(p1["motion"]), "slash", "아이템이 달라도 종류 동작 그대로")
	assert_eq(str(p1["shape"]), "sword", "부품 틀도 종류 그대로")
	assert_true(str(p1.get("blade", "")) != str(base.get("blade", "")) and str(p1.get("rune", "")) != "", "장검 +1은 제 외형(날 색·날 빛)")
	assert_true(str(p2.get("trim", "")) != str(p1.get("trim", "")), "장검 +2는 또 다른 외형")
	assert_eq(str(Cutout.item_look("rapier")["motion"]), "thrust", "레이피어 종류 = 찌르기")
	assert_eq(str(Cutout.item_look("greataxe_plus_2")["motion"]), "blunt", "대도끼 +2도 대도끼 동작")
	# 아이템 외형 항목은 종류의 틀·동작을 바꾸지 못한다
	for k: String in Cutout.LOOK_LOCKED:
		if k != "id":
			assert_eq(str(Cutout.item_look("mace_plus_2").get(k, "")), str(Cutout.item_look("mace").get(k, "")), "잠긴 값 %s" % k)
	# 인형: 같은 종류라도 아이템마다 다른 색으로 그린다
	const Doll := preload("res://scenes/battle/doll_rig.gd")
	var sp := Cutout.species_look("human")
	var cols := []
	for id: String in ["longsword", "longsword_plus_1", "longsword_plus_2"]:
		var d: Node3D = Doll.new()
		tree.root.add_child(d)
		own(d)
		d.apply_look({"template": "medium", "skin": str(sp["skin"]), "hair": str(sp["hair"]), "extras": [], "tunic": "#2f4a6b",
			"armor": {}, "weapon": Cutout.item_look(id), "offhand": Cutout.item_look("shield"), "key": id})
		var s := ""
		for mi: MeshInstance3D in d.j["weapon_r"].find_children("*", "MeshInstance3D", false, false):
			s += Color((mi.material_override as ShaderMaterial).get_shader_parameter("col")).to_html() + ";"
		cols.append(s)
	assert_true(cols[0] != cols[1] and cols[1] != cols[2] and cols[0] != cols[2], "장검·장검 +1·장검 +2는 다른 모습")
	# 아이템 외형 항목은 실제 아이템을 가리킨다
	var f := FileAccess.open("res://data/rules/cutout_looks.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	for o: Dictionary in data.get("item_looks", []):
		var item_id := str(o["id"]).trim_prefix("look_")
		assert_false(preload("res://scripts/rules/equipment.gd").entry(item_id).is_empty(), "아이템 외형 %s의 아이템이 있다" % item_id)
