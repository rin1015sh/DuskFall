extends RefCounted
## 3/4 탑뷰(오블리크) 좌표 변환. 규칙 엔진은 이 파일을 모른다(룰북 8단계: 표현 계층만 화면 좌표를 안다).
## 위에서 살짝 비스듬히 내려다보는 시점: 바닥 칸은 정사각형(64px — 에셋 키트 px_per_tile), 높이는 화면 위쪽으로 올린다.
## 칸 (x, y, 높이 h) → 화면 (x · T + T/2, y · T + T/2 − h · STEP). 카메라 회전 없음.

const T := 64
## 높이 1단계(5피트)의 화면 높이
const STEP := 40
## 벽이 보이는 높이(벽면). 키트 벽면 그림(160px)의 아래쪽을 이만큼 쓴다.
const WALL_H := 112


static func ground(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * T + T / 2.0, cell.y * T + T / 2.0)


static func top(cell: Vector2i, h: int) -> Vector2:
	return ground(cell) - Vector2(0, h * STEP)


## 칸 윗면 네모(높이 반영). 벽 칸은 벽 꼭대기.
static func top_rect(grid: Node, cell: Vector2i) -> Rect2:
	var lift: float = WALL_H if grid.has_flag(cell, "wall") else grid.height(cell) * STEP
	return Rect2(cell.x * T, cell.y * T - lift, T, T)


static func corners(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y)])


## 화면 점 → 칸. 앞쪽(아래 줄)·높은 칸부터 윗면 네모에 드는지 본다.
static func pick(grid: Node, pos: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_key := -1000000000
	for c: Vector2i in grid.all_cells():
		if top_rect(grid, c).has_point(pos):
			var key: int = c.y * 1000 + int(top_rect(grid, c).position.y * -1)
			if key > best_key:
				best_key = key
				best = c
	return best
