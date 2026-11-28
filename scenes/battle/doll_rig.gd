extends Node3D
## 간이 3D 인형 캐릭터(룰북 1단계 '스프라이트 방향', 표현 계층 — 2026-11-28): 컷아웃 평면 그림 대신
## 단순 도형(머리 공·몸통·팔다리 막대·손발)에 관절을 넣은 인형을 캐릭터 전용 창(SubViewport, 자기 세계)에서
## 위에서 비스듬히 내려다보는 직교 카메라(PITCH)로 그림 1도트 = 창 1화소로 찍는다 → 세운 판에 입힘(actor_view).
## 정수리·어깨 윗면이 보이고 다리가 짧아 보이는 위에서 본 느낌이 저절로, 방향은 인형을 돌려(4방향, 8방향도 그림 추가 없이).
## 음영은 doll.gdshader(왼쪽 위·살짝 앞 빛 3단, 밝은 쪽 따뜻하게·그늘 차갑게), 겹친 부위 안쪽 선은 doll_line.gdshader, 몸 윤곽은 화면 외곽선(pixel_outline).
## 몸 치수·동작 세기는 체형 틀 doll(data/rules/body_templates.json, 단위 = 보통 크기 화면 도트).
## 장비는 착용 아이템 모양(Cutout.look ← data/rules/cutout_looks.json)대로 관절에 붙인다: 갑옷 cover 부위 껍데기·무늬, 투구·머리띠,
## 망토, 장갑·건틀릿·팔찌, 장화, 무기(오른손 — 활은 왼손)·방패(왼팔). 안 입은 곳은 맨몸.
## 컷아웃 뼈대(cutout_rig.gd)와 같은 창구: apply_look·set_facing·play·anim·dot·canvas_px·height_px·foot_px.

const Cutout := preload("res://scripts/rules/cutout.gd")
const SHADER := preload("res://scenes/battle/doll.gdshader")
const LINE_SHADER := preload("res://scenes/battle/doll_line.gdshader")
## 인형 카메라가 내려다보는 각(도). 맵 카메라(51.3°)보다 조금 눕혀 얼굴·몸이 읽히게.
const PITCH := 40.0
## 보통 크기 캐릭터의 dot(actor_view CUT_K / PIXEL_DOT_PX) — 체형 치수가 이 크기 기준 도트
const BASE_DOT := 0.28
## 창 크기(보통 크기 도트)와 발 자리(창 아래에서 위로)
const CANVAS := Vector2(78, 76)  # 가로는 누운 몸(머리 ~ 발)이 들어가게
const FOOT := 10.0
## 켜기: 도트 캐릭터일 때 컷아웃 대신 인형(battle_scene — --doll=0이면 옛 컷아웃)
static var enabled := true

var dot := BASE_DOT
var look: Dictionary = {}
var tpl: Dictionary = {}
var anim := "idle"
var anim_t := 0.0
var facing := 0
var dims: Dictionary = {}
var root: Node3D  # 돌리는 몸(방향)
var j := {}  # 관절 이름 → Node3D
var cam: Camera3D
var _mats := {}


func _k() -> float:
	return dot / BASE_DOT


func _d(key: String, def: float) -> float:
	return float(dims.get(key, def))


## 모습을 입힌다(같은 key면 다시 만들지 않는다)
func apply_look(lk: Dictionary) -> void:
	if not look.is_empty() and str(look.get("key", "")) == str(lk.get("key", "")):
		return
	look = lk
	tpl = Cutout.template(str(lk.get("template", "medium")))
	dims = tpl.get("doll", {})
	_build()


## 방향: facing 0 아래(카메라 쪽)·1 왼·2 오른·3 위 → 인형을 돌린다(반전 없음)
func set_facing(f: int) -> void:
	facing = f
	if root != null:
		root.rotation.y = _yaw(anim, anim_t)


const FACING_YAW := [0.0, -90.0, 90.0, 180.0]


## 몸 방향(라디안): 바라보는 쪽. 쓰러질 때만 화면 가로로 눕게(앞·뒷모습에서 뒤로 넘어지면 세로로 짧게 눌려 보인다) 넘어지며 돌고, 일어나며 되돈다.
func _yaw(name: String, t: float) -> float:
	var base := deg_to_rad(FACING_YAW[clampi(facing, 0, 3)])
	var target := deg_to_rad(90.0 if facing in [0, 2] else -90.0)
	if name == "down":
		return lerp_angle(base, target, clampf(t / 0.3, 0.0, 1.0))
	if name == "rise":  # 누운 방향에서 일어나며 바라보던 쪽으로
		return lerp_angle(target, base, clampf(t / 0.42, 0.0, 1.0))
	return base


## 동작: idle · walk(반복) / attack_slash · attack_thrust · attack_blunt · attack_ranged · cast · cast_point · hit · dodge · jump · shove · rise
## (한 번 — 끝나면 idle) / down(쓰러져 누운 채 — hold). attack_melee는 attack_slash와 같은 옛 이름.
func play(name: String) -> void:
	if name == "attack_melee":
		name = "attack_slash"
	if name == anim and bool(anims().get(name, {}).get("loop", true) or anims().get(name, {}).get("hold", false)):
		return
	anim = name
	anim_t = 0.0


func canvas_px() -> Vector2i:
	var k := _k()
	return Vector2i(int(ceil(CANVAS.x * k * 0.5)) * 2, int(ceil(CANVAS.y * k)))


## 발 자리(창 아래에서 위로, 창 화소)
func foot_px() -> float:
	return roundf(FOOT * _k())


## 발에서 머리 꼭대기까지 — 컷아웃과 같은 단위(그림 px = 창 화소 / dot)
func height_px() -> float:
	var c := deg_to_rad(PITCH)
	var top := (_d("leg", 20) + _d("torso", 15) + _d("neck", 2) + _d("head_r", 8) * 2.0) * cos(c) + _d("head_r", 8) * sin(c) * 0.3
	return top * _k() / dot


func _process(delta: float) -> void:
	if root == null:
		return
	anim_t += delta
	var a: Dictionary = anims().get(anim, {})
	if not bool(a.get("loop", true)) and not bool(a.get("hold", false)) and anim_t > float(a.get("length", 1.0)):
		play("idle")
	pose(anim, anim_t)


# ---------- 만들기 ----------

