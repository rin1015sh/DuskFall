extends RefCounted
## 자연 지형(맵 데이터 art.terrain = "natural"): 부드러운 언덕 + 바위 절벽. 표현 계층만 — 규칙 높이는 칸마다 정수 그대로.
## - 칸마다 (RES+1)×(RES+1) 점. 점 높이 = 걸어서 이어진 칸들(반경 안, 이어짐 = 둘 다 바닥이고 높이 차 1단계 이하 — 3단계 이동 규칙)의
##   규칙 높이를 거리 가중 평균한 값이라, 2칸마다 1단계씩 오르는 길도 계단 없이 곧고 완만한 비탈이 된다.
##   이웃 칸과 공유하는 점은 같은 무리·같은 가중이라 같은 값(틈 없음). 칸 가운데는 규칙 높이와 조금(±0.3 안) 다를 수 있어
##   캐릭터·소품·하이라이트는 ground_at(그려진 바닥)에 세운다. 규칙 판정은 언제나 칸 정수 높이.
## - 이어지지 않은 변(높이 차 2단계 이상)에는 바위 면을 세운다: 높은 칸 변에서 아래로 갈수록 밖으로 퍼져 낮은 땅과 돌무더기 비탈처럼 이어지고,
##   변마다 세로 4줄·단마다 한 줄로 쪼개 안쪽 점을 잡음으로 불룩하게(모서리 세로줄은 맞닿은 면끼리 같은 점).
## - 밝기(입체감): 햇빛 하나(북서쪽 위) 기준 —
##   바닥은 면 방향 음영 + 드리운 그림자(높은 땅이 남동쪽 아래 땅에 그림자, 칸을 4×4로 쪼갠 점마다 햇빛 쪽으로 높이를 훑는다),
##   바위 면은 햇빛을 등진 남쪽 면이 어둡고 위가 밝고 발치가 어둡다, 절벽 위 가장자리는 밝은 테두리. × 빛 단계 어둠.

const V := preload("res://scenes/battle/view3d.gd")
## 햇빛 방향(해 쪽을 가리킴): 북서쪽 위. 그림자는 남동쪽(카메라 쪽)으로 드리워 화면에서 보인다.
const SUN := Vector3(-0.5, 0.8, -0.5)
## 바위 면 밝기 = FACE_BASE + FACE_K × (면 방향·햇빛)
const FACE_BASE := 0.74
const FACE_K := 0.42
## 바닥: 평지 밝기 FLOOR_BASE(셰이더가 1/FLOOR_BASE배로 되돌려 평지는 블록 지형과 같다), 기울기 음영 FLOOR_K
const FLOOR_K := 0.7
const FLOOR_BASE := 0.88
## 드리운 그림자 밝기·반그림자 폭(유닛)·훑는 간격
const SHADOW := 0.58
const PENUMBRA := 0.35
const SHADOW_STEP := 0.2
## 칸당 점 간격 수(바닥 쪼갬)
const RES := 4
const SUB := RES
## 비탈 매끄럽게: 거리 가중 반경(칸)
const SMOOTH_R := 1.25
## 기준 높이와의 차 가중 폭(단계)
const HEIGHT_SIGMA := 0.9
## 바위 면 불룩함(유닛)·아래 퍼짐(유닛, 돌무더기 비탈)
const BULGE := 0.2
const TALUS := 0.42
## 절벽 발치 그늘 밝기
const FOOT_AO := 0.62
## 절벽 위 가장자리 빛 테두리 너비·밝기(흰색 섞음)
const RIM_W := 0.1
const RIM_ALPHA := 0.32

var grid: Node
## 드리운 그림자 캐시(점 → 0..1, 높이만 보므로 빛이 바뀌어도 다시 쓴다)
var _shadow := {}
var _max_h := 0.0
## 칸 → (RES+1)² 높이(줄 = 북→남, 칸 = 서→동)
var vh := {}


