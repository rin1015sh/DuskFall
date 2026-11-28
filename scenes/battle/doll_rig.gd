extends Node3D
## 간이 3D 인형 캐릭터(룰북 1단계 '스프라이트 방향', 표현 계층 — 2026-11-28): 컷아웃 평면 그림 대신
## 단순 도형(머리 공·몸통·팔다리 막대·손발)에 관절을 넣은 인형을 캐릭터 전용 창(SubViewport, 자기 세계)에서
## 위에서 비스듬히 내려다보는 직교 카메라(PITCH)로 그림 1도트 = 창 1화소로 찍는다 → 세운 판에 입힘(actor_view).
## 정수리·어깨 윗면이 보이고 다리가 짧아 보이는 위에서 본 느낌이 저절로, 방향은 인형을 돌려(4방향, 8방향도 그림 추가 없이).
## 음영은 doll.gdshader(왼쪽 위·살짝 앞 빛 3단, 밝은 쪽 따뜻하게·그늘 차갑게), 겹친 부위 안쪽 선은 doll_line.gdshader, 몸 윤곽은 화면 외곽선(pixel_outline).
## 몸 치수·동작 세기는 체형 틀 doll(data/rules/body_templates.json, 단위 = 보통 크기 화면 도트), 모습은 Cutout.look 그대로.
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


func _mat(c: Color, pattern: int = 0, step: float = 2.0) -> ShaderMaterial:
	var key := "%s:%d:%.1f" % [c.to_html(), pattern, step]
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("col", c)
		m.set_shader_parameter("pattern", pattern)
		m.set_shader_parameter("pat_step", step)
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


func _build_body() -> void:
	var lk := look
	var armor: Dictionary = lk.get("armor", {})
	var ashape := str(armor.get("shape", ""))
	var body_col := Color(str(armor.get("color", lk.get("tunic", "#6b5a48")))) if not armor.is_empty() else Color(str(lk.get("tunic", "#6b5a48")))
	var skin := Color(str(lk.get("skin", "#c99a7a")))
	var hair := Color(str(lk.get("hair", "#4a3222")))
	var soft := armor.is_empty() or ashape in ["padded", "leather", "studded", "hide"]
	var legs_c := Color("#4a3a2c") if soft else body_col.darkened(0.1)
	var boots_c := Color("#2a1e16") if lk.get("boots", false) else Color("#3a2a1e")
	var hands_c := Color("#4a3424") if lk.get("gloves", false) else skin
	var pat: int = {"chain": 1, "scale": 2, "studded": 3}.get(ashape, 0)
	var m_body := _mat(body_col, pat)
	var m_sleeve := _mat(body_col if not armor.is_empty() else body_col.lightened(0.05), pat)
	var m_fore := _mat(skin if armor.is_empty() else body_col.darkened(0.05), 0)
	var m_skin := _mat(skin)
	var m_legs := _mat(legs_c)
	var m_boots := _mat(boots_c)
	var m_hands := _mat(hands_c)
	var m_hair := _mat(hair)
	var m_belt := _mat(Color("#3a2a1c"))
	var m_dark := _mat(Color(0.1, 0.08, 0.08), 4)
	var leg := _d("leg", 20)
	var thigh := leg * 0.52
	var shin := leg - thigh - 1.0
	var torso := _d("torso", 15)
	var sh := _d("shoulder", 7.5)
	var waist := _d("waist", 5.5)
	var depth := _d("depth", 4.2)
	var hr := _d("head_r", 8)
	var lr := _d("leg_r", 2.6)
	var ar := _d("arm_r", 2.1)
	var arm := _d("arm", 15)
	# 엉덩이 → 몸통 → 목 → 머리
	var hips := _joint("hips", root, Vector3(0, leg, 0))
	_ball(hips, waist, m_legs, Vector3(0, -0.5, 0), Vector3(1.0, 0.7, depth / waist))
	var chest := _joint("chest", hips, Vector3.ZERO)
	var tm := CylinderMesh.new()  # 몸통: 위가 넓은 납작 원기둥(어깨 → 허리)
	tm.top_radius = sh
	tm.bottom_radius = waist
	tm.height = torso
	tm.radial_segments = 14
	tm.rings = 2
	_mesh(chest, tm, m_body, Vector3(0, torso * 0.5, 0), Vector3.ZERO, Vector3(1, 1, depth / sh))
	_ball(chest, sh, m_body, Vector3(0, torso - 0.6, 0), Vector3(1, 0.42, depth / sh))  # 어깨 윗면(위에서 보이는 둥근 어깨)
	_box(chest, Vector3(waist * 2.0 + 0.6, 1.6, depth * 2.0 * waist / sh + 0.6), m_belt, Vector3(0, 1.2, 0))  # 허리띠
	if ashape == "plate":
		for sx: float in [-1.0, 1.0]:
			_ball(chest, ar * 1.6, _mat(body_col.lightened(0.08)), Vector3(sx * (sh - 0.6), torso - 0.8, 0), Vector3(1, 0.75, 1))
	if lk.get("cloak", false):
		var cl := _mat(Color("#3e2f4a"))
		var cm := CylinderMesh.new()  # 망토: 등 뒤로 퍼지는 반쪽 원기둥 느낌(납작한 원뿔대)
		cm.top_radius = sh * 0.95
		cm.bottom_radius = sh * 1.35
		cm.height = torso + leg * 0.55
		cm.radial_segments = 12
		var cmi := _mesh(chest, cm, cl, Vector3(0, torso - cm.height * 0.5, -depth * 0.55), Vector3(-6, 0, 0), Vector3(1, 1, 0.35))
		cmi.name = "cloak"
	var neck := _joint("neck", chest, Vector3(0, torso, 0))
	_ball(neck, ar * 0.95, m_skin, Vector3(0, 0.8, 0))
	var head := _joint("head", neck, Vector3(0, _d("neck", 2), 0))
	_build_head(head, hr, skin, hair, m_skin, m_hair, m_dark)
	# 팔: 어깨 → 팔꿈치 → 손 (오른손 = 캐릭터 오른쪽 = -x, 앞 = +z)
	for side: String in ["r", "l"]:
		var sx := -1.0 if side == "r" else 1.0
		var shoulder := _joint("shoulder_" + side, chest, Vector3(sx * (sh - ar * 0.4), torso - ar * 0.9, 0))
		_limb(shoulder, ar, arm * 0.5, m_sleeve)
		var elbow := _joint("elbow_" + side, shoulder, Vector3(0, -arm * 0.5, 0))
		_limb(elbow, ar * 0.88, arm * 0.45, m_fore)
		var hand := _joint("hand_" + side, elbow, Vector3(0, -arm * 0.48, 0))
		_ball(hand, ar * 1.05, m_hands, Vector3(0, -0.6, 0.2))
		# 다리: 엉덩이 → 무릎 → 발
		var hip := _joint("hip_" + side, hips, Vector3(sx * waist * 0.5, -0.5, 0))
		_limb(hip, lr, thigh, m_legs)
		var knee := _joint("knee_" + side, hip, Vector3(0, -thigh, 0))
		_limb(knee, lr * 0.9, shin, _mat(boots_c) if lk.get("boots", false) else _mat(legs_c.darkened(0.08)))
		var foot := _joint("foot_" + side, knee, Vector3(0, -shin, 0))
		_box(foot, Vector3(lr * 1.9, lr * 1.0, lr * 3.0), m_boots, Vector3(0, -lr * 0.5, lr * 0.7))
	if "tail" in lk.get("extras", []):
		var tail := _joint("tail", hips, Vector3(0, 0, -depth * 0.8))
		tail.rotation_degrees = Vector3(55, 0, 0)
		_limb(tail, 1.2, 12.0, _mat(skin.darkened(0.15)))
	_build_weapon(lk.get("weapon", {}), j["hand_r"], false)
	_build_weapon(lk.get("offhand", {}), j["hand_l"], true)