func _build() -> void:
	for ch in get_children():
		ch.queue_free()
	j.clear()
	var k := _k()
	# 카메라: 남쪽 위 PITCH°에서 내려다보는 직교, 창 1화소 = 세계 1단위. 발(원점)이 창 아래 foot_px 자리에 오게.
	# 몸은 배율 k(크기 — 작은 생물·큰 생물)를 받은 노드 아래, 카메라는 배율 밖.
	var vp := canvas_px()
	var p := deg_to_rad(PITCH)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = float(vp.y)
	cam.near = 1.0
	cam.far = 400.0
	var up := Vector3(0, cos(p), -sin(p))
	var back := Vector3(0, sin(p), cos(p))
	cam.transform = Transform3D(Basis(Vector3.RIGHT, -p), up * (float(vp.y) * 0.5 - foot_px()) + back * 150.0)
	add_child(cam)
	# 안쪽 선 판(겹친 부위 가장자리 — doll_line.gdshader)
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	mi.mesh = q
	var lm := ShaderMaterial.new()
	lm.shader = LINE_SHADER
	lm.set_shader_parameter("depth_range", cam.far - cam.near)
	lm.render_priority = 100
	mi.material_override = lm
	mi.extra_cull_margin = 16384.0
	mi.position = Vector3(0, 0, -2)
	cam.add_child(mi)
	cam.current = true
	root = Node3D.new()
	root.scale = Vector3.ONE * k
	add_child(root)
	_build_body()
	set_facing(facing)
	pose(anim, anim_t)


## 재질 종류(doll.gdshader kind — 색 계단·얼룩 결이 다르다)
enum K { SKIN, CLOTH, LEATHER, METAL, HAIR, WOOD }
const MAT_KIND := {"mat_cloth": K.CLOTH, "mat_leather": K.LEATHER, "mat_hide": K.LEATHER, "mat_wood": K.WOOD,
	"mat_chain": K.METAL, "mat_scale": K.METAL, "mat_plate": K.METAL, "mat_steel": K.METAL, "mat_gold": K.METAL}


func _kind_of(look_entry: Dictionary, def: int) -> int:
	return int(MAT_KIND.get(str(look_entry.get("material", "")), def))


func _mat(c: Color, pattern: int = 0, kind: int = K.SKIN) -> ShaderMaterial:
	var key := "%s:%d:%d" % [c.to_html(), pattern, kind]
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("col", c)
		m.set_shader_parameter("pattern", pattern)
		m.set_shader_parameter("kind", kind)
		_mats[key] = m
	return _mats[key]


