extends Node2D
## 2D 일러스트 컷아웃 캐릭터(룰북 1단계 '스프라이트 방향', 표현 계층): Skeleton2D 뼈대 + 부위 그림.
## 체형 틀의 뼈(data/rules/body_templates.json)에 부위를 붙이고, 뼈 회전 키 애니메이션으로 움직인다.
## 부위 그림은 assets/cutout/<체형>/<부위>.png가 있으면 그 그림, 없으면 코드로 그린 임시 그림(그라데이션 면 + 외곽선 + 북서쪽 빛).
## 앞쪽 대각선(front)·뒤쪽 대각선(back) 두 방향을 그리고 좌우 반전으로 4방향을 만든다. 장비는 부위 그림을 갈아 끼우고(Cutout.look),
## 재질·등급은 색 바꾸기로 표현한다. 그림 규격: docs/art/cutout_spec.md.

const Cutout := preload("res://scripts/rules/cutout.gd")
const ART_DIR := "res://assets/cutout"
const OUTLINE := Color(0.09, 0.07, 0.06, 0.95)
## 도트 그림 모드(도트 화면이 켜질 때 battle_scene이 정한다): 켜면 그림 px → 도트 배율 dot으로 줄여 도트 해상도 캔버스에 그린다.
## 부위마다 북서쪽 빛 3단 음영(왼쪽 위 밝은 테·가운데 본색·오른쪽 아래 그늘 테 — 밝은 쪽 따뜻하게, 그늘 차갑게), 부위 테두리 1도트 어두운 선,
## 무늬·눈은 도트 점. 장비 구조(부위 갈아 끼우기·재질 색·갑옷/무기 모양·등급 빛)는 그대로. 끄면 옛 매끈한 그림.
static var pixel := false
## 이 뼈대의 도트 배율(그림 px당 도트, 0 = 매끈한 그림). 맵 캐릭터 = 화면 도트(actor_view), 초상 = PORTRAIT_DOT.
var dot := 0.0

var look: Dictionary = {}
var tpl: Dictionary = {}
var view := "front"
var mirror := false
var anim := "idle"
var anim_t := 0.0
var skeleton: Skeleton2D
var bones := {}  # id → Bone2D
var _parts: Array = []
var _rest := {}  # id → 기본 회전(도)


## 모습을 입힌다(같은 key면 다시 만들지 않는다).
func apply_look(lk: Dictionary) -> void:
	if not look.is_empty() and str(look.get("key", "")) == str(lk.get("key", "")):
		return
	look = lk
	tpl = Cutout.template(str(lk.get("template", "medium")))
	_build()


## 방향: facing 0 아래·1 왼·2 오른·3 위 → 앞쪽 대각선(오른쪽을 봄)·뒤쪽 대각선, 왼쪽은 좌우 반전.
func set_facing(facing: int) -> void:
	var v := "back" if facing == 3 else "front"
	var m := facing == 1
	if v != view or m != mirror:
		view = v
		mirror = m
		scale.x = (-1.0 if mirror else 1.0) * _s()
		_order_parts()
		for p: Node in _parts:
			p.queue_redraw()


## 애니메이션: idle · walk(반복) / attack_melee · attack_ranged · cast · hit(한 번 — 끝나면 idle).
func play(name: String) -> void:
	if name == anim and _loop(name):
		return
	anim = name
	anim_t = 0.0


func _loop(name: String) -> bool:
	return bool(tpl.get("animations", {}).get(name, {}).get("loop", true))


func _process(delta: float) -> void:
	if tpl.is_empty():
		return
	var a: Dictionary = tpl.get("animations", {}).get(anim, {})
	if a.is_empty():
		return
	anim_t += delta
	var length := float(a.get("length", 1.0))
	if anim_t > length:
		if bool(a.get("loop", true)):
			anim_t = fmod(anim_t, length)
		else:
			play("idle")
			return
	pose(anim, anim_t)


## 뼈 회전을 키(도)에서 선형 보간해 놓는다. 키가 없는 뼈는 기본 자세.
func pose(name: String, t: float) -> void:
	var keys: Dictionary = tpl.get("animations", {}).get(name, {}).get("keys", {})
	for id: String in bones:
		var deg: float = _rest.get(id, 0.0)
		if keys.has(id):
			deg += _sample(keys[id], t)
		bones[id].rotation = deg_to_rad(deg)


