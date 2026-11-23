extends RefCounted
## 자연 지형(맵 데이터 art.terrain = "natural"): 부드러운 언덕 + 바위 절벽. 표현 계층만 — 규칙 높이는 칸마다 정수 그대로.
## - 칸을 2×2로 쪼갠 3×3 점. 가운데 점 = 그 칸 높이(캐릭터가 서는 곳 = 규칙 높이).
##   변 가운데·모서리 점은 '이어진' 칸끼리 높이를 평균한다. 이어짐 = 둘 다 바닥이고 높이 차 1단계 이하(걸어서 오르내리는 차 — 3단계 이동 규칙).
##   모서리는 그 점을 둘러싼 네 칸 중 변으로 이어진 무리의 평균이라 이웃 칸끼리 같은 값을 쓴다(틈이 없다).
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
## 바닥 쪼갬(칸당)
const SUB := 4
## 바위 면 불룩함(유닛)·아래 퍼짐(유닛, 돌무더기 비탈)·변당 세로줄 수
const BULGE := 0.2
const TALUS := 0.42
const COLS := 4
## 절벽 발치 그늘 밝기
const FOOT_AO := 0.62
## 절벽 위 가장자리 빛 테두리 너비·밝기(흰색 섞음)
const RIM_W := 0.1
const RIM_ALPHA := 0.32

var grid: Node
## 드리운 그림자 캐시(점 → 0..1, 높이만 보므로 빛이 바뀌어도 다시 쓴다)
var _shadow := {}
var _max_h := 0.0
## 칸 → 3×3 높이(줄 = 북→남, 칸 = 서→동)
var vh := {}


func _init(g: Node) -> void:
	grid = g
	for c: Vector2i in grid.all_cells():
		if _floor(c):
			var arr := PackedFloat32Array()
			arr.resize(9)
			for iz in 3:
				for ix in 3:
					arr[iz * 3 + ix] = _vertex_h(c, ix, iz)
			vh[c] = arr
			_max_h = maxf(_max_h, float(grid.height(c)))


func _floor(c: Vector2i) -> bool:
	return grid.in_bounds(c) and not grid.has_flag(c, "wall")


## 걸어서 이어지는 두 칸(바닥이고 높이 차 1 이하)
func linked(a: Vector2i, b: Vector2i) -> bool:
	return _floor(a) and _floor(b) and absi(grid.height(a) - grid.height(b)) <= 1


func _vertex_h(c: Vector2i, ix: int, iz: int) -> float:
	var h := float(grid.height(c))
	if ix == 1 and iz == 1:
		return h
	if ix == 1 or iz == 1:
		var n := c + Vector2i(ix - 1, iz - 1)
		return (h + grid.height(n)) * 0.5 if linked(c, n) else h
	# 모서리 점(px, pz)을 둘러싼 네 칸 중 c와 변으로 이어진 무리의 평균
	var px := c.x + ix / 2
	var pz := c.y + iz / 2
	var around := [Vector2i(px - 1, pz - 1), Vector2i(px, pz - 1), Vector2i(px - 1, pz), Vector2i(px, pz)]
	var group := [c]
	var i := 0
	while i < group.size():
		var g: Vector2i = group[i]
		for o: Vector2i in around:
			if not o in group and absi(o.x - g.x) + absi(o.y - g.y) == 1 and linked(g, o):
				group.append(o)
		i += 1
	var s := 0.0
	for g: Vector2i in group:
		s += grid.height(g)
	return s / group.size()


## 바닥 높이(칸 평면 점 p). 자연 지형 칸은 2×2 조각 안에서 쌍선형, 아니면 칸 윗면.
func ground_at(p: Vector2) -> float:
	var c := Vector2i(floori(p.x), floori(p.y))
	if not vh.has(c):
		return V.cell_top(grid, c) if grid.in_bounds(c) else 0.0
	var arr: PackedFloat32Array = vh[c]
	var fx := clampf(p.x - c.x, 0.0, 1.0) * 2.0
	var fz := clampf(p.y - c.y, 0.0, 1.0) * 2.0
	var qx := mini(int(fx), 1)
	var qz := mini(int(fz), 1)
	var u := fx - qx
	var v := fz - qz
	var h00 := arr[qz * 3 + qx]
	var h10 := arr[qz * 3 + qx + 1]
	var h01 := arr[(qz + 1) * 3 + qx]
	var h11 := arr[(qz + 1) * 3 + qx + 1]
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
				pts.append(Vector3(p.x, ground_at(p), p.y))
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
			# 변을 따라 4줄(모서리·¼·가운데·¾·모서리)
			var cols_top := []
			var flares := []
			for i in COLS + 1:
				var f := float(i) / COLS
				var tp: Vector3 = (top[0] as Vector3).lerp(top[1], f * 2.0) if f <= 0.5 else (top[1] as Vector3).lerp(top[2], f * 2.0 - 1.0)
				cols_top.append(tp)
				if i == 0 or i == COLS:
					flares.append(_corner_flare(c, tp))
				else:
					flares.append(out)
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


## 칸 c의 d쪽 변의 세 점(모서리 → 가운데 → 모서리, 변을 따라 x 또는 z가 커지는 순서)
func _edge(c: Vector2i, d: Vector2i) -> Array:
	var arr: PackedFloat32Array = vh[c]
	var out := []
	for i in 3:
		var ix: int = i if d.y != 0 else (0 if d.x < 0 else 2)
		var iz: int = i if d.x != 0 else (0 if d.y < 0 else 2)
		out.append(Vector3(c.x + ix * 0.5, arr[iz * 3 + ix], c.y + iz * 0.5))
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
			for s in 2:
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
