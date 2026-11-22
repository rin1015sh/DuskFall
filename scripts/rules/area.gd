extends RefCounted
## 범위 템플릿(상태 없음). 룰북 4단계 '범위 템플릿'.
## 범위는 수평 거리만 보고 높이 차는 무시한다. 시작점에서 벽으로 막힌 칸은 빠진다.
## grid를 null로 주면 벽 판정 없이 모양만 낸다.


## 원형 마스크: 중심 칸에서 dx² + dy² ≤ N² + N(구·원기둥·발산). 반경 4 → 69칸.
static func circle(grid: Node, center: Vector2i, n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in range(-n, n + 1):
		for dx in range(-n, n + 1):
			if dx * dx + dy * dy <= n * n + n:
				out.append(center + Vector2i(dx, dy))
	return _clip(grid, center, out)


## 발산: 구와 같은 원형 마스크, 중심은 시전자 칸(9단계 충돌 F).
static func emanation(grid: Node, caster: Node, n: int) -> Array[Vector2i]:
	return circle(grid, grid.cell_of(caster), n)


## 원뿔: 길이 N칸. 앞으로 d칸 떨어진 줄에서 좌우 ⌊d/2⌋칸. 3칸 → 7칸.
## 대각선 방향은 앞쪽 거리를 max(|x|, |y|), 옆 폭을 |x − y|로 잰다(같은 칸 수).
static func cone(grid: Node, origin: Vector2i, dir: Vector2i, n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	dir = Vector2i(signi(dir.x), signi(dir.y))
	if dir.x != 0 and dir.y != 0:
		for y in range(1, n + 1):
			for x in range(1, n + 1):
				var d := maxi(x, y)
				if absi(x - y) <= d / 2:
					out.append(origin + Vector2i(x * dir.x, y * dir.y))
	else:
		var side := Vector2i(-dir.y, dir.x)
		for d in range(1, n + 1):
			for s in range(-d / 2, d / 2 + 1):
				out.append(origin + dir * d + side * s)
	return _clip(grid, origin, out)


## 선: 시작 칸에서 대상 칸 방향으로 N칸 직선, 벽에서 멈춘다(모서리는 양옆이 다 벽일 때 멈춤).
static func line(grid: Node, origin: Vector2i, toward: Vector2i, n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if toward == origin:
		return out
	# 방향을 늘려 N칸 이상 가는 끝점을 잡고 그 직선을 따라간다.
	var d := toward - origin
	var scale := int(ceil(float(n) / maxi(absi(d.x), absi(d.y)))) + 1
	var GridWorld := preload("res://scripts/rules/grid_world.gd")
	for item: Variant in GridWorld.line_between(origin, origin + d * scale):
		if item is Array:
			if grid != null and _wall(grid, item[0]) and _wall(grid, item[1]):
				break
			continue
		var c: Vector2i = item
		if grid != null and _wall(grid, c):
			break
		out.append(c)
		if out.size() >= n:
			break
	return out


static func _wall(grid: Node, c: Vector2i) -> bool:
	return not grid.in_bounds(c) or grid.has_flag(c, "wall")


## 정육면체: 한 변 S칸. 시전자와 한 변이 맞닿는다(직교 방향이면 옆으로 가운데 정렬).
static func cube_from(grid: Node, origin: Vector2i, dir: Vector2i, s: int) -> Array[Vector2i]:
	dir = Vector2i(signi(dir.x), signi(dir.y))
	var corner: Vector2i
	if dir.x != 0 and dir.y != 0:
		corner = origin + dir
		var out: Array[Vector2i] = []
		for y in s:
			for x in s:
				out.append(corner + Vector2i(x * dir.x, y * dir.y))
		return _clip(grid, origin, out)
	var side := Vector2i(-dir.y, dir.x)
	var out2: Array[Vector2i] = []
	for f in range(1, s + 1):
		for o in range(-(s - 1) / 2, s / 2 + 1):
			out2.append(origin + dir * f + side * o)
	return _clip(grid, origin, out2)


## 정사각형 영역: 왼쪽 위 칸에서 S × S(사거리 안에 놓는 주문 영역).
static func square(grid: Node, top_left: Vector2i, s: int, origin: Vector2i = Vector2i(-1, -1)) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in s:
		for x in s:
			out.append(top_left + Vector2i(x, y))
	return _clip(grid, origin if origin.x >= 0 else top_left, out)


## 범위 안 생물. 큰 생물은 점유 칸 중 하나라도 들면 포함(9단계 충돌 E).
static func creatures_in(grid: Node, cells: Array[Vector2i]) -> Array:
	var out: Array = []
	for cr: Node in grid.creatures():
		if cr.has_flag("ethereal"):
			continue  # Blink: 다른 차원
		for c in grid.occupied_cells(cr):
			if c in cells:
				out.append(cr)
				break
	return out


## 격자 밖과, 시작점에서 벽으로 막힌 칸을 뺀다.
static func _clip(grid: Node, origin: Vector2i, cells: Array[Vector2i]) -> Array[Vector2i]:
	if grid == null:
		return cells
	var out: Array[Vector2i] = []
	for c in cells:
		if not grid.in_bounds(c) or grid.has_flag(c, "wall"):
			continue
		if c == origin or grid.has_line_of_sight(origin, c, true):
			out.append(c)
	return out