static func _sample(k: Array, t: float) -> float:
	if k.is_empty():
		return 0.0
	if t <= float(k[0][0]):
		return float(k[0][1])
	for i in range(1, k.size()):
		var t0 := float(k[i - 1][0])
		var t1 := float(k[i][0])
		if t <= t1:
			var u := (t - t0) / maxf(t1 - t0, 0.0001)
			return lerpf(float(k[i - 1][1]), float(k[i][1]), u)
	return float(k[k.size() - 1][1])


# ---------- 만들기 ----------

func _build() -> void:
	for ch in get_children():
		ch.queue_free()
	bones.clear()
	_parts.clear()
	_rest.clear()
	var canvas: Array = tpl.get("canvas", [160, 240])
	position = Vector2(float(canvas[0]) * 0.5, float(canvas[1]) - 12.0) * _s()  # 원점 = 발 사이 바닥(그림 아래에서 12px 위)
	scale = Vector2((-1.0 if mirror else 1.0) * _s(), _s())
	skeleton = Skeleton2D.new()
	add_child(skeleton)
	for b: Dictionary in tpl.get("bones", []):
		var bone := Bone2D.new()
		bone.name = str(b["id"])
		bone.position = Vector2(float(b["x"]), float(b["y"]))
		bone.set_autocalculate_length_and_angle(false)
		bone.set_length(maxf(float(b["len"]), 1.0))
		bone.set_bone_angle(PI * 0.5)
		var parent: Node = skeleton if str(b["parent"]) == "" else bones.get(str(b["parent"]), skeleton)
		parent.add_child(bone)
		bone.rest = bone.transform
		bones[str(b["id"])] = bone
		_rest[str(b["id"])] = 0.0
	_add_parts()
	_order_parts()
	pose(anim, anim_t)


## 그림 px → 캔버스 배율(도트 그림이면 dot, 아니면 1)
func _s() -> float:
	return dot if dot > 0.0 else 1.0


## 도트 그림 캔버스 크기(도트) — 그림 캔버스 × dot, 올림
func canvas_px() -> Vector2i:
	var canvas: Array = tpl.get("canvas", [160, 240])
	return Vector2i(ceili(float(canvas[0]) * _s()), ceili(float(canvas[1]) * _s()))


## 발에서 머리 꼭대기까지(그림 px) — 머리 위 HP 막대 높이.
func height_px() -> float:
	var y := 0.0
	for b: Dictionary in tpl.get("bones", []):
		if str(b["id"]) in ["hips", "torso", "neck", "head"]:
			y += absf(float(b["y"])) if str(b["id"]) != "torso" else 0.0
	return y + _bone_len("head") + 6.0


func _bone_len(id: String) -> float:
	for b: Dictionary in tpl.get("bones", []):
		if str(b["id"]) == id:
			return float(b["len"])
	return 10.0


func _prop(k: String, d: float) -> float:
	return float(tpl.get("proportions", {}).get(k, d))


