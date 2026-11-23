extends RefCounted
## 자연 지형(맵 데이터 art.terrain = "natural"): 부드러운 언덕 + 둥글고 울퉁불퉁한 바위 절벽. 표현 계층만 — 규칙 높이는 칸마다 정수 그대로.
## 1) 비탈 층(vh): 칸마다 (RES+1)² 점. 걸어서 이어진 칸들(이어짐 = 둘 다 바닥이고 높이 차 1단계 이하 — 3단계 이동 규칙)의 높이를
##    거리·높이 차 가중 평균 — 2칸마다 1단계씩 오르는 길도 곧은 비탈. 절벽(높이 차 2 이상)에서는 끊긴다.
## 2) 지형 그물(격자): 맵 전체를 칸당 LR×LR 점으로. 점 높이 = 위치를 잡음으로 흔든 자리의 비탈 층 높이(절벽 외곽선이 칸 경계가 아닌 곡선),
##    → 그물을 몇 번 고르게 다듬어(라플라스) 절벽이 끊김 없는 가파른 경사가 되고 모서리가 둥글어진다
##    → 가파른 곳은 부드러운 잡음으로 들고 밀어 울퉁불퉁하게. 바닥·절벽이 한 그물이라 틈이 없다.
##    셰이더(floor.gdshader)가 기울기를 보고 가파른 곳에 바위 그림을 입힌다.
## 캐릭터·소품·하이라이트는 ground_at(그려진 면)에 선다. 규칙 판정은 언제나 칸 정수 높이.
## 밝기(입체감): 햇빛 하나(북서쪽 위) — 면 방향 음영(바닥/바위), 드리운 그림자(해 쪽으로 높이를 훑음), 오목한 절벽 발치 그늘 × 빛 단계 어둠.

const V := preload("res://scenes/battle/view3d.gd")
## 햇빛 방향(해 쪽을 가리킴): 북서쪽 위. 그림자는 남동쪽(카메라 쪽)으로 드리워 화면에서 보인다.
const SUN := Vector3(-0.5, 0.8, -0.5)
## 바위(가파른 곳) 밝기 = FACE_BASE + FACE_K × (면 방향·햇빛)
const FACE_BASE := 0.74
const FACE_K := 0.42
## 바닥: 평지 밝기 FLOOR_BASE(셰이더가 1/FLOOR_BASE배로 되돌려 평지는 블록 지형과 같다), 기울기 음영 FLOOR_K
const FLOOR_K := 0.7
const FLOOR_BASE := 0.88
## 드리운 그림자 밝기·반그림자 폭(유닛)·훑는 간격
const SHADOW := 0.58
const PENUMBRA := 0.35
const SHADOW_STEP := 0.2
## 비탈 층: 칸당 점 간격 수, 거리 가중 반경(칸), 높이 차 가중 폭(단계)
const RES := 2
const SMOOTH_R := 2.0
const HEIGHT_SIGMA := 1.3
## 지형 그물: 칸당 점 간격 수, 외곽선 흔들림(칸), 다듬기 횟수
const LR := 5
const WARP := 0.2
const RELAX := 3
## 가파른 곳 울퉁불퉁함: 높이(유닛)·옆(유닛)
const BUMP_Y := 0.32
const BUMP_XZ := 0.12
## 오목한 곳(절벽 발치) 그늘 세기·최소 밝기
const AO_K := 2.2
const AO_MIN := 0.6

var grid: Node
var _max_h := 0.0
## 칸 → (RES+1)² 비탈 층 높이(줄 = 북→남, 칸 = 서→동)
var vh := {}
## 지형 그물(LW × LH 점): 다듬은 높이·그린 자리·법선·가파름(0..1)·오목 그늘·쓰는 점
var LW := 0
var LH := 0
var _h := PackedFloat32Array()
var _pos := PackedVector3Array()
var _nrm := PackedVector3Array()
var _steep := PackedFloat32Array()
var _ao := PackedFloat32Array()
var _valid := PackedByteArray()
var _shadow := PackedFloat32Array()


