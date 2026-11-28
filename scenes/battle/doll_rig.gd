extends Node3D
## 간이 3D 인형 캐릭터(룰북 1단계 '스프라이트 방향', 표현 계층 — 2026-11-28): 컷아웃 평면 그림 대신
## 단순 도형(머리 공·몸통·팔다리 막대·손발)에 관절을 넣은 인형을 캐릭터 전용 창(SubViewport, 자기 세계)에서
## 위에서 비스듬히 내려다보는 직교 카메라(PITCH)로 그림 1도트 = 창 1화소로 찍는다 → 세운 판에 입힘(actor_view).
## 정수리·어깨 윗면이 보이고 다리가 짧아 보이는 위에서 본 느낌이 저절로, 방향은 인형을 돌려(4방향, 8방향도 그림 추가 없이).
## 음영은 doll.gdshader(왼쪽 위·살짝 앞 빛 3단, 밝은 쪽 따뜻하게·그늘 차갑게), 겹친 부위 안쪽 선은 doll_line.gdshader, 몸 윤곽은 화면 외곽선(pixel_outline).
## 몸 치수·동작 세기는 체형 틀 doll(data/rules/body_templates.json, 단위 = 보통 크기 화면 도트). 맨몸(피부·종족 부위만) —
## 옷·갑옷·무기는 착용 아이템에 따라 관절에 붙이는 다음 단계에서(지금은 입히지 않음).
## 컷아웃 뼈대(cutout_rig.gd)와 같은 창구: apply_look·set_facing·play·anim·dot·canvas_px·height_px·foot_px.

const Cutout := preload("res://scripts/rules/cutout.gd")
const SHADER := preload("res://scenes/battle/doll.gdshader")
const LINE_SHADER := preload("res://scenes/battle/doll_line.gdshader")
## 인형 카메라가 내려다보는 각(도). 맵 카메라(51.3°)보다 조금 눕혀 얼굴·몸이 읽히게.
const PITCH := 40.0
## 보통 크기 캐릭터의 dot(actor_view CUT_K / PIXEL_DOT_PX) — 체형 치수가 이 크기 기준 도트
const BASE_DOT := 0.28
## 창 크기(보통 크기 도트)와 발 자리(창 아래에서 위로)
const CANVAS := Vector2(64, 76)
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
		root.rotation.y = deg_to_rad([0.0, -90.0, 90.0, 180.0][clampi(f, 0, 3)])


## 동작: idle · walk(반복) / attack_melee · attack_ranged · cast · hit(한 번 — 끝나면 idle). 길이는 체형 틀 animations.
func play(name: String) -> void:
	if name == anim and name in ["idle", "walk"]:
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
	var a: Dictionary = tpl.get("animations", {}).get(anim, {})
	var length := float(a.get("length", 1.0))
	if anim not in ["idle", "walk"] and anim_t > length:
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


func _mat(c: Color, pattern: int = 0) -> ShaderMaterial:
	var key := "%s:%d" % [c.to_html(), pattern]
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("col", c)
		m.set_shader_parameter("pattern", pattern)
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


## 맨몸 인형: 피부색 몸 + 종족 부위(머리카락·귀·뿔·수염·엄니·주둥이·꼬리)만. 옷·갑옷·무기·방패는 입히지 않는다 —
## 장비는 착용한 아이템에 따라 관절(j)에 부위를 붙이는 다음 단계에서.
func _build_body() -> void:
	var lk := look
	var skin := Color(str(lk.get("skin", "#c99a7a")))
	var hair := Color(str(lk.get("hair", "#4a3222")))
	var m_skin := _mat(skin)
	var m_skin2 := _mat(skin.darkened(0.06))  # 몸통·골반은 팔다리보다 살짝 짙게(겹친 부위가 읽히게)
	var m_hair := _mat(hair)
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


func _build_head(head: Node3D, hr: float, hair: Color, m_skin: Material, m_hair: Material, m_dark: Material) -> void:
	var extras: Array = look.get("extras", [])
	var c := Vector3(0, hr, 0)
	_ball(head, hr, m_skin, c, Vector3(0.95, 1.0, 0.95))
	# 눈: 앞쪽 두 점(창 1화소)
	for ex: float in [-0.36, 0.36]:
		_box(head, Vector3(1.0, 1.4, 1.0), m_dark, c + Vector3(hr * ex, -hr * 0.05, hr * 0.9))
	if hair.a > 0.01:
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
		var hc := _mat(Color("#3a2e2a"))
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


# ---------- 동작 ----------