## 부위를 뼈에 붙인다. 부위 id는 그리기 순서(draw_order)의 이름.
func _add_parts() -> void:
	var armor: Dictionary = look.get("armor", {})
	var body_col := Color(str(armor.get("color", look.get("tunic", "#6b5a48")))) if not armor.is_empty() else Color(str(look.get("tunic", "#6b5a48")))
	var skin := Color(str(look.get("skin", "#c99a7a")))
	var hair := Color(str(look.get("hair", "#4a3222")))
	var limb_w := _prop("limb_w", 9.0)
	var sleeve := body_col if not armor.is_empty() else body_col.lightened(0.05)
	var legs := Color("#4a3a2c") if armor.is_empty() or str(armor.get("shape", "")) in ["padded", "leather", "studded", "hide"] else body_col.darkened(0.1)
	var boots := Color("#3a2a1e") if not look.get("boots", false) else Color("#2a1e16")
	var hands := skin if not look.get("gloves", false) else Color("#4a3424")
	_part("cloak", "torso", "cloak", Color("#3e2f4a") if look.get("cloak", false) else Color(0, 0, 0, 0), {"show": look.get("cloak", false)})
	for side: String in ["far", "near"]:
		_part("upper_arm_" + side, "upper_arm_" + side, "limb", sleeve, {"w": limb_w, "len": _bone_len("upper_arm_" + side)})
		_part("lower_arm_" + side, "lower_arm_" + side, "limb", skin if armor.is_empty() else sleeve.darkened(0.05), {"w": limb_w * 0.85, "len": _bone_len("lower_arm_" + side)})
		_part("hand_" + side, "hand_" + side, "hand", hands, {"r": limb_w * 0.55})
		_part("thigh_" + side, "thigh_" + side, "limb", legs, {"w": limb_w * 1.25, "len": _bone_len("thigh_" + side)})
		_part("shin_" + side, "shin_" + side, "limb", boots if look.get("boots", false) else legs.darkened(0.08), {"w": limb_w * 1.05, "len": _bone_len("shin_" + side)})
		_part("foot_" + side, "foot_" + side, "foot", boots, {"r": limb_w * 0.75})
	_part("torso", "torso", "torso", body_col, {"len": _bone_len("torso"), "top": _prop("shoulder_w", 34.0), "bottom": _prop("waist_w", 24.0), "armor": str(armor.get("shape", "")), "rarity": str(armor.get("rarity", "common"))})
	_part("neck", "neck", "limb", skin, {"w": limb_w * 0.9, "len": _bone_len("neck"), "up": true})
	_part("head", "head", "head", skin, {"r": _prop("head_r", 12.0), "extras": look.get("extras", [])})
	_part("hair", "head", "hair", hair, {"r": _prop("head_r", 12.0), "show": hair.a > 0.01 and not look.get("helmet", false)})
	var extras: Array = look.get("extras", [])
	_part("ears", "head", "ears", skin, {"r": _prop("head_r", 12.0), "show": "ears_pointed" in extras})
	_part("horns", "head", "horns", Color("#3a2e2a"), {"r": _prop("head_r", 12.0), "show": "horns" in extras})
	_part("beard", "head", "beard", hair, {"r": _prop("head_r", 12.0), "show": "beard" in extras or "tusks" in extras or "snout" in extras, "kind": "tusks" if "tusks" in extras else ("snout" if "snout" in extras else "beard"), "skin": skin})
	_part("helmet", "head", "helmet", Color(Cutout.material_color("mat_steel")), {"r": _prop("head_r", 12.0), "show": look.get("helmet", false)})
	_part("tail", "hips", "tail", skin.darkened(0.15), {"show": "tail" in extras})
	var w: Dictionary = look.get("weapon", {})
	_part("weapon", "hand_near", "weapon", Color(str(w.get("color", "#c8ccd2"))), {"show": not w.is_empty(), "shape": str(w.get("shape", "")), "len": float(w.get("length", 40)), "glow": str(w.get("glow", "")), "rarity": str(w.get("rarity", "common"))})
	var o: Dictionary = look.get("offhand", {})
	_part("offhand", "hand_far", "weapon", Color(str(o.get("color", "#7a5a36"))), {"show": not o.is_empty(), "shape": str(o.get("shape", "")), "len": float(o.get("length", 30)), "glow": str(o.get("glow", "")), "rarity": str(o.get("rarity", "common"))})


func _part(id: String, bone_id: String, kind: String, col: Color, params: Dictionary) -> void:
	if not params.get("show", true):
		return
	var bone: Node = bones.get(bone_id)
	if bone == null:
		return
	var path := "%s/%s/%s.png" % [ART_DIR, str(tpl.get("id", "medium")), id]
	var node: Node2D
	if ResourceLoader.exists(path):
		var spr := Sprite2D.new()  # 그린 그림이 있으면 그것(기준점 = 뼈 시작점, docs/art/cutout_spec.md)
		spr.texture = load(path)
		spr.centered = false
		spr.offset = Vector2(-spr.texture.get_size().x * 0.5, 0)
		spr.self_modulate = col if kind in ["torso", "limb"] and id != "neck" else Color.WHITE
		node = spr
	else:
		var p := Part.new()
		p.kind = kind
		p.col = col
		p.params = params
		p.rig = self
		node = p
	node.name = "part_" + id
	node.set_meta("part_id", id)
	node.z_as_relative = false
	bone.add_child(node)
	_parts.append(node)


## 그리기 순서(앞·뒤 대각선마다 다르다): 목록 순서 = z.
func _order_parts() -> void:
	var order: Array = tpl.get("draw_order", {}).get(view, [])
	for p: Node2D in _parts:
		var i := order.find(str(p.get_meta("part_id")))
		p.z_index = i if i >= 0 else order.size()
		if str(p.get_meta("part_id")) == "tail":
			p.z_index = -1 if view == "front" else order.size() + 1
		p.visible = true


