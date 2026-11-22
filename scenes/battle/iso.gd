extends RefCounted
## 쿼터뷰(아이소메트릭) 좌표 변환. 규칙 엔진은 이 파일을 모른다(룰북 8단계: 표현 계층만 화면 좌표를 안다).
## 칸 (x, y, 높이 h) → 화면: ((x − y) · W/2, (x + y) · H/2 − h · STEP). 카메라 회전 없음.

const TILE_W := 96
const TILE_H := 48
## 높이 1단계(5피트)의 화면 높이
const STEP := 24


static func ground(cell: Vector2i) -> Vector2:
	return Vector2((cell.x - cell.y) * TILE_W / 2.0, (cell.x + cell.y) * TILE_H / 2.0)


static func top(cell: Vector2i, h: int) -> Vector2:
	return ground(cell) - Vector2(0, h * STEP)


## 칸 윗면 마름모 꼭짓점(위·오른·아래·왼).
static func diamond(center: Vector2) -> PackedVector2Array:
	return PackedVector2Array([center + Vector2(0, -TILE_H / 2.0), center + Vector2(TILE_W / 2.0, 0),
		center + Vector2(0, TILE_H / 2.0), center + Vector2(-TILE_W / 2.0, 0)])


## 화면 점 → 칸. 높이가 있어 앞쪽(그리기 순서가 늦은) 칸부터 윗면 마름모에 드는지 본다.
static func pick(grid: Node, pos: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_key := -1000000000
	for c: Vector2i in grid.all_cells():
		var h: int = grid.height(c) + (3 if grid.has_flag(c, "wall") else 0)
		if Geometry2D.is_point_in_polygon(pos, diamond(top(c, h))):
			var key := (c.x + c.y) * 100 + h
			if key > best_key:
				best_key = key
				best = c
	return best