func _build_head(head: Node3D, hr: float, skin: Color, hair: Color, m_skin: Material, m_hair: Material, m_dark: Material) -> void:
	var lk := look
	var extras: Array = lk.get("extras", [])
	var c := Vector3(0, hr, 0)
	_ball(head, hr, m_skin, c, Vector3(0.95, 1.0, 0.95))
	# 눈: 앞쪽 두 점(창 1화소), 코 그늘
	for ex: float in [-0.36, 0.36]:
		_box(head, Vector3(1.0, 1.6, 1.0), m_dark, c + Vector3(hr * ex, -hr * 0.05, hr * 0.92))
	var helmet: bool = lk.get("helmet", false)
	if hair.a > 0.01 and not helmet:
		# 머리카락: 정수리·뒤통수를 덮는 반구(앞은 이마까지) + 뒷머리
		var hm := SphereMesh.new()
		hm.radius = hr * 1.07
		hm.height = hr * 1.07
		hm.is_hemisphere = true
		hm.radial_segments = 14
		hm.rings = 5
		_mesh(head, hm, m_hair, c + Vector3(0, hr * 0.22, -hr * 0.04), Vector3(-14, 0, 0))
		_ball(head, hr * 0.9, m_hair, c + Vector3(0, -hr * 0.1, -hr * 0.3), Vector3(1.05, 0.9, 0.85))
	if helmet:
		var steel := _mat(Color(Cutout.material_color("mat_steel")))
		var hm2 := SphereMesh.new()
		hm2.radius = hr * 1.13
		hm2.height = hr * 1.13
		hm2.is_hemisphere = true
		hm2.radial_segments = 14
		hm2.rings = 5
		_mesh(head, hm2, steel, c + Vector3(0, hr * 0.12, -hr * 0.04), Vector3(-10, 0, 0))
		var rim := CylinderMesh.new()
		rim.top_radius = hr * 1.16
		rim.bottom_radius = hr * 1.18
		rim.height = 1.2
		rim.radial_segments = 14
		_mesh(head, rim, _mat(Color(Cutout.material_color("mat_steel")).darkened(0.3)), c + Vector3(0, hr * 0.12, -hr * 0.04), Vector3(-10, 0, 0))
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
			_cone(head, 0.7, 1.8, tc, c + Vector3(hr * sx, -hr * 0.4, hr * 0.85))
	if "snout" in extras:
		_box(head, Vector3(hr * 0.9, hr * 0.6, hr * 0.9), m_skin, c + Vector3(0, -hr * 0.25, hr * 1.0))