func _init(g: Node) -> void:
	grid = g
	var n := RES + 1
	for c: Vector2i in grid.all_cells():
		if _floor(c):
			var arr := PackedFloat32Array()
			arr.resize(n * n)
			if _flat_around(c):
				arr.fill(float(grid.height(c)))  # 둘레가 모두 같은 높이(바닥·벽)면 계산할 것 없이 평평
			else:
				var comp := _component(c)
				for iz in n:
					for ix in n:
						arr[iz * n + ix] = _smooth_h(c, Vector2(c.x + float(ix) / RES, c.y + float(iz) / RES), comp)
			vh[c] = arr
			_max_h = maxf(_max_h, float(grid.height(c)))
	_build_lattice()


## 칸 c 둘레(반경 3칸)의 바닥이 모두 c와 같은 높이인가
func _flat_around(c: Vector2i) -> bool:
	var h: int = grid.height(c)
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var o := c + Vector2i(dx, dy)
			if _floor(o) and grid.height(o) != h:
				return false
	return true


func _floor(c: Vector2i) -> bool:
	return grid.in_bounds(c) and not grid.has_flag(c, "wall")


## 걸어서 이어지는 두 칸(바닥이고 높이 차 1 이하)
func linked(a: Vector2i, b: Vector2i) -> bool:
	return _floor(a) and _floor(b) and absi(grid.height(a) - grid.height(b)) <= 1


## 칸 c에서 이어짐으로 닿는 칸들(c 가운데에서 SMOOTH_R + 1.2 안, 그 안으로만 이어 감) — 칸마다 한 번
func _component(c: Vector2i) -> Array:
	var reach := SMOOTH_R + 1.2
	var cc := Vector2(c) + Vector2(0.5, 0.5)
	var group := {c: true}
	var queue: Array[Vector2i] = [c]
	while not queue.is_empty():
		var g: Vector2i = queue.pop_back()
		for o: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var nb := g + o
			if group.has(nb) or not linked(g, nb) or cc.distance_to(Vector2(nb) + Vector2(0.5, 0.5)) > reach:
				continue
			group[nb] = true
			queue.append(nb)
	return group.keys()


## 점 p(칸 c의 점)의 높이: c와 이어진 칸들(comp) 중 p 둘레 칸의 가중 평균.
## 가중 = 거리 가중 × 기준 높이와의 차 가중(차가 2 이상인 칸은 거의 0 — 비탈로 돌아 이어진 절벽 너머가 끼어들어 절벽을 깎지 않게).
## 기준 높이 = p에 맞닿은 칸 중 c와 변으로 이어진 무리의 평균. (칸 사이 작은 차이는 지형 그물이 다듬는다.)
func _smooth_h(c: Vector2i, p: Vector2, comp: Array) -> float:
	var href := _touch_ref(c, p)
	var reach := SMOOTH_R + 0.71
	var sw := 0.0
	var sh := 0.0
	for g: Vector2i in comp:
		var d := p.distance_to(Vector2(g) + Vector2(0.5, 0.5))
		if d >= reach:
			continue
		var w := 1.0 - d / reach
		var dh := float(grid.height(g)) - href
		w *= w * exp(-dh * dh / (HEIGHT_SIGMA * HEIGHT_SIGMA))
		sw += w
		sh += w * grid.height(g)
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


## 비탈 층 높이(칸 평면 점). 바닥 칸 안에서 쌍선형, 아니면 칸 윗면.
func _cell_ground(p: Vector2) -> float:
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
	return lerpf(lerpf(arr[qz * n + qx], arr[qz * n + qx + 1], u), lerpf(arr[(qz + 1) * n + qx], arr[(qz + 1) * n + qx + 1], u), v)


func _idx(i: int, j: int) -> int:
	return j * LW + i


## 격자 점 (i, j)에 맞닿은 바닥 칸 하나(없으면 (-1, -1)). 칸 경계 위의 점은 양쪽 칸이 맞닿는다.
func _touch_floor(i: int, j: int) -> Vector2i:
	var xs := [i / LR - 1, i / LR] if i % LR == 0 else [i / LR]
	var zs := [j / LR - 1, j / LR] if j % LR == 0 else [j / LR]
	for x: int in xs:
		for z: int in zs:
			if vh.has(Vector2i(x, z)):
				return Vector2i(x, z)
	return Vector2i(-1, -1)