func _init(g: Node) -> void:
	grid = g
	var n := RES + 1
	for c: Vector2i in grid.all_cells():
		if _floor(c):
			var arr := PackedFloat32Array()
			arr.resize(n * n)
			for iz in n:
				for ix in n:
					arr[iz * n + ix] = _smooth_h(c, Vector2(c.x + float(ix) / RES, c.y + float(iz) / RES))
			vh[c] = arr
			_max_h = maxf(_max_h, float(grid.height(c)))


func _floor(c: Vector2i) -> bool:
	return grid.in_bounds(c) and not grid.has_flag(c, "wall")


## 걸어서 이어지는 두 칸(바닥이고 높이 차 1 이하)
func linked(a: Vector2i, b: Vector2i) -> bool:
	return _floor(a) and _floor(b) and absi(grid.height(a) - grid.height(b)) <= 1


## 점 p(칸 c의 점)의 높이: c에서 이어짐으로 닿는 칸 중 p 둘레(반경 SMOOTH_R + 0.71) 칸들의 가중 평균.
## 가중 = 거리 가중 × 기준 높이와의 차 가중(차가 2 이상인 칸은 거의 0 — 비탈로 돌아 이어진 절벽 너머가 끼어들어 절벽을 깎지 않게).
## 기준 높이 = p에 맞닿은 칸 중 c와 변으로 이어진 무리의 평균. 둘레 안에서만 이어 가고 기준도 맞닿은 무리로 정하므로
## p를 공유하는 이어진 이웃 칸은 같은 값을 얻는다(틈 없음).
func _smooth_h(c: Vector2i, p: Vector2) -> float:
	var href := _touch_ref(c, p)
	var reach := SMOOTH_R + 0.71
	var group := {c: true}
	var queue: Array[Vector2i] = [c]
	var sw := 0.0
	var sh := 0.0
	while not queue.is_empty():
		var g: Vector2i = queue.pop_back()
		var d := p.distance_to(Vector2(g) + Vector2(0.5, 0.5))
		var w := maxf(0.0, 1.0 - d / reach)
		var dh := float(grid.height(g)) - href
		w *= w * exp(-dh * dh / (HEIGHT_SIGMA * HEIGHT_SIGMA))
		sw += w
		sh += w * grid.height(g)
		for o: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var nb := g + o
			if group.has(nb) or not linked(g, nb):
				continue
			if p.distance_to(Vector2(nb) + Vector2(0.5, 0.5)) > reach:
				continue
			group[nb] = true
			queue.append(nb)
	return sh / sw if sw > 0.0 else href


## p에 맞닿은 칸(1·2·4칸) 중 c와 변으로 이어진 무리의 평균 높이
func _touch_ref(c: Vector2i, p: Vector2) -> float:
	var xs := [floori(p.x)] if not is_equal_approx(p.x, roundf(p.x)) else [roundi(p.x) - 1, roundi(p.x)]
	var zs := [floori(p.y)] if not is_equal_approx(p.y, roundf(p.y)) else [roundi(p.y) - 1, roundi(p.y)]
	var touch := []
	for x: int in xs:
		for z: int in zs:
			touch.append(Vector2i(x, z))
	var group := [c]
	var i := 0
	while i < group.size():
		var g: Vector2i = group[i]
		for o: Vector2i in touch:
			if not o in group and absi(o.x - g.x) + absi(o.y - g.y) == 1 and linked(g, o):
				group.append(o)
		i += 1
	var s := 0.0
	for g: Vector2i in group:
		s += grid.height(g)
	return s / group.size()