# ---------- 임시 부위 그림(코드) ----------

class Part extends Node2D:
	var kind := ""
	var col := Color.WHITE
	var params := {}
	var rig: Node2D

	func _draw() -> void:
		var front: bool = rig.view == "front"
		match kind:
			"limb":
				_capsule(float(params.get("w", 8.0)), float(params.get("len", 20.0)) * (-1.0 if params.get("up", false) else 1.0))
			"hand":
				_blob(Vector2(0, 4), float(params.get("r", 5.0)), float(params.get("r", 5.0)))
			"foot":
				var r := float(params.get("r", 6.0))
				_blob(Vector2(r * 0.6, 2), r * 1.4, r * 0.75)
			"torso":
				_torso(front)
			"head":
				_head(front)
			"hair":
				_hair(front)
			"ears":
				var r2 := float(params.get("r", 12.0))
				var ep := PackedVector2Array([Vector2(-r2 * 0.6, -r2 * 1.05), Vector2(-r2 * 1.6, -r2 * 1.7), Vector2(-r2 * 0.8, -r2 * 0.7)])
				_poly(ep, col)
			"horns":
				var r3 := float(params.get("r", 12.0))
				for sx: float in [-0.45, 0.35]:
					var hp := PackedVector2Array([Vector2(r3 * sx - 2, -r3 * 1.75), Vector2(r3 * sx - 8, -r3 * 2.7), Vector2(r3 * sx + 3, -r3 * 1.85)])
					_poly(hp, col)
			"beard":
				_beard(front)
			"helmet":
				var r4 := float(params.get("r", 12.0))
				var pts := PackedVector2Array()
				for i in 13:
					var a := PI + PI * i / 12.0
					pts.append(Vector2(cos(a) * r4 * 1.12, -r4 + sin(a) * r4 * 1.12))
				pts.append(Vector2(r4 * 1.15, -r4 * 0.6))
				pts.append(Vector2(-r4 * 1.15, -r4 * 0.6))
				_poly(pts, col)
				_line(Vector2(-r4 * 1.1, -r4 * 0.62), Vector2(r4 * 1.1, -r4 * 0.62), col.darkened(0.35), 2.0)
			"cloak":
				var L := float(rig._bone_len("torso"))
				var w := float(rig._prop("shoulder_w", 34.0))
				_poly(PackedVector2Array([Vector2(-w * 0.55, -L), Vector2(w * 0.55, -L), Vector2(w * 0.75, L * 1.4), Vector2(-w * 0.8, L * 1.45)]), col)
			"tail":
				var tp := PackedVector2Array()
				for i in 10:
					var t := i / 9.0
					tp.append(Vector2(-t * 34.0, 6 + sin(t * 3.0) * 10.0 + t * 18.0))
				var tpx := _px()
				if tpx <= 0.0:  # 도트 모드는 화면 외곽선이 두른다
					draw_polyline(tp, OUTLINE, 6.0)
				draw_polyline(tp, col, tpx * 2.0 if tpx > 0.0 else 4.0)
			"weapon":
				_weapon()

	## 도트 그림 모드면 1도트(부위 좌표 단위), 아니면 0
	func _px() -> float:
		return 1.0 / rig.dot if rig.dot > 0.0 else 0.0

	## 선(도트 모드면 1도트 굵기·계단 선)
	func _line(a: Vector2, b: Vector2, c: Color, w: float) -> void:
		var px := _px()
		draw_line(a, b, c, px if px > 0.0 else w, px <= 0.0)

	## 점(눈·무늬): 도트 모드면 1도트 네모, 아니면 원
	func _dot(p: Vector2, r: float, c: Color) -> void:
		var px := _px()
		if px > 0.0:
			draw_rect(Rect2(p - Vector2(px, px) * 0.5, Vector2(px, px)), c)
		else:
			draw_circle(p, r, c)

	## 도트 3단 음영: 본색 면, 왼쪽 위 테(1도트) 밝게·따뜻하게, 오른쪽 아래 테(1~2도트) 어둡게·차갑게.
	## 부위마다 검은 테두리는 두르지 않는다 — 몸 윤곽은 화면 외곽선(pixel_outline, 제 색의 어두운 쪽)이 1도트로 고르게 두른다
	func _poly_px(pts: PackedVector2Array, c: Color) -> void:
		var px := _px()
		var hi := c.lightened(0.24).lerp(Color(1.0, 0.92, 0.7), 0.08)
		var lo := c.darkened(0.24).lerp(Color(0.2, 0.22, 0.38), 0.1)
		draw_colored_polygon(pts, c)
		var sh := PackedVector2Array()
		for p in pts:
			sh.append(p + Vector2(px, px))
		for piece: PackedVector2Array in Geometry2D.clip_polygons(pts, sh):
			if piece.size() >= 3:  # 볼록에 가까운 부위 − 밀린 자기 = 초승달(구멍 없음)
				draw_colored_polygon(piece, hi)
		var sl := PackedVector2Array()
		for p in pts:
			sl.append(p - Vector2(px, px))
		for piece2: PackedVector2Array in Geometry2D.clip_polygons(pts, sl):
			if piece2.size() >= 3:
				draw_colored_polygon(piece2, lo)

	## 면 + 북서쪽 빛(왼쪽 위 밝게, 오른쪽 아래 어둡게) + 외곽선
	func _poly(pts: PackedVector2Array, c: Color) -> void:
		if _px() > 0.0:
			_poly_px(pts, c)
			return
		var cols := PackedColorArray()
		var lo := pts[0]
		var hi := pts[0]
		for p in pts:
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		var span := (hi - lo)
		for p in pts:
			var u := ((p.x - lo.x) / maxf(span.x, 1.0) + (p.y - lo.y) / maxf(span.y, 1.0)) * 0.5
			cols.append(c.lightened(0.18 * (1.0 - u)).darkened(0.22 * u))
		draw_polygon(pts, cols)
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, OUTLINE, 1.6, true)

	## 팔다리: 뼈 시작점에서 length만큼(음수면 위로) 이어진 둥근 막대.
	func _capsule(w: float, length: float) -> void:
		var r := w * 0.5
		var sg := 1.0 if length >= 0.0 else -1.0
		var all := PackedVector2Array()
		for i in 9:
			var a := PI * i / 8.0
			all.append(Vector2(-cos(a) * r, -sin(a) * r * sg))
		for i in 9:
			var a2 := PI * i / 8.0
			all.append(Vector2(cos(a2) * r * 0.9, length + sin(a2) * r * 0.9 * sg))
		_poly(all, col)

	func _blob(c: Vector2, rx: float, ry: float) -> void:
		var pts := PackedVector2Array()
		for i in 16:
			var a := TAU * i / 16.0
			pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		_poly(pts, col)

	func _torso(front: bool) -> void:
		var L := float(params.get("len", 46.0))
		var top := float(params.get("top", 34.0)) * 0.5
		var bot := float(params.get("bottom", 24.0)) * 0.5
		var pts := PackedVector2Array([Vector2(-bot, 8), Vector2(-bot - 2, -L * 0.45), Vector2(-top, -L + 6), Vector2(-top * 0.6, -L),
			Vector2(top * 0.6, -L), Vector2(top, -L + 6), Vector2(bot + 2, -L * 0.45), Vector2(bot, 8)])
		_poly(pts, col)
		var shape := str(params.get("armor", ""))
		# 갑옷 무늬(임시): 사슬·비늘 점, 판금 가슴판·어깨, 징 박힌 가죽 징, 허리띠
		match shape:
			"chain", "scale", "studded":
				var step := 5.0 if shape != "studded" else 7.0
				if _px() > 0.0:
					step = _px() * (3.0 if shape != "studded" else 4.0)  # 도트 무늬: 3~4도트 간격
				var y := -L + 8.0
				while y < 4.0:
					var x := -bot
					while x < bot:
						_dot(Vector2(x + (2.5 if int(y) % 2 == 0 else 0.0), y), 1.0 if shape != "studded" else 1.3, col.lightened(0.35) if shape != "scale" else col.darkened(0.25))
						x += step
					y += step * 0.8
			"plate", "breastplate":
				_line(Vector2(0, -L + 4), Vector2(0, 2), col.lightened(0.4), 1.5)
				if shape == "plate":
					for sx: float in [-1.0, 1.0]:
						_pauldron(Vector2(sx * top * 0.95, -L + 6))
		if not front:
			_line(Vector2(0, -L + 2), Vector2(0, 6), col.darkened(0.3), 1.2)  # 등 솔기
		draw_rect(Rect2(-bot - 1, 1, bot * 2 + 2, 4), Color("#3a2a1c"))  # 허리띠
		var rar := str(params.get("rarity", "common"))
		if rar != "common":
			var glow: Color = {"uncommon": Color(0.4, 0.9, 0.4, 0.7), "rare": Color(0.4, 0.6, 1.0, 0.8), "very_rare": Color(0.75, 0.45, 1.0, 0.85), "legendary": Color(1.0, 0.75, 0.3, 0.9)}.get(rar, Color.WHITE)
			var closed := pts.duplicate()
			closed.append(pts[0])
			draw_polyline(closed, glow, _px() if _px() > 0.0 else 1.2, _px() <= 0.0)  # 등급 — 색 바꾸기(테두리 빛)

	func _pauldron(c: Vector2) -> void:
		var pts := PackedVector2Array()
		for i in 10:
			var a := PI + PI * i / 9.0
			pts.append(c + Vector2(cos(a) * 9.0, sin(a) * 7.0 + 3.0))
		_poly(pts, col.lightened(0.08))

	func _head(front: bool) -> void:
		var r := float(params.get("r", 12.0))
		var c := Vector2(0, -r)
		var pts := PackedVector2Array()
		for i in 20:
			var a := TAU * i / 20.0
			pts.append(c + Vector2(cos(a) * r * 0.95, sin(a) * r * 1.08))
		if front:
			pts.append(c + Vector2(r * 1.02, r * 0.2))  # 앞쪽 대각선: 턱·코 쪽으로 살짝
		_poly(pts, col)
		if front:
			for ex: float in [0.15, 0.62]:
				_dot(c + Vector2(r * ex, -r * 0.05), 1.4, Color(0.12, 0.09, 0.08))
			if _px() <= 0.0:
				draw_line(c + Vector2(r * 0.85, r * 0.05), c + Vector2(r * 0.95, r * 0.25), col.darkened(0.3), 1.0)
				draw_line(c + Vector2(r * 0.3, r * 0.5), c + Vector2(r * 0.65, r * 0.48), col.darkened(0.4), 1.0)

	func _hair(front: bool) -> void:
		var r := float(params.get("r", 12.0))
		var c := Vector2(0, -r)
		var pts := PackedVector2Array()
		if front:
			for i in 14:
				var a := PI * 0.95 + PI * 1.15 * i / 13.0
				pts.append(c + Vector2(cos(a) * r * 1.05, sin(a) * r * 1.14))
			pts.append(c + Vector2(-r * 0.2, -r * 0.35))
			pts.append(c + Vector2(-r * 1.05, r * 0.55))
		else:
			for i in 20:
				var a := TAU * i / 20.0
				pts.append(c + Vector2(cos(a) * r * 1.02, sin(a) * r * 1.12 + (r * 0.15 if sin(a) > 0 else 0.0)))
		_poly(pts, col)

	func _beard(front: bool) -> void:
		var r := float(params.get("r", 12.0))
		var c := Vector2(0, -r)
		match str(params.get("kind", "beard")):
			"beard":
				if front:
					_poly(PackedVector2Array([c + Vector2(-r * 0.2, r * 0.3), c + Vector2(r * 1.0, r * 0.15), c + Vector2(r * 0.6, r * 1.5), c + Vector2(-r * 0.1, r * 1.2)]), col)
			"tusks":
				if front:
					for tx: float in [0.35, 0.75]:
						_poly(PackedVector2Array([c + Vector2(r * tx - 1.5, r * 0.45), c + Vector2(r * tx + 1.5, r * 0.45), c + Vector2(r * tx, r * 0.05)]), Color("#ece2cc"))
			"snout":
				if front:
					_poly(PackedVector2Array([c + Vector2(r * 0.4, -r * 0.2), c + Vector2(r * 1.7, r * 0.15), c + Vector2(r * 1.6, r * 0.55), c + Vector2(r * 0.4, r * 0.6)]), params.get("skin", col))

	## 무기(손에서 위로): 칼·도끼·둔기·창·지팡이·단검·활·석궁·투석구·총·방패
	func _weapon() -> void:
		var L := float(params.get("len", 40.0))
		var shape := str(params.get("shape", "sword"))
		var c := col
		var wood := Color("#6e4c2c")
		var glow_s := str(params.get("glow", ""))
		if glow_s != "":
			if _px() <= 0.0:
				draw_circle(Vector2(0, -L * 0.55), L * 0.45, Color(Color(glow_s), 0.18))
		match shape:
			"sword", "dagger":
				_poly(PackedVector2Array([Vector2(-2.2, -6), Vector2(2.2, -6), Vector2(1.6, -L), Vector2(0, -L - 5), Vector2(-1.6, -L)]), Color(glow_s) if glow_s != "" else c)
				_poly(PackedVector2Array([Vector2(-7, -6), Vector2(7, -6), Vector2(7, -3), Vector2(-7, -3)]), Color("#8a6a3a"))
				_poly(PackedVector2Array([Vector2(-1.8, -3), Vector2(1.8, -3), Vector2(1.8, 6), Vector2(-1.8, 6)]), wood)
			"axe":
				_poly(PackedVector2Array([Vector2(-1.6, 8), Vector2(1.6, 8), Vector2(1.6, -L), Vector2(-1.6, -L)]), wood)
				_poly(PackedVector2Array([Vector2(1, -L + 2), Vector2(13, -L - 5), Vector2(15, -L + 10), Vector2(1, -L + 12)]), Color(Cutout.material_color("mat_steel")))
			"mace":
				_poly(PackedVector2Array([Vector2(-1.8, 8), Vector2(1.8, 8), Vector2(1.8, -L + 6), Vector2(-1.8, -L + 6)]), wood if c == Color(Cutout.material_color("mat_wood")) else c.darkened(0.3))
				_blob_at(Vector2(0, -L + 2), 6.5, 7.5, c)
			"spear":
				_poly(PackedVector2Array([Vector2(-1.4, 14), Vector2(1.4, 14), Vector2(1.4, -L), Vector2(-1.4, -L)]), wood)
				_poly(PackedVector2Array([Vector2(-3.5, -L), Vector2(3.5, -L), Vector2(0, -L - 12)]), Color(Cutout.material_color("mat_steel")))
			"staff":
				_poly(PackedVector2Array([Vector2(-2, 16), Vector2(2, 16), Vector2(2, -L), Vector2(-2, -L)]), c)
				_blob_at(Vector2(0, -L - 3), 3.5, 3.5, Color("#7fb0d8"))
			"bow":
				var pts := PackedVector2Array()
				for i in 13:
					var a := -PI * 0.5 + PI * i / 12.0
					pts.append(Vector2(-cos(a) * L * 0.2 - 2, sin(a) * L * 0.5))
				var bpx := _px()
				if bpx <= 0.0:
					draw_polyline(pts, OUTLINE, 4.5)
				draw_polyline(pts, c, bpx if bpx > 0.0 else 3.0)
				_line(pts[0], pts[pts.size() - 1], Color(0.85, 0.82, 0.75), 1.0)
			"crossbow":
				_poly(PackedVector2Array([Vector2(-2, 4), Vector2(2, 4), Vector2(2, -L * 0.7), Vector2(-2, -L * 0.7)]), c)
				var cpx := _px()
				if cpx <= 0.0:
					draw_line(Vector2(-L * 0.35, -L * 0.6), Vector2(L * 0.35, -L * 0.6), OUTLINE, 4.0)
				draw_line(Vector2(-L * 0.35, -L * 0.6), Vector2(L * 0.35, -L * 0.6), c.darkened(0.2), cpx if cpx > 0.0 else 2.5)
			"shield":
				_blob_at(Vector2(-2, -2), 13, 15, c)
				_dot(Vector2(-2, -2), 3.0, Color(Cutout.material_color("mat_steel")))
			_:
				_poly(PackedVector2Array([Vector2(-1.5, 4), Vector2(1.5, 4), Vector2(1.5, -L * 0.6), Vector2(-1.5, -L * 0.6)]), c)
		var rar := str(params.get("rarity", "common"))
		if rar != "common":
			var glow: Color = {"uncommon": Color(0.4, 0.9, 0.4, 0.35), "rare": Color(0.4, 0.6, 1.0, 0.4), "very_rare": Color(0.75, 0.45, 1.0, 0.45), "legendary": Color(1.0, 0.75, 0.3, 0.5)}.get(rar, Color.WHITE)
			if _px() > 0.0:
				_dot(Vector2(0, -L * 0.6), 5.0, Color(glow, 1.0))
			else:
				draw_circle(Vector2(0, -L * 0.6), 5.0, glow)

	func _blob_at(c: Vector2, rx: float, ry: float, colr: Color) -> void:
		var pts := PackedVector2Array()
		for i in 16:
			var a := TAU * i / 16.0
			pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		_poly(pts, colr)