## 지형 그물: 흔든 자리의 비탈 층 높이 → 고르게 다듬기 → 가파른 곳 울퉁불퉁 → 법선·오목 그늘
func _build_lattice() -> void:
	LW = grid.size.x * LR + 1
	LH = grid.size.y * LR + 1
	var n := LW * LH
	_h.resize(n)
	_valid.resize(n)
	_valid.fill(0)
	for j in LH:
		for i in LW:
			var k := _idx(i, j)
			var own := _touch_floor(i, j)
			if own.x < 0:
				continue
			_valid[k] = 1
			var p := Vector2(float(i) / LR, float(j) / LR)
			var w := Vector2(_noise(p * 1.1 + Vector2(11.0, 3.0)), _noise(p * 1.1 + Vector2(47.0, 29.0))) * 2.0 - Vector2.ONE
			w += (Vector2(_noise(p * 3.3 + Vector2(5.0, 71.0)), _noise(p * 3.3 + Vector2(83.0, 17.0))) * 2.0 - Vector2.ONE) * 0.35
			var q := p + w * WARP
			var qc := Vector2i(floori(q.x), floori(q.y))
			if not vh.has(qc):
				# 흔든 자리가 벽·맵 밖이면 맞닿은 바닥 칸 안의 자리로
				q = Vector2(clampf(p.x, own.x, own.x + 1.0), clampf(p.y, own.y, own.y + 1.0))
			_h[k] = _cell_ground(q)
	# 고르게 다듬기(쓰는 이웃끼리만): 절벽이 가파른 경사로 이어지고 모서리가 둥글어진다
	for it in RELAX:
		var nh := _h.duplicate()
		for j in LH:
			for i in LW:
				var k := _idx(i, j)
				if _valid[k] == 0:
					continue
				var s := _h[k] * 2.0
				var cnt := 2.0
				for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var ii := i + o.x
					var jj := j + o.y
					if ii >= 0 and jj >= 0 and ii < LW and jj < LH and _valid[_idx(ii, jj)] == 1:
						s += _h[_idx(ii, jj)]
						cnt += 1.0
				nh[k] = s / cnt
		_h = nh
	# 가파름·오목 그늘·울퉁불퉁한 자리
	_pos.resize(n)
	_steep.resize(n)
	_ao.resize(n)
	for j in LH:
		for i in LW:
			var k := _idx(i, j)
			var p := Vector2(float(i) / LR, float(j) / LR)
			if _valid[k] == 0:
				_pos[k] = Vector3(p.x, 0.0, p.y)
				continue
			var gx := (_hv(i + 1, j, k) - _hv(i - 1, j, k)) * LR * 0.5
			var gz := (_hv(i, j + 1, k) - _hv(i, j - 1, k)) * LR * 0.5
			var st := clampf((Vector2(gx, gz).length() - 1.4) / 1.8, 0.0, 1.0)
			_steep[k] = st
			var lap := (_hv(i + 1, j, k) + _hv(i - 1, j, k) + _hv(i, j + 1, k) + _hv(i, j - 1, k)) * 0.25 - _h[k]
			_ao[k] = clampf(1.0 - maxf(lap, 0.0) * AO_K * LR * 0.25, AO_MIN, 1.0)
			var bump := (_noise(p * 1.8 + Vector2(3.1, 9.7)) - 0.5) * 0.7 + (_noise(p * 4.6 + Vector2(17.0, 2.0)) - 0.5) * 0.3
			var side := Vector2(_noise(p * 2.2 + Vector2(61.0, 7.0)), _noise(p * 2.2 + Vector2(13.0, 91.0))) - Vector2(0.5, 0.5)
			_pos[k] = Vector3(p.x + side.x * BUMP_XZ * st, _h[k] + bump * BUMP_Y * st, p.y + side.y * BUMP_XZ * st)
	_nrm.resize(n)
	for j in LH:
		for i in LW:
			var k := _idx(i, j)
			if _valid[k] == 0:
				_nrm[k] = Vector3.UP
				continue
			var ax := _pv(i + 1, j, k) - _pv(i - 1, j, k)
			var az := _pv(i, j + 1, k) - _pv(i, j - 1, k)
			var nn := az.cross(ax).normalized()
			_nrm[k] = nn if nn.y >= 0.0 else -nn
	_build_shadows()


