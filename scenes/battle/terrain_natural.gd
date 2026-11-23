extends RefCounted
## 자연 지형(맵 데이터 art.terrain = "natural"): 부드러운 언덕 + 바위 절벽. 표현 계층만 — 규칙 높이는 칸마다 정수 그대로.
## - 칸을 2×2로 쪼갠 3×3 점. 가운데 점 = 그 칸 높이(캐릭터가 서는 곳 = 규칙 높이).
##   변 가운데·모서리 점은 '이어진' 칸끼리 높이를 평균한다. 이어짐 = 둘 다 바닥이고 높이 차 1단계 이하(걸어서 오르내리는 차 — 3단계 이동 규칙).
##   모서리는 그 점을 둘러싼 네 칸 중 변으로 이어진 무리의 평균이라 이웃 칸끼리 같은 값을 쓴다(틈이 없다).
## - 이어지지 않은 변(높이 차 2단계 이상)에는 바위 면을 세운다: 높은 칸 변 → 낮은 칸 변, 단계마다 한 줄, 가운데 점은 잡음으로 불룩하게.
## - 밝기: 고정 햇빛(왼쪽 위 앞)과 면 방향으로 음영(빛 없는 그림에 굴곡이 읽히게) × 빛 단계 어둠.

const V := preload("res://scenes/battle/view3d.gd")
## 햇빛 방향(서쪽·위·남쪽에서 비춤 — 카메라 쪽 바위 면이 밝다)
const SUN := Vector3(-0.5, 0.75, 0.45)
const SHADE_K := 0.7
## 바닥 빛: 북서쪽 위에서(카메라 쪽을 보는 비탈은 살짝 어둡고 서쪽 비탈은 밝다). 평지 밝기 FLOOR_BASE를
## 셰이더가 1/FLOOR_BASE배로 되돌려 평지는 블록 지형과 같고, 빛을 받는 비탈만 더 밝아진다.
const FLOOR_SUN := Vector3(-0.6, 0.7, -0.35)
const FLOOR_K := 0.6
const FLOOR_BASE := 0.88
## 바위 면 불룩함(유닛)
const BULGE := 0.16
## 절벽 발치 그늘 밝기
const FOOT_AO := 0.62
## 절벽 위 가장자리 띠 너비·진하기
const RIM_W := 0.14
const RIM_ALPHA := 0.55

var grid: Node
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


## 면 방향 → 밝기(평지 = 1)
static func sun_shade(n: Vector3) -> float:
	var l := SUN.normalized()
	return clampf(1.0 + SHADE_K * (n.normalized().dot(l) - l.y), 0.42, 1.0)


## 바닥 밝기(평지 = FLOOR_BASE)
static func floor_shade(n: Vector3) -> float:
	var l := FLOOR_SUN.normalized()
	return clampf(FLOOR_BASE + FLOOR_K * (n.normalized().dot(l) - l.y), 0.45, 1.0)


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


## 바닥 그물(삼각형): dark_at(점) → 어둠 0..1
func build_floor(dark_at: Callable) -> ArrayMesh:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for c: Vector2i in vh:
		var arr: PackedFloat32Array = vh[c]
		var pts := []
		var shade := []
		for iz in 3:
			for ix in 3:
				var p := Vector2(c.x + ix * 0.5, c.y + iz * 0.5)
				pts.append(Vector3(p.x, arr[iz * 3 + ix], p.y))
				var k: float = (1.0 - float(dark_at.call(p))) * floor_shade(_normal_at(c, p))
				shade.append(Color(k, k, k))
		for qz in 2:
			for qx in 2:
				var a := qz * 3 + qx
				var idx := [a, a + 1, a + 4, a, a + 4, a + 3]
				for j: int in idx:
					verts.append(pts[j])
					cols.append(shade[j])
	return _mesh(verts, cols)


## 바위 면 그물: 이어지지 않은 변마다 높은 칸 변 → 낮은 칸 변. dark_at(칸) → 어둠(면이 보는 낮은 칸).
## 맵 가장자리·벽 쪽 변은 만들지 않는다(벽이 덮는다).
func build_cliffs(dark_of: Callable) -> ArrayMesh:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for c: Vector2i in vh:
		for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var n := c + d
			if not vh.has(n) or linked(c, n) or grid.height(c) <= grid.height(n):
				continue
			var top := _edge(c, d)
			var bot := _edge(n, -d)
			var out := Vector3(d.x, 0, d.y)
			var k := 1.0 - float(dark_of.call(n))
			for s in 2:
				_face_strip(verts, cols, top[s], top[s + 1], bot[s], bot[s + 1], out, s, k)
	return _mesh(verts, cols)


## 칸 c의 d쪽 변의 세 점(모서리 → 가운데 → 모서리, 변을 따라 x 또는 z가 커지는 순서)
func _edge(c: Vector2i, d: Vector2i) -> Array:
	var arr: PackedFloat32Array = vh[c]
	var out := []
	for i in 3:
		var ix: int = i if d.y != 0 else (0 if d.x < 0 else 2)
		var iz: int = i if d.x != 0 else (0 if d.y < 0 else 2)
		out.append(Vector3(c.x + ix * 0.5, arr[iz * 3 + ix], c.y + iz * 0.5))
	return out


## 바위 면 한 조각(변의 반): 위 두 점·아래 두 점. 단계마다 한 줄, 변 가운데 쪽 세로줄 안쪽 점만 불룩하게(모서리는 이웃 면과 맞닿아 그대로).
func _face_strip(verts: PackedVector3Array, cols: PackedColorArray, t0: Vector3, t1: Vector3, b0: Vector3, b1: Vector3, out: Vector3, s: int, k: float) -> void:
	var rows := maxi(1, ceili(maxf(t0.y - b0.y, t1.y - b1.y)))
	var mid_col := 1 if s == 0 else 0  # 변 가운데 점이 있는 쪽
	var grid_pts := []
	for r in rows + 1:
		var f := float(r) / rows
		var row := []
		for u in 2:
			var tp: Vector3 = t0 if u == 0 else t1
			var bp: Vector3 = b0 if u == 0 else b1
			var p := tp.lerp(bp, f)
			if r > 0 and r < rows and u == mid_col:
				p += out * BULGE * (0.4 + 0.6 * _hash3(p))
			row.append(p)
		grid_pts.append(row)
	for r in rows:
		var a: Vector3 = grid_pts[r][0]
		var b: Vector3 = grid_pts[r][1]
		var c: Vector3 = grid_pts[r + 1][1]
		var d: Vector3 = grid_pts[r + 1][0]
		var n := (b - a).cross(d - a)
		if n.dot(out) < 0.0:
			n = -n
		var sh := sun_shade(n) * k
		for p: Vector3 in [a, b, c, a, c, d]:
			verts.append(p)
			# 발치 그늘: 낮은 바닥에서 0.6단계 위까지 어둡게
			var foot_y := lerpf(b0.y, b1.y, clampf(inverse_lerp(t0.x + t0.z, t1.x + t1.z, p.x + p.z), 0.0, 1.0))
			var ao := clampf(FOOT_AO + (1.0 - FOOT_AO) * (p.y - foot_y) / 0.6, FOOT_AO, 1.0)
			cols.append(Color(sh * ao, sh * ao, sh * ao))


## 절벽 위 가장자리 어두운 띠(높은 칸 쪽, 바닥을 따라)
func build_rims() -> ArrayMesh:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var edge := Color(0, 0, 0, RIM_ALPHA)
	var fade := Color(0, 0, 0, 0)
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