## 관절 회전(도)을 정한다. 걷기·서 있기는 계산(박자 = 체형 틀 길이), 한 번 동작은 짧은 키.
func pose(name: String, t: float) -> void:
	for n: Node3D in j.values():
		if n.name != "tail":
			n.rotation = Vector3.ZERO
	j["hips"].position.y = _d("leg", 20)
	var amp := float(dims.get("walk_swing", 32.0))
	match name:
		"walk":
			var length := float(tpl.get("animations", {}).get("walk", {}).get("length", 0.8))
			var ph := TAU * t / length
			var s := sin(ph)
			_rx("hip_r", -s * amp)
			_rx("hip_l", s * amp)
			_rx("knee_r", maxf(0.0, -cos(ph)) * amp * 1.3)
			_rx("knee_l", maxf(0.0, cos(ph)) * amp * 1.3)
			_rx("foot_r", -s * amp * 0.3)
			_rx("foot_l", s * amp * 0.3)
			_rx("shoulder_r", s * amp * 0.8)
			_rx("shoulder_l", -s * amp * 0.8)
			_rx("elbow_r", -18.0)
			_rx("elbow_l", -18.0)
			j["chest"].rotation.y = deg_to_rad(s * 6.0)
			j["hips"].position.y -= absf(cos(ph)) * 1.0  # 내딛을 때 1도트 내려앉음
			j["chest"].rotation.x = deg_to_rad(5.0)
		"attack_melee":
			# 준비(팔 뒤로 높이) → 내려침(0.18~0.32) → 따라감 → 복귀. 다음 단계에서 다듬는다.
			var up := _key(t, [[0.0, 0.0], [0.18, -150.0], [0.32, -20.0], [0.55, 0.0]])
			_rx("shoulder_r", up)
			_rx("elbow_r", _key(t, [[0.0, 0.0], [0.18, -40.0], [0.32, -10.0], [0.55, 0.0]]))
			j["chest"].rotation.x = deg_to_rad(_key(t, [[0.0, 0.0], [0.18, -6.0], [0.32, 12.0], [0.55, 0.0]]))
			_rx("hip_r", _key(t, [[0.0, 0.0], [0.32, -18.0], [0.55, 0.0]]))
			_rx("hip_l", _key(t, [[0.0, 0.0], [0.32, 12.0], [0.55, 0.0]]))
		"attack_ranged":
			var aim := _key(t, [[0.0, 0.0], [0.2, -85.0], [0.55, -85.0], [0.7, 0.0]])
			_rx("shoulder_l", aim)
			_rx("shoulder_r", aim * 0.9)
			_rx("elbow_r", _key(t, [[0.0, 0.0], [0.2, -40.0], [0.45, -70.0], [0.5, -10.0], [0.7, 0.0]]))
		"cast":
			var lift := _key(t, [[0.0, 0.0], [0.3, -120.0], [0.6, -110.0], [0.8, 0.0]])
			_rx("shoulder_r", lift)
			_rx("shoulder_l", lift)
			_rz("shoulder_r", _key(t, [[0.0, 0.0], [0.3, -20.0], [0.8, 0.0]]))
			_rz("shoulder_l", _key(t, [[0.0, 0.0], [0.3, 20.0], [0.8, 0.0]]))
			j["hips"].position.y += _key(t, [[0.0, 0.0], [0.3, 1.0], [0.8, 0.0]])
		"hit":
			j["chest"].rotation.x = deg_to_rad(_key(t, [[0.0, 0.0], [0.08, -16.0], [0.4, 0.0]]))
			j["head"].rotation.x = deg_to_rad(_key(t, [[0.0, 0.0], [0.08, -12.0], [0.4, 0.0]]))
			_rx("shoulder_r", _key(t, [[0.0, 0.0], [0.08, 25.0], [0.4, 0.0]]))
			_rx("shoulder_l", _key(t, [[0.0, 0.0], [0.08, 25.0], [0.4, 0.0]]))
		_:
			# 서 있기: 6박(참고 — 200·200·400·200·200·400ms)마다 1도트 숨쉬기, 팔 살짝 벌림
			var length2 := float(tpl.get("animations", {}).get("idle", {}).get("length", 1.6))
			var u := fmod(t, length2) / length2
			var down := 1.0 if (u > 0.25 and u < 0.5) or u > 0.75 else 0.0
			j["hips"].position.y -= down * 0.6
			j["chest"].position.y = 0.0
			_rx("shoulder_r", -4.0 - down * 3.0)
			_rx("shoulder_l", -4.0 - down * 3.0)
			_rz("shoulder_r", -6.0)
			_rz("shoulder_l", 6.0)
			_rx("elbow_r", -14.0)
			_rx("elbow_l", -10.0)
			_rx("knee_r", down * 6.0)
			_rx("knee_l", down * 6.0)
			_rx("hip_r", -down * 3.0)
			_rx("hip_l", -down * 3.0)


func _rx(id: String, deg: float) -> void:
	if j.has(id):
		j[id].rotation.x = deg_to_rad(deg)


func _rz(id: String, deg: float) -> void:
	if j.has(id):
		j[id].rotation.z = deg_to_rad(deg)


static func _key(t: float, k: Array) -> float:
	if t <= float(k[0][0]):
		return float(k[0][1])
	for i in range(1, k.size()):
		var t0 := float(k[i - 1][0])
		var t1 := float(k[i][0])
		if t <= t1:
			var u := (t - t0) / maxf(t1 - t0, 0.0001)
			u = u * u * (3.0 - 2.0 * u)  # 부드럽게
			return lerpf(float(k[i - 1][1]), float(k[i][1]), u)
	return float(k[k.size() - 1][1])