## 바닥 높이(칸 평면 점 p). 자연 지형 칸은 점 격자 안에서 쌍선형, 아니면 칸 윗면.
func ground_at(p: Vector2) -> float:
	var c := Vector2i(floori(p.x), floori(p.y))
	if not vh.has(c):
		return V.cell_top(grid, c) if grid.in_bounds(c) else 0.0
	var arr: PackedFloat32Array = vh[c]
	var n := RES + 1
	var fx := clampf(p.x - c.x, 0.0, 1.0) * RES
	var fz := clampf(p.y - c.y, 0.0, 1.0) * RES
	var qx := mini(int(fx), RES - 1)
	var qz := mini(int(fz), RES - 1)
	var u := fx - qx
	var v := fz - qz
	var h00 := arr[qz * n + qx]
	var h10 := arr[qz * n + qx + 1]
	var h01 := arr[(qz + 1) * n + qx]
	var h11 := arr[(qz + 1) * n + qx + 1]
	return lerpf(lerpf(h00, h10, u), lerpf(h01, h11, u), v)


## 바위 면 밝기(면 법선)
static func sun_shade(n: Vector3) -> float:
	return clampf(FACE_BASE + FACE_K * n.normalized().dot(SUN.normalized()), 0.35, 1.0)


## 바닥 밝기(평지 = FLOOR_BASE)
static func floor_shade(n: Vector3) -> float:
	var l := SUN.normalized()
	return clampf(FLOOR_BASE + FLOOR_K * (n.normalized().dot(l) - l.y), 0.45, 1.0)


## 드리운 그림자(0 = 볕, 1 = 그늘): 점에서 해 쪽으로 땅 높이를 훑어 빛줄기보다 높으면 그늘. 가장자리는 반그림자로 부드럽게.
func shadow_at(p: Vector2) -> float:
	var key := Vector2i(roundi(p.x * SUB), roundi(p.y * SUB))
	if _shadow.has(key):
		return _shadow[key]
	var l := SUN.normalized()
	var dir := Vector2(l.x, l.z).normalized()
	var rise := l.y / Vector2(l.x, l.z).length()  # 수평 1유닛마다 빛줄기가 오르는 높이
	var y0 := ground_at(p)
	var top := _max_h - y0
	var amount := 0.0
	var t := SHADOW_STEP * 1.5
	while t * rise < top + PENUMBRA:
		var q := p + dir * t
		var c := Vector2i(floori(q.x), floori(q.y))
		if not vh.has(c):
			if not grid.in_bounds(c):
				break
		else:
			var over := ground_at(q) - (y0 + t * rise)
			amount = maxf(amount, clampf(over / PENUMBRA, 0.0, 1.0))
			if amount >= 1.0:
				break
		t += SHADOW_STEP
	_shadow[key] = amount
	return amount
## 칸 안 점의 기울기 법선(칸 밖으로 나가지 않게 표본)
func _normal_at(c: Vector2i, p: Vector2) -> Vector3:
	var e := 0.2
	var x0 := clampf(p.x - e, c.x, c.x + 1.0)
	var x1 := clampf(p.x + e, c.x, c.x + 1.0)
	var z0 := clampf(p.y - e, c.y, c.y + 1.0)
	var z1 := clampf(p.y + e, c.y, c.y + 1.0)
	var dx := (ground_at(Vector2(x1, p.y)) - ground_at(Vector2(x0, p.y))) / maxf(x1 - x0, 0.001)
	var dz := (ground_at(Vector2(p.x, z1)) - ground_at(Vector2(p.x, z0))) / maxf(z1 - z0, 0.001)
	return Vector3(-dx, 1.0, -dz).normalized()


## 바닥 그물(삼각형, 칸당 SUB×SUB): dark_at(점) → 어둠 0..1. 높이는 ground_at(이웃 칸과 변에서 같은 값).
func build_floor(dark_at: Callable) -> ArrayMesh:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var n := SUB + 1
	for c: Vector2i in vh:
		var pts := []
		var shade := []
		for iz in n:
			for ix in n:
				var p := Vector2(c.x + float(ix) / SUB, c.y + float(iz) / SUB)
				pts.append(Vector3(p.x, (vh[c] as PackedFloat32Array)[iz * n + ix], p.y))
				var k: float = (1.0 - float(dark_at.call(p))) * floor_shade(_normal_at(c, p)) * lerpf(1.0, SHADOW, shadow_at(p))
				shade.append(Color(k, k, k))
		for qz in SUB:
			for qx in SUB:
				var a := qz * n + qx
				for j: int in [a, a + 1, a + n + 1, a, a + n + 1, a + n]:
					verts.append(pts[j])
					cols.append(shade[j])
	return _mesh(verts, cols)