## 이웃 점 높이(쓰지 않는 점이면 자기 높이)
func _hv(i: int, j: int, fallback: int) -> float:
	if i < 0 or j < 0 or i >= LW or j >= LH or _valid[_idx(i, j)] == 0:
		return _h[fallback]
	return _h[_idx(i, j)]


func _pv(i: int, j: int, fallback: int) -> Vector3:
	if i < 0 or j < 0 or i >= LW or j >= LH or _valid[_idx(i, j)] == 0:
		return _pos[fallback]
	return _pos[_idx(i, j)]


## 그려진 바닥 높이(칸 평면 점): 지형 그물 쌍선형(울퉁불퉁 전 높이). 바닥 칸이 아니면 칸 윗면.
func ground_at(p: Vector2) -> float:
	var c := Vector2i(floori(p.x), floori(p.y))
	if not vh.has(c) or LW == 0:
		return V.cell_top(grid, c) if grid.in_bounds(c) else 0.0
	var fx := clampf(p.x * LR, 0.0, LW - 1.001)
	var fz := clampf(p.y * LR, 0.0, LH - 1.001)
	var i := int(fx)
	var j := int(fz)
	var u := fx - i
	var v := fz - j
	return lerpf(lerpf(_hv(i, j, _idx(i, j)), _hv(i + 1, j, _idx(i, j)), u), lerpf(_hv(i, j + 1, _idx(i, j)), _hv(i + 1, j + 1, _idx(i, j)), u), v)


## 가파른 정도(0 평지 … 1 절벽) — 장식·바위 그림
func steep_at(p: Vector2) -> float:
	var i := clampi(roundi(p.x * LR), 0, LW - 1)
	var j := clampi(roundi(p.y * LR), 0, LH - 1)
	return _steep[_idx(i, j)] if _valid[_idx(i, j)] == 1 else 0.0


## 바위 밝기(면 법선)
static func sun_shade(n: Vector3) -> float:
	return clampf(FACE_BASE + FACE_K * n.normalized().dot(SUN.normalized()), 0.35, 1.0)


## 바닥 밝기(평지 = FLOOR_BASE)
static func floor_shade(n: Vector3) -> float:
	var l := SUN.normalized()
	return clampf(FLOOR_BASE + FLOOR_K * (n.normalized().dot(l) - l.y), 0.45, 1.0)


## 드리운 그림자: 격자 점마다 해 쪽으로 높이를 훑어 빛줄기보다 높으면 그늘(반그림자). 높이만 보므로 한 번만.
func _build_shadows() -> void:
	_shadow.resize(LW * LH)
	_shadow.fill(0.0)
	# 짝수 점만 훑고 사이 점은 이웃 평균(그림자는 부드러워 4배 덜 훑어도 같다)
	for j in range(0, LH, 2):
		for i in range(0, LW, 2):
			if _valid[_idx(i, j)] == 1:
				_shadow[_idx(i, j)] = _trace_shadow(i, j)
	for j in LH:
		for i in LW:
			if (i % 2 == 0 and j % 2 == 0) or _valid[_idx(i, j)] == 0:
				continue
			var s := 0.0
			var cnt := 0
			for o: Vector2i in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				var ii := i + o.x
				var jj := j + o.y
				if ii % 2 == 0 and jj % 2 == 0 and ii >= 0 and jj >= 0 and ii < LW and jj < LH and _valid[_idx(ii, jj)] == 1:
					s += _shadow[_idx(ii, jj)]
					cnt += 1
			_shadow[_idx(i, j)] = s / cnt if cnt > 0 else 0.0


func _trace_shadow(i: int, j: int) -> float:
	var l := SUN.normalized()
	var dir := Vector2(l.x, l.z).normalized()
	var rise := l.y / Vector2(l.x, l.z).length()
	var p := Vector2(float(i) / LR, float(j) / LR)
	var y0 := _h[_idx(i, j)]
	var top := _max_h - y0
	var amount := 0.0
	var t := SHADOW_STEP * 1.5
	while t * rise < top + PENUMBRA:
		var q := p + dir * t
		if q.x < 0.0 or q.y < 0.0 or q.x >= grid.size.x or q.y >= grid.size.y:
			break
		if vh.has(Vector2i(floori(q.x), floori(q.y))):
			var over := ground_at(q) - (y0 + t * rise)
			amount = maxf(amount, clampf(over / PENUMBRA, 0.0, 1.0))
			if amount >= 1.0:
				break
		t += SHADOW_STEP
	return amount


