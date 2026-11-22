extends Control
## 오른쪽 위 원형 미니맵(BG3 배치 참고): 선택한 캐릭터를 가운데 두고 둘레 칸을 그린다.
## 벽 어둡게, 바닥 흙색, 물 푸르게, 파티 청록 점, 적 붉은 점(누군가 볼 수 있을 때만), 중립 노란 점.

const S := preload("res://scenes/ui/ui_style.gd")
const RADIUS_TILES := 13

var grid: Node
var center_creature: Node
var party: Array = []


func _ready() -> void:
	custom_minimum_size = Vector2(190, 190)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 8
	draw_circle(c, r + 6, Color(0, 0, 0, 0.55))
	draw_circle(c, r, Color(0.08, 0.07, 0.06))
	if grid == null or center_creature == null or not grid.creatures().has(center_creature):
		_ring(c, r)
		return
	var cc: Vector2i = grid.cell_of(center_creature)
	var px := r / float(RADIUS_TILES)
	for dy in range(-RADIUS_TILES, RADIUS_TILES + 1):
		for dx in range(-RADIUS_TILES, RADIUS_TILES + 1):
			if dx * dx + dy * dy > RADIUS_TILES * RADIUS_TILES:
				continue
			var cell := cc + Vector2i(dx, dy)
			if not grid.in_bounds(cell):
				continue
			var col: Color
			if grid.has_flag(cell, "wall"):
				col = Color(0.16, 0.13, 0.11)
			elif grid.surface_id(cell) == "water":
				col = Color(0.22, 0.33, 0.40)
			else:
				var h: int = grid.height(cell)
				col = Color(0.36, 0.31, 0.23).lightened(0.06 * h)
				if grid.light_at(cell) == 0:
					col = col.darkened(0.45)
			draw_rect(Rect2(c + Vector2(dx - 0.5, dy - 0.5) * px, Vector2(px, px) + Vector2(0.6, 0.6)), col)
	for o: Node in grid.creatures():
		if o.dead:
			continue
		var d: Vector2 = Vector2(grid.cell_of(o) - cc)
		if d.length() > RADIUS_TILES:
			continue
		var col := Color(0.35, 0.80, 0.82)
		if o.team == "enemy":
			var seen := party.any(func(p: Node) -> bool: return not p.dead and grid.can_see(p, o))
			if not seen:
				continue
			col = Color(0.80, 0.25, 0.20)
		elif o.team != "party":
			col = Color(0.85, 0.72, 0.30)
		draw_circle(c + d * px, maxf(px * 0.6, 2.5), Color(0, 0, 0, 0.7))
		draw_circle(c + d * px, maxf(px * 0.45, 2.0), col)
	_ring(c, r)


func _ring(c: Vector2, r: float) -> void:
	draw_arc(c, r + 1, 0, TAU, 72, S.BRONZE, 4.0, true)
	draw_arc(c, r + 6, 0, TAU, 72, Color(S.GOLD, 0.55), 1.5, true)
	for i in 4:
		var a := TAU * i / 4.0 - PI / 2
		var p := c + Vector2(cos(a), sin(a)) * (r + 4)
		var pts := PackedVector2Array([p + Vector2(0, -6), p + Vector2(5, 0), p + Vector2(0, 6), p + Vector2(-5, 0)])
		draw_colored_polygon(pts, S.BRONZE_DARK)
		draw_polyline(pts + PackedVector2Array([pts[0]]), S.GOLD_SOFT, 1.2, true)