## 바위 면 그물: 이어지지 않은 변마다 높은 칸 변 → 낮은 칸 바닥. dark_of(칸) → 어둠(면이 보는 낮은 칸).
## 맵 가장자리·벽 쪽 변은 만들지 않는다(벽이 덮는다).
## 면은 아래로 갈수록 밖으로 퍼져(TALUS, f²) 아래 땅과 비탈처럼 이어지고, 칸 모서리가 아닌 세로줄은 잡음으로 불룩하다.
## 칸 모서리 세로줄은 그 모서리에 맞닿은 절벽 변들의 바깥 방향을 합쳐 퍼지므로 튀어나온 모서리에서 두 면이 같은 점을 쓴다(틈 없음).
func build_cliffs(dark_of: Callable) -> ArrayMesh:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for c: Vector2i in vh:
		for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var n := c + d
			if not _is_cliff(c, n):
				continue
			var top := _edge(c, d)
			var out := Vector3(d.x, 0, d.y)
			var k := 1.0 - float(dark_of.call(n))
			# 변을 따라 RES+1줄(모서리 … 모서리)
			var cols_top := top
			var flares := []
			for i in top.size():
				flares.append(_corner_flare(c, top[i]) if i == 0 or i == top.size() - 1 else out)
			_face_grid(verts, cols, c, n, cols_top, flares, out, k)
	return _mesh(verts, cols)


## 높은 칸 c → 이웃 n이 절벽(둘 다 바닥, 이어지지 않음, c가 높음)
func _is_cliff(c: Vector2i, n: Vector2i) -> bool:
	return vh.has(c) and vh.has(n) and not linked(c, n) and grid.height(c) > grid.height(n)


## 칸 모서리 점에서의 퍼짐 방향: 칸 c의 그 모서리에 맞닿은 절벽 변들의 바깥 방향 합
func _corner_flare(c: Vector2i, p: Vector3) -> Vector3:
	var sum := Vector3.ZERO
	for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if not _is_cliff(c, c + d):
			continue
		# 이 변이 모서리 p를 지나는가
		var on: bool = (d.x != 0 and is_equal_approx(p.x, c.x + (1.0 if d.x > 0 else 0.0))) or (d.y != 0 and is_equal_approx(p.z, c.y + (1.0 if d.y > 0 else 0.0)))
		if on:
			sum += Vector3(d.x, 0, d.y)
	return sum