func _joint(name: String, parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.position = pos
	parent.add_child(n)
	j[name] = n
	return n


func _mesh(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## 막대(관절에서 아래로 len): 둥근 캡슐
func _limb(parent: Node3D, r: float, len: float, m: Material, r2: float = -1.0) -> void:
	var cm := CapsuleMesh.new()
	cm.radius = r if r2 < 0.0 else maxf(r, r2)
	cm.height = len + cm.radius * 2.0
	cm.radial_segments = 10
	cm.rings = 3
	_mesh(parent, cm, m, Vector3(0, -len * 0.5, 0))


func _ball(parent: Node3D, r: float, m: Material, pos: Vector3, scl := Vector3.ONE) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 14
	sm.rings = 7
	return _mesh(parent, sm, m, pos, Vector3.ZERO, scl)


func _box(parent: Node3D, size: Vector3, m: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return _mesh(parent, bm, m, pos, rot)


func _cone(parent: Node3D, r: float, h: float, m: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 8
	cm.rings = 1
	return _mesh(parent, cm, m, pos, rot)


## 인형 몸: 피부색 몸 + 종족 부위(머리카락·귀·뿔·수염·엄니·주둥이·꼬리). 그 위에 착용 아이템만 관절에 붙인다(_build_gear —
## 아이템을 안 입은 곳은 맨몸 그대로).
func _build_body() -> void:
	var lk := look
	var skin := Color(str(lk.get("skin", "#c99a7a")))
	var hair := Color(str(lk.get("hair", "#4a3222")))
	var m_skin := _mat(skin)
	var m_skin2 := _mat(skin.darkened(0.06))  # 몸통·골반은 팔다리보다 살짝 짙게(겹친 부위가 읽히게)
	var m_hair := _mat(hair, 0, K.HAIR)
	var m_dark := _mat(Color(0.1, 0.08, 0.08), 4)
	var leg := _d("leg", 24)
	var thigh := leg * 0.52
	var shin := leg - thigh - 1.0
	var torso := _d("torso", 17)
	var sh := _d("shoulder", 7.5)
	var waist := _d("waist", 5.5)
	var depth := _d("depth", 4.2)
	var hr := _d("head_r", 6)
	var lr := _d("leg_r", 2.6)
	var ar := _d("arm_r", 2.1)
	var arm := _d("arm", 17)
	# 엉덩이(골반) → 몸통 → 목 → 머리
	var hips := _joint("hips", root, Vector3(0, leg, 0))
	_ball(hips, waist, m_skin2, Vector3(0, -0.5, 0), Vector3(1.0, 0.7, depth / waist))
	var chest := _joint("chest", hips, Vector3.ZERO)
	var tm := CylinderMesh.new()  # 몸통: 위가 넓은 납작 원기둥(어깨 → 허리)
	tm.top_radius = sh
	tm.bottom_radius = waist
	tm.height = torso
	tm.radial_segments = 14
	tm.rings = 2
	_mesh(chest, tm, m_skin2, Vector3(0, torso * 0.5, 0), Vector3.ZERO, Vector3(1, 1, depth / sh))
	_ball(chest, sh, m_skin2, Vector3(0, torso - 0.6, 0), Vector3(1, 0.42, depth / sh))  # 어깨 윗면(위에서 보이는 둥근 어깨)
	var neck := _joint("neck", chest, Vector3(0, torso, 0))
	_ball(neck, ar * 0.95, m_skin, Vector3(0, 0.8, 0))
	var head := _joint("head", neck, Vector3(0, _d("neck", 2), 0))
	_build_head(head, hr, hair, m_skin, m_hair, m_dark)
	# 팔: 어깨 → 팔꿈치 → 손 (오른손 = 캐릭터 오른쪽 = -x, 앞 = +z)
	for side: String in ["r", "l"]:
		var sx := -1.0 if side == "r" else 1.0
		var shoulder := _joint("shoulder_" + side, chest, Vector3(sx * (sh - ar * 0.4), torso - ar * 0.9, 0))
		_limb(shoulder, ar, arm * 0.5, m_skin)
		var elbow := _joint("elbow_" + side, shoulder, Vector3(0, -arm * 0.5, 0))
		_limb(elbow, ar * 0.88, arm * 0.45, m_skin)
		var hand := _joint("hand_" + side, elbow, Vector3(0, -arm * 0.48, 0))
		_ball(hand, ar * 1.05, m_skin, Vector3(0, -0.6, 0.2))
		# 다리: 엉덩이 → 무릎 → 발
		var hip := _joint("hip_" + side, hips, Vector3(sx * waist * 0.5, -0.5, 0))
		_limb(hip, lr, thigh, m_skin)
		var knee := _joint("knee_" + side, hip, Vector3(0, -thigh, 0))
		_limb(knee, lr * 0.85, shin, m_skin)
		var foot := _joint("foot_" + side, knee, Vector3(0, -shin, 0))
		_box(foot, Vector3(lr * 1.6, lr * 0.9, lr * 2.6), m_skin, Vector3(0, -lr * 0.45, lr * 0.6))
	if "tail" in lk.get("extras", []):
		var tail := _joint("tail", hips, Vector3(0, 0, -depth * 0.8))
		tail.rotation_degrees = Vector3(55, 0, 0)
		_limb(tail, 1.0, 11.0, _mat(skin.darkened(0.15)))
	_build_gear()


func _build_head(head: Node3D, hr: float, hair: Color, m_skin: Material, m_hair: Material, m_dark: Material) -> void:
	var extras: Array = look.get("extras", [])
	var c := Vector3(0, hr, 0)
	_ball(head, hr, m_skin, c, Vector3(0.95, 1.0, 0.95))
	# 눈: 앞쪽 두 점(창 1화소)
	for ex: float in [-0.36, 0.36]:
		_box(head, Vector3(1.0, 1.4, 1.0), m_dark, c + Vector3(hr * ex, -hr * 0.05, hr * 0.9))
	if hair.a > 0.01 and _head_shape() != "helmet":
		# 머리카락: 정수리·뒤통수를 덮는 반구(앞은 이마까지) + 뒷머리
		var hm := SphereMesh.new()
		hm.radius = hr * 1.07
		hm.height = hr * 1.07
		hm.is_hemisphere = true
		hm.radial_segments = 14
		hm.rings = 5
		_mesh(head, hm, m_hair, c + Vector3(0, hr * 0.22, -hr * 0.04), Vector3(-14, 0, 0))
		_ball(head, hr * 0.9, m_hair, c + Vector3(0, -hr * 0.1, -hr * 0.3), Vector3(1.05, 0.9, 0.85))
	if "ears_pointed" in extras:
		for sx: float in [-1.0, 1.0]:
			_cone(head, hr * 0.28, hr * 0.9, m_skin, c + Vector3(sx * hr * 1.05, hr * 0.1, -hr * 0.1), Vector3(0, 0, -sx * 70.0))
	if "horns" in extras:
		var hc := _mat(Color("#3a2e2a"), 0, K.WOOD)
		for sx: float in [-1.0, 1.0]:
			_cone(head, hr * 0.3, hr * 1.1, hc, c + Vector3(sx * hr * 0.55, hr * 1.25, hr * 0.05), Vector3(-25, 0, -sx * 28.0))
	if "beard" in extras:
		_ball(head, hr * 0.7, m_hair, c + Vector3(0, -hr * 0.62, hr * 0.48), Vector3(1.0, 1.0, 0.6))
	if "tusks" in extras:
		var tc := _mat(Color("#ece2cc"))
		for sx: float in [-0.4, 0.4]:
			_cone(head, 0.6, 1.5, tc, c + Vector3(hr * sx, -hr * 0.4, hr * 0.85))
	if "snout" in extras:
		_box(head, Vector3(hr * 0.9, hr * 0.6, hr * 0.9), m_skin, c + Vector3(0, -hr * 0.25, hr * 1.0))


# ---------- 장비(착용 아이템) ----------

const PATTERN := {"chain": 1, "scale": 2, "studs": 3, "quilt": 5, "bands": 6}
const UNDER := Color("#4a3a2c")  # 갑옷 밑 바지·속옷


func _head_shape() -> String:
	var hl: Dictionary = look.get("head_look", {})
	if not hl.is_empty():
		return str(hl.get("shape", ""))
	return "helmet" if look.get("helmet", false) else ""


## 껍데기 막대(관절에서 아래로 len): 몸 부위보다 조금 굵은 캡슐
func _shell(joint: String, r: float, len: float, m: Material, from := 0.0) -> void:
	if not j.has(joint):
		return
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = len + r * 2.0
	cm.radial_segments = 10
	cm.rings = 3
	_mesh(j[joint], cm, m, Vector3(0, -from - len * 0.5, 0))


func _build_gear() -> void:
	var leg := _d("leg", 24)
	var thigh := leg * 0.52
	var shin := leg - thigh - 1.0
	var torso := _d("torso", 17)
	var sh := _d("shoulder", 7.5)
	var waist := _d("waist", 5.5)
	var depth := _d("depth", 4.2)
	var hr := _d("head_r", 6)
	var lr := _d("leg_r", 2.6)
	var ar := _d("arm_r", 2.1)
	var arm := _d("arm", 17)
	var t := 0.7  # 껍데기 두께
	# 갑옷: 덮는 부위마다 껍데기, 나머지 다리는 바지
	var armor: Dictionary = look.get("armor", {})
	if armor.is_empty():
		# 기본 옷(갑옷이 없을 때): 클래스 색 윗옷(몸통·반소매·짧은 자락) + 바지 — 갑옷과 같은 길로 그린다
		armor = {"cover": ["torso", "upper_arm", "skirt"], "color": str(look.get("tunic", "#6b5a48")), "material": "mat_cloth", "clothes": true}
	if not armor.is_empty():
		var cover: Array = armor.get("cover", ["torso"])
		var col := Color(str(armor.get("color", "#808080")))
		var pat: int = PATTERN.get(str(armor.get("pattern", "")), 0)
		var ak := _kind_of(armor, K.CLOTH)
		var m := _mat(col, pat, ak)
		var m_plain := _mat(col.darkened(0.08), 0, ak)
		var m_under := _mat(UNDER, 0, K.CLOTH)
		if "torso" in cover:
			var tm := CylinderMesh.new()
			tm.top_radius = sh + t
			tm.bottom_radius = waist + t
			tm.height = torso + 0.6
			tm.radial_segments = 14
			tm.rings = 2
			_mesh(j["chest"], tm, m, Vector3(0, torso * 0.5 - 0.2, 0), Vector3.ZERO, Vector3(1, 1, (depth + t) / (sh + t)))
			_ball(j["chest"], sh + t, m, Vector3(0, torso - 0.6, 0), Vector3(1, 0.42, (depth + t) / (sh + t)))
			_box(j["chest"], Vector3((waist + t) * 2.0 + 0.4, 1.4, (depth + t) * 2.0 * waist / sh + 0.6), _mat(Color("#3a2a1c"), 0, K.LEATHER), Vector3(0, 1.0, 0))  # 허리띠
		# 골반·다리: 바지(갑옷이 넓적다리를 덮으면 그 위에 갑옷)
		_ball(j["hips"], waist + t * 0.6, m_under, Vector3(0, -0.5, 0), Vector3(1.0, 0.72, (depth + t) / (waist + t)))
		for sd: String in ["r", "l"]:
			_shell("hip_" + sd, lr + t * 0.5, thigh, m_under)
			_shell("knee_" + sd, lr * 0.85 + t * 0.5, shin * 0.85, m_under)
			if "upper_arm" in cover:
				_shell("shoulder_" + sd, ar + t, arm * (0.3 if armor.get("clothes", false) else 0.5), m)
			if "forearm" in cover:
				_shell("elbow_" + sd, ar * 0.88 + t, arm * 0.42, m_plain)
			if "thigh" in cover:
				_shell("hip_" + sd, lr + t, thigh * 0.95, m)
			if "shin" in cover:
				_shell("knee_" + sd, lr * 0.85 + t, shin * 0.8, m_plain)
			if "pauldron" in cover:
				_ball(j["shoulder_" + sd], ar * 1.7, _mat(col.lightened(0.06), 0, ak), Vector3(0, 0.2, 0), Vector3(1.1, 0.8, 1.1))
		if "skirt" in cover:
			var skm := CylinderMesh.new()  # 허리에서 넓적다리 중간까지 퍼지는 자락
			skm.top_radius = waist + t
			skm.bottom_radius = waist + t + 2.2
			skm.height = thigh * 0.55
			skm.radial_segments = 14
			_mesh(j["hips"], skm, m, Vector3(0, -skm.height * 0.5, 0), Vector3.ZERO, Vector3(1, 1, (depth + t) / (waist + t)))
	# 머리: 투구(정수리 덮는 반구 + 테) · 머리띠(이마 고리)
	var hl: Dictionary = look.get("head_look", {})
	var hshape := _head_shape()
	var hcol := Color(str(hl.get("color", Cutout.material_color("mat_steel"))))
	var hc := Vector3(0, hr, 0)
	if hshape == "helmet":
		var hm := SphereMesh.new()
		hm.radius = hr * 1.07
		hm.height = hr * 1.07
		hm.is_hemisphere = true
		hm.radial_segments = 14
		hm.rings = 5
		# 앞을 들어 올려 이마까지만(얼굴이 보이게), 쇠는 살짝 어둡게(밝은 단이 하얗게 날지 않게)
		_mesh(j["head"], hm, _mat(hcol.darkened(0.18), 0, K.METAL), hc + Vector3(0, hr * 0.2, -hr * 0.08), Vector3(-24, 0, 0))
		var rim := CylinderMesh.new()
		rim.top_radius = hr * 1.1
		rim.bottom_radius = hr * 1.12
		rim.height = 1.0
		rim.radial_segments = 14
		_mesh(j["head"], rim, _mat(hcol.darkened(0.4), 0, K.METAL), hc + Vector3(0, hr * 0.2, -hr * 0.08), Vector3(-24, 0, 0))
	elif hshape == "headband":
		var tm2 := TorusMesh.new()
		tm2.inner_radius = hr * 0.98
		tm2.outer_radius = hr * 1.12
		tm2.rings = 16
		tm2.ring_segments = 4
		_mesh(j["head"], tm2, _mat(hcol, 0, _kind_of(hl, K.METAL)), hc + Vector3(0, hr * 0.32, 0), Vector3(-8, 0, 0))
	# 망토: 어깨에서 등 뒤로 퍼져 무릎 위까지
	var cl: Dictionary = look.get("cloak_look", {})
	if not cl.is_empty() or look.get("cloak", false):
		var ccol := Color(str(cl.get("color", "#3e2f4a")))
		var cm := CylinderMesh.new()
		cm.top_radius = sh * 0.95
		cm.bottom_radius = sh * 1.35
		cm.height = torso + leg * 0.5
		cm.radial_segments = 12
		var cmi := _mesh(j["chest"], cm, _mat(ccol, 0, K.CLOTH), Vector3(0, torso - cm.height * 0.5, -depth - 0.6), Vector3(-7, 0, 0), Vector3(1, 1, 0.3))
		cmi.name = "cloak"
		_box(j["chest"], Vector3(sh * 2.0, 1.2, depth * 2.0 + 1.0), _mat(ccol.darkened(0.12), 0, K.CLOTH), Vector3(0, torso - 0.4, 0))  # 어깨 덮개 깃
	# 손: 장갑(손 덮개) · 건틀릿(크고 쇠, 팔뚝 끝까지) · 팔찌(팔뚝 띠)
	var hd: Dictionary = look.get("hands_look", {})
	var hshape2 := str(hd.get("shape", "gloves" if look.get("gloves", false) else ""))
	if hshape2 != "":
		var gcol := Color(str(hd.get("color", "#4a3424")))
		var gk := _kind_of(hd, K.LEATHER)
		for sd: String in ["r", "l"]:
			if hshape2 == "bracers":
				_shell("elbow_" + sd, ar * 0.88 + 0.6, arm * 0.2, _mat(gcol, 0, gk), arm * 0.18)
			else:
				_ball(j["hand_" + sd], ar * (1.3 if hshape2 == "gauntlets" else 1.15), _mat(gcol, 0, gk), Vector3(0, -0.6, 0.2))
				if hshape2 == "gauntlets":
					_shell("elbow_" + sd, ar * 0.88 + 0.8, arm * 0.16, _mat(gcol.darkened(0.08), 0, gk), arm * 0.28)
	# 발: 장화(정강이 아래 반 + 발)
	var ft: Dictionary = look.get("feet_look", {})
	if not ft.is_empty() or look.get("boots", false):
		var bcol := Color(str(ft.get("color", "#3a2a1e")))
		for sd: String in ["r", "l"]:
			_shell("knee_" + sd, lr * 0.85 + 0.8, shin * 0.45, _mat(bcol, 0, K.LEATHER), shin * 0.5)
			_box(j["foot_" + sd], Vector3(lr * 1.6 + 1.0, lr * 0.9 + 0.8, lr * 2.6 + 1.0), _mat(bcol.darkened(0.1), 0, K.LEATHER), Vector3(0, -lr * 0.45, lr * 0.6))
	else:
		for sd: String in ["r", "l"]:  # 기본 신(장화 아이템이 없을 때): 발만 덮는 가죽 신
			_box(j["foot_" + sd], Vector3(lr * 1.6 + 0.6, lr * 0.9 + 0.5, lr * 2.6 + 0.6), _mat(Color("#2e241c"), 0, K.LEATHER), Vector3(0, -lr * 0.45, lr * 0.6))
	# 무기: 오른손(활은 왼손 — 활 동작이 왼팔로 겨눈다), 보조 손·방패는 왼손
	var w: Dictionary = look.get("weapon", {})
	var o: Dictionary = look.get("offhand", {})
	if not w.is_empty():
		_build_weapon(w, j["hand_l"] if str(w.get("shape", "")) == "bow" else j["hand_r"], str(w.get("shape", "")) == "bow")
	if not o.is_empty():
		_build_weapon(o, j["hand_l"], true)


## 쥔 각(손 관절 x 회전 도 — 손의 +y는 팔꿈치 쪽, +z는 손등 앞): 120 = 칼끝이 앞으로 살짝 아래(편하게 든 칼),
## 180 = 팔을 곧게 이은 방향(휘두를 때 동작 키 weapon_r·weapon_l로), 0~12 = 팔 따라 곧추선 활·지팡이·창.
const GRIP := {"default": 120.0, "bow": 0.0, "staff": 10.0, "spear": 10.0, "sling": 170.0, "whip": 150.0}


## 무기 하나: 손 관절에 붙인다. 축(+y)이 칼끝, 쥔 각은 GRIP(동작이 weapon_r·weapon_l 키로 손목을 꺾는다).
func _build_weapon(w: Dictionary, hand: Node3D, left: bool) -> void:
	var shape := str(w.get("shape", ""))
	var v := str(w.get("variant", ""))
	var c := Color(str(w.get("color", "#c8ccd2")))
	var glow := str(w.get("glow", ""))
	var L := float(w.get("length", 40)) * WEAPON_K
	var g := _joint("weapon_l" if left else "weapon_r", hand, Vector3((1.0 if left else -1.0) * 0.6, -0.8, 0.8))
	# 두손 쥐기: 두손 무기, 또는 양손 겸용인데 보조 손이 비었을 때(활·석궁·총은 제 동작). 왼손이 쥘 자리 = grip2(무기 좌표)
	var two: bool = not left and shape not in ["bow", "crossbow", "gun", "sling", "whip"] and (bool(w.get("two_handed", false)) or (bool(w.get("versatile", false)) and look.get("offhand", {}).is_empty()))
	if shape != "shield":
		g.rotation_degrees = Vector3(float(GRIP.get(shape, GRIP["default"])), 0, 0)
	g.set_meta("rest", g.rotation)
	var out := 1.0 if left else -1.0  # 몸 바깥쪽(x)
	var steel_c := Color(Cutout.material_color("mat_steel")).darkened(0.12)
	var steel := _mat(steel_c, 0, K.METAL)
	var dark := _mat(steel_c.darkened(0.35), 0, K.METAL)
	var wood := _mat(Color("#5e4028"), 0, K.WOOD)
	var wrap := _mat(Color("#3a2618"), 0, K.LEATHER)
	var brass := _mat(Color("#9a7a3e"), 0, K.METAL)
	var blade := _mat(Color(glow) if glow != "" else steel_c, 0, K.METAL if glow == "" else K.SKIN)
	var gem := Color()
	var rar := str(w.get("rarity", "common"))
	if RARITY_GEM.has(rar):
		gem = RARITY_GEM[rar]
	match shape:
		"shield":
			var sm := CylinderMesh.new()  # 둥근 방패: 팔뚝 바깥에 세워 앞을 막는다
			sm.top_radius = 5.6
			sm.bottom_radius = 5.6
			sm.height = 1.0
			sm.radial_segments = 16
			_mesh(g, sm, _mat(c, 0, _kind_of(w, K.WOOD)), Vector3(1.4, 2.6, 0.6), Vector3(90, 0, 75))
			_ball(g, 1.4, steel, Vector3(2.0, 2.6, 0.8))
			var rim := TorusMesh.new()
			rim.inner_radius = 5.2
			rim.outer_radius = 6.0
			rim.rings = 16
			rim.ring_segments = 4
			_mesh(g, rim, dark, Vector3(1.4, 2.6, 0.6), Vector3(90, 0, 75))
		"sword", "dagger":
			_sword(g, v, L, blade, steel, brass, wrap, two, out)
		"axe":
			_haft(g, L, wood, two, 1.0)
			match v:
				"pick":  # 곡괭이: 앞으로 길게 휜 뾰족 머리 + 뒤 망치
					_box(g, Vector3(L * 0.5, 1.2, 1.2), steel, Vector3(out * L * 0.22, L * 0.92, 0), Vector3(0, 0, out * 12.0))
					_box(g, Vector3(1.6, 1.6, 1.6), dark, Vector3(-out * 1.0, L * 0.92, 0))
				_:
					var bw := L * (0.42 if v == "great" else (0.3 if v == "hand" else 0.36)) + 1.6
					var bh := L * (0.42 if v == "great" else 0.32) + 1.4
					_axe_head(g, bw, bh, L * 0.86, out, steel, dark)
					if v == "great":
						_axe_head(g, bw, bh, L * 0.86, -out, steel, dark)  # 양날
					_box(g, Vector3(1.8, 1.6, 1.6), dark, Vector3(0, L * 0.86, 0))
		"mace":
			_haft(g, L, _mat(steel_c.darkened(0.45), 0, K.METAL) if v != "flail" else wood, two, 0.9)
			var mr := 2.8 + L * 0.09
			var head := _mat(steel_c.darkened(0.08), 0, K.METAL)
			match v:
				"flail":  # 도리깨: 사슬 끝에 매달린 가시 공
					for i in 3:
						_ball(g, 0.6, dark, Vector3(out * (0.6 + i * 0.9), L * 0.95 - i * 1.2, 0))
					_ball(g, mr * 0.9, head, Vector3(out * 3.2, L * 0.95 - 4.4, 0))
					for k2: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]:
						_cone(g, 0.5, 1.4, dark, Vector3(out * 3.2, L * 0.95 - 4.4, 0) + k2 * mr * 0.95, _cone_rot(k2))
				"spiked":  # 모닝스타: 가시 공
					_ball(g, mr, head, Vector3(0, L * 0.9, 0))
					for k3: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.BACK, Vector3.FORWARD]:
						_cone(g, 0.6, 1.8, dark, Vector3(0, L * 0.9, 0) + k3 * mr * 0.95, _cone_rot(k3))
				_:  # 철퇴: 쇠뭉치 + 날개 네 장
					_ball(g, mr, head, Vector3(0, L * 0.9, 0))
					for a2: float in [0.0, 45.0, 90.0, 135.0]:
						_box(g, Vector3(mr * 2.6, mr * 1.5, 0.9), head, Vector3(0, L * 0.9, 0), Vector3(0, a2, 0))
			_ball(g, 0.9, dark, Vector3(0, -0.2, 0))  # 손잡이 끝
		"hammer":
			_haft(g, L, wood, two, 1.0)
			var hw := (2.2 if v == "light" else (3.6 if v == "maul" else 2.8)) + L * 0.06
			_box(g, Vector3(hw * (1.6 if v == "maul" else 1.2), hw, hw), _mat(steel_c.darkened(0.08), 0, K.METAL), Vector3(out * hw * 0.3, L * 0.9, 0))
			if v != "maul":
				_cone(g, hw * 0.4, hw * 1.1, dark, Vector3(-out * hw * 0.85, L * 0.9, 0), Vector3(0, 0, -out * 90.0))  # 뒤 뾰족
			_box(g, Vector3(hw * 1.3, 0.5, hw * 1.1), dark, Vector3(out * hw * 0.3, L * 0.9 + hw * 0.5, 0))
		"club":
			var cm2 := CylinderMesh.new()  # 곤봉: 끝으로 갈수록 굵은 나무 + 옹이
			cm2.top_radius = (2.6 if v == "great" else 1.9) + L * 0.04
			cm2.bottom_radius = 0.8
			cm2.height = L * 1.05
			cm2.radial_segments = 8
			_mesh(g, cm2, _mat(Color("#6a4a2e"), 0, K.WOOD), Vector3(0, L * 0.42 - (L * 0.3 if two else 0.0), 0))
			_ball(g, cm2.top_radius * 0.5, _mat(Color("#4e3420"), 0, K.WOOD), Vector3(out * cm2.top_radius * 0.8, L * 0.7, 0.4))
			if two:
				g.set_meta("grip2", Vector3(0, -L * 0.28, 0))
		"spear":
			_spear(g, v, L, wood, steel, dark, two, out)
		"staff":
			var sr := 1.2 if v != "blowgun" else 0.8
			_rod(g, -L * 0.45, L * 1.0, sr, _mat(Color("#6a4a2e"), 0, K.WOOD))
			if v == "blowgun":
				_rod(g, L * 0.95, L * 1.05, 0.9, brass)
			else:
				for y: float in [-L * 0.45, L * 0.98]:
					_rod(g, y - 0.6, y + 0.6, sr + 0.35, brass)  # 쇠 테
			if two:
				g.set_meta("grip2", Vector3(0, L * 0.35, 0))
		"bow":
			var bl := L * (1.15 if v == "long" else 0.85)
			var bm := _mat(c.darkened(0.1), 0, K.WOOD)
			for i in 7:
				var u := (float(i) - 3.0) / 3.0
				_box(g, Vector3(1.3, bl * 0.18, 1.3), bm, Vector3(0, u * bl * 0.45, (1.0 - u * u) * 3.0), Vector3(-u * 38.0, 0, 0))
			_box(g, Vector3(1.6, 2.0, 1.6), wrap, Vector3(0, 0, 3.0))  # 손잡이
			_box(g, Vector3(0.35, bl * 0.92, 0.35), _mat(Color(0.82, 0.78, 0.7), 4), Vector3(0, 0, 0))
		"crossbow":
			var ck := 0.7 if v == "hand" else (1.2 if v == "heavy" else 1.0)
			_box(g, Vector3(1.6, L * 0.75 * ck, 1.8), _mat(c, 0, K.WOOD), Vector3(0, L * 0.3 * ck, 0))
			_box(g, Vector3(L * 0.75 * ck, 1.2, 1.2), dark, Vector3(0, L * 0.6 * ck, 0))
			_box(g, Vector3(L * 0.75 * ck, 0.3, 0.3), _mat(Color(0.82, 0.78, 0.7), 4), Vector3(0, L * 0.5 * ck, -0.6))
		"gun":
			var gk := 0.55 if v == "pistol" else 1.0
			_rod(g, 0.0, L * 0.95 * gk, 0.75, dark)
			_box(g, Vector3(1.8, 4.0 * gk + 1.0, 2.2), wood, Vector3(0, 0.0, -0.6))
			_box(g, Vector3(1.0, 1.2, 1.0), brass, Vector3(0, 1.4, 0.4))
		"whip":
			for i in 6:  # 늘어진 채찍 고리
				_ball(g, 0.6, wrap, Vector3(out * sin(i * 0.9) * 1.6, -0.8 - i * 1.2, cos(i * 0.9) * 1.0))
			_rod(g, -0.6, 2.6, 0.8, wrap)
		"sling":
			_rod(g, -L * 0.35, 0.0, 0.3, wrap)
			_ball(g, 1.0, wrap, Vector3(0, -L * 0.35, 0))
		_:
			_rod(g, 0.0, L * 0.6, 0.8, _mat(c))
	if two and shape in ["spear", "staff"]:
		g.set_meta("pole", true)  # 두손 장대 무기: 서 있기·걷기에서 곧추세워 든다
	if two and not g.has_meta("grip2"):
		g.set_meta("grip2", Vector3(0, -L * 0.28, 0))  # 자루 무기: 오른손 아래(자루 끝 쪽)
	if gem.a > 0.0 and shape not in ["shield", "bow", "crossbow", "gun", "sling", "whip"]:
		_ball(g, 0.9, _mat(gem, 4), Vector3(0, 0.0, 1.0))  # 마법 무기: 등급 색 보석


## 무기 크기(무기 길이 px → 인형 단위) — 몸에 비해 작대기처럼 보이지 않게
const WEAPON_K := 0.42
## 마법 무기 등급 보석 색
const RARITY_GEM := {"uncommon": Color(0.35, 0.85, 0.4), "rare": Color(0.35, 0.6, 1.0), "very_rare": Color(0.75, 0.4, 1.0), "legendary": Color(1.0, 0.72, 0.25)}


func _rod(g: Node3D, y0: float, y1: float, r: float, m: Material) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = absf(y1 - y0)
	cm.radial_segments = 8
	cm.rings = 1
	_mesh(g, cm, m, Vector3(0, (y0 + y1) * 0.5, 0))


## 자루: 한손이면 손 아래로 조금, 두손이면 왼손이 쥘 만큼 길게
func _haft(g: Node3D, L: float, m: Material, two: bool, r: float) -> void:
	_rod(g, -(L * 0.32 if two else L * 0.12), L * 0.95, r * 1.3, m)


func _cone_rot(dir: Vector3) -> Vector3:
	if dir == Vector3.UP:
		return Vector3.ZERO
	if dir == Vector3.DOWN:
		return Vector3(180, 0, 0)
	if dir == Vector3.RIGHT:
		return Vector3(0, 0, -90)
	if dir == Vector3.LEFT:
		return Vector3(0, 0, 90)
	return Vector3(90 if dir == Vector3.BACK else -90, 0, 0)


## 도끼날: 자루에서 바깥쪽으로 넓어지는 날(앞뒤로 두꺼운 쐐기)
func _axe_head(g: Node3D, bw: float, bh: float, y: float, side: float, steel: Material, dark: Material) -> void:
	_box(g, Vector3(bw, bh * 0.7, 1.5), steel, Vector3(side * bw * 0.5, y, 0))
	_box(g, Vector3(bw * 0.4, bh, 1.4), steel, Vector3(side * bw * 0.85, y, 0))  # 넓은 날 끝
	_box(g, Vector3(0.7, bh * 1.02, 1.55), _mat(Color(0.88, 0.88, 0.86), 0, K.METAL), Vector3(side * (bw + 0.1), y, 0))  # 벼린 날
	_box(g, Vector3(bw * 0.5, 0.5, 1.2), dark, Vector3(side * bw * 0.3, y - bh * 0.32, 0))


## 칼: 외형(variant)마다 날 너비·휨·코등이·손잡이가 다르다
func _sword(g: Node3D, v: String, L: float, blade: Material, steel: Material, brass: Material, wrap: Material, two: bool, out: float) -> void:
	var bw := {"short": 3.2, "curved": 3.2, "rapier": 1.6, "great": 4.0, "sickle": 2.2, "dagger": 2.6, "dart": 1.4}.get(v, 3.0) as float
	var bl := L * ({"great": 1.05, "dagger": 0.75, "dart": 0.5}.get(v, 1.0) as float)
	var hilt := 5.6 if two else 3.0
	_rod(g, -hilt + 1.2, 1.2, 1.0, wrap)  # 손잡이(가죽 감김)
	_ball(g, 0.9, brass, Vector3(0, -hilt + 1.0, 0))  # 칼자루 끝
	if two:
		g.set_meta("grip2", Vector3(0, -hilt + 2.2, 0))
	match v:
		"rapier":  # 컵 코등이 + 고리
			var cup := SphereMesh.new()
			cup.radius = 1.8
			cup.height = 1.8
			cup.is_hemisphere = true
			_mesh(g, cup, brass, Vector3(0, 1.4, 0), Vector3(180, 0, 0))
			var ring := TorusMesh.new()
			ring.inner_radius = 1.2
			ring.outer_radius = 1.6
			_mesh(g, ring, brass, Vector3(out * 0.2, 0.4, 0.6), Vector3(0, 0, 90))
		"curved", "sickle":
			_box(g, Vector3(2.4, 0.9, 1.4), brass, Vector3(0, 1.4, 0))
		_:
			_box(g, Vector3(bw * (2.4 if v == "great" else 2.0), 1.3, 1.8), brass, Vector3(0, 1.4, 0))  # 십자 코등이
	if v == "curved" or v == "sickle":
		# 휜 날: 마디마다 조금씩 기울여 바깥쪽으로 휨(낫은 끝에서 크게 꺾임)
		var segs := 5
		var p := Vector3(0, 1.9, 0)
		var ang := 0.0
		for i in segs:
			var seg := bl / float(segs)
			ang += (8.0 if v == "curved" else (6.0 + i * 10.0)) * out
			var dir := Vector3(-sin(deg_to_rad(ang)), cos(deg_to_rad(ang)), 0)
			_box(g, Vector3(bw * (1.0 - i * 0.08), seg + 0.4, 1.3), blade, p + dir * seg * 0.5, Vector3(0, 0, ang))
			p += dir * seg
	else:
		var y0 := 1.9
		_box(g, Vector3(bw, bl, 1.3), blade, Vector3(0, y0 + bl * 0.5, 0))
		if v != "rapier" and v != "dart":
			_box(g, Vector3(0.6, bl * 0.85, 1.45), _mat(Color(0.5, 0.52, 0.56), 0, K.METAL), Vector3(0, y0 + bl * 0.45, 0))  # 피홈
		_cone(g, bw * 0.55, bw * 1.1, blade, Vector3(0, y0 + bl + bw * 0.5, 0))  # 칼끝


## 창: 외형마다 날이 다르다(나뭇잎 날·투창·글레이브 휜 날·할버드 도끼+갈고리·랜스 긴 원뿔·장창 가는 촉·삼지창)
func _spear(g: Node3D, v: String, L: float, wood: Material, steel: Material, dark: Material, two: bool, out: float) -> void:
	var len := L * ({"pike": 1.5, "lance": 1.4, "javelin": 0.85}.get(v, 1.25) as float)
	var butt := -len * 0.42  # 손은 자루 중간쯤
	var top := len * 0.58
	_rod(g, butt, top, 1.0 if v != "lance" else 1.4, wood)
	_ball(g, 0.8, dark, Vector3(0, butt, 0))
	if two:
		g.set_meta("grip2", Vector3(0, butt * 0.6, 0))
	match v:
		"glaive":
			_box(g, Vector3(2.4, 6.0, 0.8), steel, Vector3(out * 0.6, top + 3.0, 0), Vector3(0, 0, out * 10.0))
			_cone(g, 1.2, 2.4, steel, Vector3(out * 1.0, top + 6.8, 0), Vector3(0, 0, out * 10.0))
		"halberd":
			_cone(g, 0.9, 4.0, steel, Vector3(0, top + 2.0, 0))
			_axe_head(g, 3.6, 4.0, top - 0.5, out, steel, dark)
			_cone(g, 0.6, 2.2, dark, Vector3(-out * 1.4, top - 0.5, 0), Vector3(0, 0, out * 90.0))  # 갈고리
		"lance":
			_cone(g, 1.8, 7.0, steel, Vector3(0, top + 3.5, 0))
			var gd := CylinderMesh.new()  # 손 가리개
			gd.top_radius = 0.9
			gd.bottom_radius = 2.4
			gd.height = 2.4
			_mesh(g, gd, dark, Vector3(0, 1.6, 0))
		"pike":
			_cone(g, 0.8, 4.0, steel, Vector3(0, top + 2.0, 0))
		"trident":
			for x: float in [-1.6, 0.0, 1.6]:
				_cone(g, 0.5, 3.4 if x == 0.0 else 2.8, steel, Vector3(x, top + 2.0, 0))
			_box(g, Vector3(4.0, 0.8, 0.8), steel, Vector3(0, top + 0.4, 0))
		_:  # 창·투창: 나뭇잎 날
			var lw := 1.6 if v == "javelin" else 2.2
			_box(g, Vector3(lw + 0.8, 5.0, 1.1), steel, Vector3(0, top + 2.5, 0))
			_cone(g, (lw + 0.8) * 0.55, 2.4, steel, Vector3(0, top + 6.2, 0))
			_box(g, Vector3(0.9, 1.2, 0.9), dark, Vector3(0, top + 0.1, 0))


# ---------- 동작 ----------

## 동작 키(체형 틀 doll_anims — 없으면 보통 체형 것). 관절 → [[초, [x, y, z 회전 도]]], hips_pos = 엉덩이 자리 이동.
func anims() -> Dictionary:
	var a: Dictionary = tpl.get("doll_anims", {})
	return a if not a.is_empty() else Cutout.template("medium").get("doll_anims", {})


func has_anim(name: String) -> bool:
	return anims().has("attack_slash" if name == "attack_melee" else name)


## 관절 자세를 정한다: 키 사이를 부드럽게 잇되 fps 박자로 끊어(도트 장면처럼 또박또박), interp step이면 다음 키까지 그대로.
func pose(name: String, t: float) -> void:
	for n: Node3D in j.values():
		if n.has_meta("rest"):
			n.rotation = n.get_meta("rest")  # 무기 쥔 각(키가 있으면 아래에서 덮어씀)
		elif n.name != "tail":
			n.rotation = Vector3.ZERO
	j["hips"].position = Vector3(0, _d("leg", 24), 0)
	root.rotation.y = _yaw(name, t)
	var two: bool = j.has("weapon_r") and j["weapon_r"].has_meta("grip2")
	var a: Dictionary = anims().get(name + "_2h", {}) if two else {}  # 두손 무기면 _2h 변형(서 있기·걷기)
	if a.is_empty():
		a = anims().get(name, anims().get("idle", {}))
	var length := float(a.get("length", 1.0))
	var tt := fmod(t, length) if bool(a.get("loop", true)) else minf(t, length)
	var fps := float(a.get("fps", 0.0))
	if fps > 0.0 and tt < length:  # 끝 장면은 끝 자세 그대로
		tt = floorf(tt * fps + 0.0001) / fps
	var step := str(a.get("interp", "")) == "step"
	var keys: Dictionary = a.get("keys", {})
	for id: String in keys:
		var v := _sample3(keys[id], tt, step)
		if id == "hips_pos":
			j["hips"].position += v
		elif j.has(id):
			j[id].rotation = Vector3(deg_to_rad(v.x), deg_to_rad(v.y), deg_to_rad(v.z))
	if two and name in ["idle", "walk"] and j["weapon_r"].has_meta("pole"):
		j["weapon_r"].rotation = Vector3(deg_to_rad(105.0), 0, deg_to_rad(10.0))  # 팔 각(-105°)을 되돌려 곧추섬
	# 두손 무기: 왼손이 무기 자루(grip2)를 쥐게 왼팔을 맞춘다(서 있기·걷기·근접 공격)
	if two and (name in ["idle", "walk"] or name.begins_with("attack_")) and name != "attack_ranged":
		_ik_arm("l", j["weapon_r"].global_transform * Vector3(j["weapon_r"].get_meta("grip2")))


## 두 마디 팔 맞추기(IK): 어깨 → 팔꿈치 → 손이 target(세계 좌표)에 닿게 어깨·팔꿈치를 돌린다. 팔꿈치는 바깥·아래·뒤로 굽는다.
func _ik_arm(sd: String, target: Vector3) -> void:
	var sh_n: Node3D = j["shoulder_" + sd]
	var el_n: Node3D = j["elbow_" + sd]
	var hd_n: Node3D = j["hand_" + sd]
	var parent: Node3D = sh_n.get_parent()
	var a := absf(el_n.position.y)
	var b := absf(hd_n.position.y) + 0.6
	var inv := parent.global_transform.affine_inverse()
	var tl: Vector3 = inv * target  # 어깨 부모(몸통) 좌표
	var to := tl - sh_n.position
	var dist := clampf(to.length(), absf(a - b) + 0.01, a + b - 0.01)
	var dir := to.normalized()
	var side := 1.0 if sd == "l" else -1.0
	var pole := Vector3(side * 0.6, -0.6, -0.5).normalized()  # 팔꿈치가 향할 쪽
	var cos_a := clampf((a * a + dist * dist - b * b) / (2.0 * a * dist), -1.0, 1.0)
	var bend_axis := dir.cross(pole - dir * dir.dot(pole)).normalized()
	if bend_axis.length() < 0.01:
		bend_axis = Vector3.RIGHT
	var upper := dir.rotated(bend_axis, acos(cos_a))  # 윗팔 방향: 대상 쪽에서 팔꿈치 쪽으로 기울임
	var y_axis := -upper
	var z_axis := (dir - upper * upper.dot(dir)).normalized()  # 아래팔이 굽는 쪽(+z = 굽힘 방향)
	if z_axis.length() < 0.01:
		z_axis = Vector3.FORWARD
	var x_axis := y_axis.cross(z_axis).normalized()
	z_axis = x_axis.cross(y_axis).normalized()
	sh_n.basis = Basis(x_axis, y_axis, z_axis).scaled(sh_n.scale)
	var cos_e := clampf((a * a + b * b - dist * dist) / (2.0 * a * b), -1.0, 1.0)
	el_n.rotation = Vector3(-(PI - acos(cos_e)), 0, 0)


static func _sample3(k: Array, t: float, step: bool) -> Vector3:
	var v0: Array = k[0][1]
	if k.size() == 1 or t <= float(k[0][0]):
		return Vector3(float(v0[0]), float(v0[1]), float(v0[2]))
	for i in range(1, k.size()):
		var t1 := float(k[i][0])
		if t < t1:
			var a: Array = k[i - 1][1]
			var b: Array = k[i][1]
			var va := Vector3(float(a[0]), float(a[1]), float(a[2]))
			if step:
				return va
			var t0 := float(k[i - 1][0])
			var u := (t - t0) / maxf(t1 - t0, 0.0001)
			u = u * u * (3.0 - 2.0 * u)
			return va.lerp(Vector3(float(b[0]), float(b[1]), float(b[2])), u)
	var e: Array = k[k.size() - 1][1]
	return Vector3(float(e[0]), float(e[1]), float(e[2]))