func shadow_at(p: Vector2) -> float:
	var i := clampi(roundi(p.x * LR), 0, LW - 1)
	var j := clampi(roundi(p.y * LR), 0, LH - 1)
	return _shadow[_idx(i, j)]


## 지형 그물(바닥 + 절벽 한 그물, 점 공유 — 틈 없음): dark_at(점) → 어둠 0..1.
## 정점 색 = (바닥/바위 음영을 가파름으로 섞음) × 드리운 그림자 × 오목 그늘 × 빛 단계. 법선은 셰이더가 바위 그림을 고르는 데 쓴다.
func build_floor(dark_at: Callable) -> ArrayMesh:
	var map := PackedInt32Array()
	map.resize(LW * LH)
	map.fill(-1)
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var nrms := PackedVector3Array()
	var idx := PackedInt32Array()
	for c: Vector2i in vh:
		for qj in LR:
			for qi in LR:
				var corner := [Vector2i(qi, qj), Vector2i(qi + 1, qj), Vector2i(qi + 1, qj + 1), Vector2i(qi, qj + 1)]
				var vi := []
				for o: Vector2i in corner:
					var gi := c.x * LR + o.x
					var gj := c.y * LR + o.y
					var k := _idx(gi, gj)
					if map[k] < 0:
						map[k] = verts.size()
						verts.append(_pos[k])
						nrms.append(_nrm[k])
						var p := Vector2(float(gi) / LR, float(gj) / LR)
						var st := _steep[k]
						var sh := lerpf(floor_shade(_nrm[k]), sun_shade(_nrm[k]) * FLOOR_BASE, st)
						var v: float = (1.0 - float(dark_at.call(p))) * sh * lerpf(1.0, SHADOW, _shadow[k]) * _ao[k]
						cols.append(Color(v, v, v))
					vi.append(map[k])
				idx.append_array(PackedInt32Array([vi[0], vi[1], vi[2], vi[0], vi[2], vi[3]]))
	var m := ArrayMesh.new()
	if verts.is_empty():
		return m
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = nrms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## 바위 면은 지형 그물에 들어 있다(따로 세우지 않는다).
func build_cliffs(_dark_of: Callable) -> ArrayMesh:
	return ArrayMesh.new()


## 절벽 가장자리 테두리는 그물의 둥근 턱·음영이 대신한다.
func build_rims() -> ArrayMesh:
	return ArrayMesh.new()


## 절벽 변 목록(장식·사다리용): [높은 칸, 낮은 칸]
func cliff_edges() -> Array:
	var out := []
	for c: Vector2i in vh:
		for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var n := c + d
			if vh.has(n) and not linked(c, n) and grid.height(c) > grid.height(n):
				out.append([c, n])
	return out


## 높은 칸 c → 이웃 n이 절벽(둘 다 바닥, 이어지지 않음, c가 높음)
func _is_cliff(c: Vector2i, n: Vector2i) -> bool:
	return vh.has(c) and vh.has(n) and not linked(c, n) and grid.height(c) > grid.height(n)


## 매끄러운 값 잡음(0..1)
static func _noise(p: Vector2) -> float:
	var i := Vector2(floorf(p.x), floorf(p.y))
	var f := p - i
	var u := f * f * (Vector2(3.0, 3.0) - 2.0 * f)
	var a := _hash2(i)
	var b := _hash2(i + Vector2(1, 0))
	var c := _hash2(i + Vector2(0, 1))
	var d := _hash2(i + Vector2(1, 1))
	return lerpf(lerpf(a, b, u.x), lerpf(c, d, u.x), u.y)


static func _hash2(p: Vector2) -> float:
	var h := sin(p.x * 127.1 + p.y * 311.7) * 43758.5453
	return h - floorf(h)


static func _hash3(p: Vector3) -> float:
	var h := sin(p.x * 12.9898 + p.y * 78.233 + p.z * 37.719) * 43758.5453
	return h - floorf(h)