## 면 격자: 세로줄마다 위 점 → 아래(퍼진 자리의 바닥), 높이 1단계마다 한 줄
func _face_grid(verts: PackedVector3Array, cols: PackedColorArray, c: Vector2i, n: Vector2i, tops: Array, flares: Array, out: Vector3, k: float) -> void:
	var rows := maxi(2, ceili(float(grid.height(c) - grid.height(n))) + 1)
	var g := []  # [줄][세로줄] 점
	var ao := []
	for r in rows + 1:
		var f := float(r) / rows
		var row := []
		var aorow := []
		for i in tops.size():
			var tp: Vector3 = tops[i]
			var fl: Vector3 = flares[i]
			# 안쪽 세로줄은 퍼짐 폭이 제각각(밑동이 들쭉날쭉), 모서리 세로줄은 맞닿은 면과 같게 고정
			var talus := TALUS if i == 0 or i == tops.size() - 1 else TALUS * (0.45 + 1.1 * _hash3(tp * 3.7))
			var foot := Vector2(tp.x, tp.z) + Vector2(fl.x, fl.z) * talus
			var foot_y := ground_at(foot) if vh.has(Vector2i(floori(foot.x), floori(foot.y))) else float(grid.height(n))
			var off := Vector2(fl.x, fl.z) * talus * f * f
			var p := Vector3(tp.x + off.x, lerpf(tp.y, foot_y, f), tp.z + off.y)
			if r > 0 and r < rows and i > 0 and i < tops.size() - 1:
				p += out * BULGE * (_hash3(p) - 0.3)
			row.append(p)
			aorow.append(clampf(FOOT_AO + (1.0 - FOOT_AO) * (p.y - foot_y) / 0.7, FOOT_AO, 1.0) * (1.0 + 0.16 * clampf(1.0 - (tp.y - p.y) / 0.3, 0.0, 1.0)))
		g.append(row)
		ao.append(aorow)
	for r in rows:
		for i in tops.size() - 1:
			var a: Vector3 = g[r][i]
			var b: Vector3 = g[r][i + 1]
			var cc: Vector3 = g[r + 1][i + 1]
			var d: Vector3 = g[r + 1][i]
			var nrm := (b - a).cross(d - a)
			if nrm.dot(out) < 0.0:
				nrm = -nrm
			var sh := sun_shade(nrm) * k
			var quad := [[a, ao[r][i]], [b, ao[r][i + 1]], [cc, ao[r + 1][i + 1]], [a, ao[r][i]], [cc, ao[r + 1][i + 1]], [d, ao[r + 1][i]]]
			for q: Array in quad:
				verts.append(q[0])
				var v := minf(sh * float(q[1]), 1.0)
				cols.append(Color(v, v, v))


## 칸 c의 d쪽 변의 점들(RES+1개, 변을 따라 x 또는 z가 커지는 순서)
func _edge(c: Vector2i, d: Vector2i) -> Array:
	var arr: PackedFloat32Array = vh[c]
	var n := RES + 1
	var out := []
	for i in n:
		var ix: int = i if d.y != 0 else (0 if d.x < 0 else RES)
		var iz: int = i if d.x != 0 else (0 if d.y < 0 else RES)
		out.append(Vector3(c.x + float(ix) / RES, arr[iz * n + ix], c.y + float(iz) / RES))
	return out


## 절벽 위 가장자리 빛 테두리(높은 칸 쪽, 바닥을 따라) — 볕 받는 턱이 어두운 면과 대비돼 윤곽이 선다
func build_rims() -> ArrayMesh:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var edge := Color(1.0, 0.97, 0.88, RIM_ALPHA)
	var fade := Color(1.0, 0.97, 0.88, 0)
	for c: Vector2i in vh:
		for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var n := c + d
			if not vh.has(n) or linked(c, n) or grid.height(c) <= grid.height(n):
				continue
			var e := _edge(c, d)
			var inward := Vector3(-d.x, 0, -d.y) * RIM_W
			for s in e.size() - 1:
				var a: Vector3 = e[s] + Vector3(0, V.LIFT, 0)
				var b: Vector3 = e[s + 1] + Vector3(0, V.LIFT, 0)
				var ai := a + inward
				var bi := b + inward
				ai.y = ground_at(Vector2(ai.x, ai.z)) + V.LIFT
				bi.y = ground_at(Vector2(bi.x, bi.z)) + V.LIFT
				for q: Array in [[a, edge], [b, edge], [bi, fade], [a, edge], [bi, fade], [ai, fade]]:
					verts.append(q[0])
					cols.append(q[1])
	return _mesh(verts, cols)


## 바위 면이 서는 변 목록(장식·사다리용): [높은 칸, 낮은 칸]
func cliff_edges() -> Array:
	var out := []
	for c: Vector2i in vh:
		for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var n := c + d
			if vh.has(n) and not linked(c, n) and grid.height(c) > grid.height(n):
				out.append([c, n])
	return out


static func _hash3(p: Vector3) -> float:
	var h := sin(p.x * 12.9898 + p.y * 78.233 + p.z * 37.719) * 43758.5453
	return h - floorf(h)


static func _mesh(verts: PackedVector3Array, cols: PackedColorArray) -> ArrayMesh:
	var m := ArrayMesh.new()
	if verts.is_empty():
		return m
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