## 무기: 손 관절에 붙인다. 막대 방향 = 무기 축(+y가 칼끝) — 손에서 앞쪽 위로 들고 있다.
func _build_weapon(w: Dictionary, hand: Node3D, off: bool) -> void:
	if w.is_empty():
		return
	var shape := str(w.get("shape", ""))
	var c := Color(str(w.get("color", "#c8ccd2")))
	var glow := str(w.get("glow", ""))
	var L := float(w.get("length", 40)) * 0.32
	var steel := _mat(Color(Cutout.material_color("mat_steel")))
	var wood := _mat(Color("#6e4c2c"))
	var g := _joint("weapon_l" if off else "weapon_r", hand, Vector3((1.0 if off else -1.0) * 0.8, -0.8, 1.0))  # 손 바깥·앞(몸에 묻히지 않게)
	if shape == "shield":
		g.rotation_degrees = Vector3(0, 0, 0)
		var sm := CylinderMesh.new()
		sm.top_radius = 5.0
		sm.bottom_radius = 5.0
		sm.height = 1.0
		sm.radial_segments = 14
		_mesh(g, sm, _mat(c), Vector3(1.2, 2.0, 1.0), Vector3(90, 0, 70))
		_ball(g, 1.3, steel, Vector3(1.6, 2.0, 1.6))
		return
	g.rotation_degrees = Vector3(45, 0, 0)  # 축을 앞쪽 위로
	var blade := _mat(Color(glow) if glow != "" else c)
	match shape:
		"sword", "dagger":
			_box(g, Vector3(1.0, 3.0, 1.0), wood, Vector3(0, 0, 0))
			_box(g, Vector3(4.0, 0.9, 1.2), _mat(Color("#8a6a3a")), Vector3(0, 1.8, 0))
			_box(g, Vector3(1.4, L, 0.6), blade, Vector3(0, 2.2 + L * 0.5, 0))
		"axe":
			_box(g, Vector3(0.9, L, 0.9), wood, Vector3(0, L * 0.4, 0))
			_box(g, Vector3(4.0, 3.6, 0.7), steel, Vector3(2.0, L * 0.85, 0))
		"mace":
			_box(g, Vector3(0.9, L, 0.9), wood, Vector3(0, L * 0.4, 0))
			_ball(g, 2.2, blade, Vector3(0, L * 0.9, 0))
		"spear":
			_box(g, Vector3(0.8, L * 1.2, 0.8), wood, Vector3(0, L * 0.45, 0))
			_cone(g, 1.3, 3.5, steel, Vector3(0, L * 1.05 + 1.7, 0))
		"staff":
			g.rotation_degrees = Vector3(12, 0, 0)
			_box(g, Vector3(1.0, L * 1.3, 1.0), _mat(c), Vector3(0, L * 0.4, 0))
			_ball(g, 1.4, _mat(Color("#7fb0d8")), Vector3(0, L * 1.05 + 0.8, 0))
		"bow":
			g.rotation_degrees = Vector3(10, 0, 0)
			var bm := _mat(c)
			for i in 5:
				var t := (float(i) - 2.0) / 2.0
				_box(g, Vector3(0.9, L * 0.26, 0.9), bm, Vector3(0, t * L * 0.4, (1.0 - t * t) * 2.2), Vector3(-t * 35.0, 0, 0))
			_box(g, Vector3(0.3, L * 0.95, 0.3), _mat(Color(0.85, 0.82, 0.75), 4), Vector3(0, 0, 0))
		"crossbow":
			_box(g, Vector3(1.2, L * 0.7, 1.2), _mat(c), Vector3(0, L * 0.3, 0))
			_box(g, Vector3(L * 0.6, 0.8, 0.8), _mat(c.darkened(0.2)), Vector3(0, L * 0.55, 0))
		_:
			_box(g, Vector3(1.0, L * 0.6, 1.0), _mat(c), Vector3(0, L * 0.3, 0))


# ---------- 동작 ----------

## 관절 회전(도)을 정한다. 걷기·서 있기는 계산(박자 = 체형 틀 길이), 한 번 동작은 짧은 키.
func pose(name: String, t: float) -> void:
	for n: Node3D in j.values():
		if n.name != "tail" and not str(n.name).begins_with("weapon"):
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
