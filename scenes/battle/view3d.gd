extends RefCounted
## 3/4 탑뷰 3D 좌표(표현 계층). 규칙 엔진은 이 파일을 모른다(룰북 8단계: 표현 계층만 화면 좌표를 안다).
## 세계 좌표: 1칸 = 1유닛(x = 칸 x, z = 칸 y — 남쪽이 +z), 높이 1단계(5피트) = 1유닛(y 위).
## 카메라: 직교 투영, 남쪽 위에서 PITCH만큼 내려다본다(회전 없음). 1유닛 = 화면 64px(확대 1)일 때
##   가로 1칸 = 64px, 높이 1단계 = 64·cos(PITCH) = 40px(옛 2D와 같다), 바닥 세로 1칸 = 64·sin(PITCH) ≈ 50px(원근 반영).
## 서 있는 그림(캐릭터·소품)은 세운 판에 그리고 세로를 1/cos(PITCH)배 늘려 화면 크기가 옛 2D와 같게 한다.

## 칸 한 변의 그림 px(던전 에셋 키트 px_per_tile)
const T := 64
## 높이 1단계의 화면 px(확대 1)
const STEP_PX := 40.0
## 카메라가 내려다보는 각(수평에서): cos = 40/64
const PITCH := 0.8956648938  # acos(0.625)
const COS_P := 0.625
const SIN_P := 0.7806247498
## 서 있는 그림 세로 배율(화면에서 옛 2D 크기 그대로)
const UPRIGHT := 1.6
## 벽 높이(유닛) = 옛 벽면 112px / 40px
const WALL_H := 2.8
## 방 남쪽 벽(안을 가리지 않게 잘라 낸 낮은 벽) 높이 = 옛 20px
const LOW_WALL_H := 0.5
## 바닥 위에 까는 것(표면·하이라이트)의 들림
const LIFT := 0.012
## 카메라와 바라보는 점 사이 거리(직교라 화면에는 영향 없음, 깊이 범위만)
const CAM_DIST := 60.0
## 그림 거르기: 옛 2D(가장 가까운 점)와 같게
const TEX_FILTER := BaseMaterial3D.TEXTURE_FILTER_NEAREST
## 빛 단계별 어둠(어둠·어스름·밝음) — 그림 밝기를 (1 − 값)배로
const DARK_ALPHA := [0.82, 0.5, 0.06]


## 칸 빛 단계에 따른 그림 색(서 있는 판·캐릭터에 곱한다)
static func light_tint(grid: Node, c: Vector2i) -> Color:
	var k: float = 1.0 - DARK_ALPHA[clampi(grid.light_at(c), 0, 2)] if grid.in_bounds(c) else 1.0
	return Color(k, k, k)


## 칸 가운데(높이 h 단계)
static func pos(cell: Vector2i, h: float = 0.0) -> Vector3:
	return Vector3(cell.x + 0.5, h, cell.y + 0.5)


## 칸 좌표(실수, 칸 단위 평면) → 세계(높이 h)
static func flat(p: Vector2, h: float = 0.0) -> Vector3:
	return Vector3(p.x, h, p.y)


## 방의 남쪽 벽(북쪽이 바닥이고 남쪽이 막힘)은 방 안을 가리지 않게 낮게 자른다(옛 2D 규칙).
static func is_low_wall(grid: Node, c: Vector2i) -> bool:
	if not grid.has_flag(c, "wall"):
		return false
	var south := c + Vector2i.DOWN
	var north := c + Vector2i.UP
	var open_south: bool = grid.in_bounds(south) and not grid.has_flag(south, "wall")
	return not open_south and grid.in_bounds(north) and not grid.has_flag(north, "wall")


## 칸 윗면 높이(유닛). 벽은 보이는 꼭대기.
static func cell_top(grid: Node, c: Vector2i) -> float:
	if grid.has_flag(c, "wall"):
		return LOW_WALL_H if is_low_wall(grid, c) else WALL_H
	return float(grid.height(c))


## 칸 윗면 가운데
static func top(grid: Node, c: Vector2i) -> Vector3:
	return pos(c, cell_top(grid, c))


## 카메라 자세: 바라보는 점 target, 확대 zoom(1 = 1유닛 64px), 화면 높이 px → (Transform3D, 직교 크기)
static func camera_transform(target: Vector3) -> Transform3D:
	var b := Basis(Vector3.RIGHT, -PITCH)
	return Transform3D(b, target + b.z * CAM_DIST)


static func ortho_size(viewport_h: float, zoom: float) -> float:
	return viewport_h / (T * zoom)


## 화면 끌기(px) → 바라보는 점 이동(세계)
static func pan_delta(screen_delta: Vector2, zoom: float) -> Vector3:
	return Vector3(screen_delta.x / (T * zoom), 0.0, screen_delta.y / (T * zoom * SIN_P))


## 광선 → 칸. 칸마다 바닥(−1)부터 윗면까지의 기둥 상자와 광선이 처음 만나는 칸(가장 가까운 것).
## 절벽·벽의 앞면을 누르면 그 높은 칸을 고른다.
static func pick(grid: Node, origin: Vector3, dir: Vector3) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_t := INF
	for c: Vector2i in grid.all_cells():
		var t := _ray_box(origin, dir, Vector3(c.x, -1.0, c.y), Vector3(c.x + 1, cell_top(grid, c), c.y + 1))
		if t < best_t:
			best_t = t
			best = c
	return best


## 광선과 상자(최소·최대 모서리)가 만나는 거리(안 만나면 INF). 슬랩 방식.
static func _ray_box(o: Vector3, d: Vector3, lo: Vector3, hi: Vector3) -> float:
	var t0 := -INF
	var t1 := INF
	for i in 3:
		if absf(d[i]) < 1e-9:
			if o[i] < lo[i] or o[i] > hi[i]:
				return INF
			continue
		var a := (lo[i] - o[i]) / d[i]
		var b := (hi[i] - o[i]) / d[i]
		t0 = maxf(t0, minf(a, b))
		t1 = minf(t1, maxf(a, b))
	if t1 < maxf(t0, 0.0):
		return INF
	return maxf(t0, 0.0)


## 카메라 없이(테스트·도구) 화면을 흉내 낸 광선: 칸 평면 점 p(높이 h)를 지나 카메라 방향에서 오는 광선
static func ray_through(p: Vector3) -> Array:
	var back := Basis(Vector3.RIGHT, -PITCH).z
	return [p + back * CAM_DIST, -back]
