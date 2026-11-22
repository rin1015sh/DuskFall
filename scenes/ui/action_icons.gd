extends Control
## 통일된 행동 아이콘(BG3의 금색 선화 아이콘 느낌, 그림 에셋 없이 _draw로): 어두운 바탕 + 금색 선.
## kind = 행동 키(attack, jump, drink ...). 없는 종류는 has_icon()이 false — 단축 막대가 그림으로 대신한다.

const S := preload("res://scenes/ui/ui_style.gd")
const KINDS := ["attack", "ranged_attack", "offhand_attack", "jump", "shove", "throw", "dash", "disengage", "hide", "help",
	"dip", "stand_up", "switch_weapons", "cunning_dash", "cunning_disengage", "cunning_hide", "sneak_melee", "sneak_ranged",
	"drink", "feed", "throw_potion", "wa_sweep", "wa_hamstring", "wa_pommel", "wa_topple", "wa_impale"]

var kind := ""
var dim := false


static func has_icon(key: String) -> bool:
	return key.get_slice(":", 0) in KINDS


func _draw() -> void:
	var w := size.x
	var c := size / 2.0
	var k := w / 40.0
	var col := Color(S.GOLD, 0.35) if dim else S.GOLD
	var thin := 1.6 * k
	var thick := 2.4 * k
	# 바탕: 어두운 원 + 가는 금테
	draw_circle(c, w * 0.47, Color(0.09, 0.075, 0.06))
	draw_arc(c, w * 0.47, 0, TAU, 40, Color(col, 0.5), 1.0, true)
	var P := func(x: float, y: float) -> Vector2: return c + Vector2(x, y) * k
	var base: String = kind.get_slice(":", 0)
	match base:
		"attack", "wa_sweep", "wa_topple":
			_sword(P, col, thick)
			if base == "wa_sweep":
				draw_arc(c, 13 * k, -2.6, -0.4, 16, col, thin, true)
			elif base == "wa_topple":
				draw_line(P.call(-10, 12), P.call(10, 12), col, thick, true)
		"ranged_attack", "sneak_ranged", "wa_hamstring":
			draw_arc(P.call(-4, 0), 13 * k, -1.2, 1.2, 20, col, thick, true)
			draw_line(P.call(1, -12), P.call(1, 12), Color(col, 0.7), thin, true)
			draw_line(P.call(-8, 0), P.call(13, 0), col, thin, true)
			draw_colored_polygon(PackedVector2Array([P.call(13, 0), P.call(8, -3), P.call(8, 3)]), col)
			if base == "sneak_ranged":
				_eye(P, col, thin, Vector2(-9, 9), 0.45)
		"offhand_attack", "sneak_melee", "wa_pommel", "wa_impale":
			draw_line(P.call(-9, 9), P.call(9, -9), col, thick, true)
			draw_line(P.call(-12, 6), P.call(-6, 12), col, thick, true)
			if base == "sneak_melee":
				_eye(P, col, thin, Vector2(7, 8), 0.45)
			elif base == "wa_pommel":
				draw_circle(P.call(-11, 11), 3.5 * k, col)
			elif base == "wa_impale":
				draw_colored_polygon(PackedVector2Array([P.call(13, -13), P.call(6, -10), P.call(10, -6)]), col)
		"jump":
			draw_arc(P.call(0, 8), 13 * k, PI + 0.3, TAU - 0.3, 24, col, thick, true)
			draw_colored_polygon(PackedVector2Array([P.call(13, 5), P.call(8, 1), P.call(14, -1)]), col)
			draw_line(P.call(-14, 12), P.call(14, 12), Color(col, 0.6), thin, true)
		"shove":
			for y: float in [-6.0, 0.0, 6.0]:
				draw_line(P.call(-12, y), P.call(6, y), col, thin, true)
			draw_colored_polygon(PackedVector2Array([P.call(12, 0), P.call(5, -8), P.call(5, 8)]), col)
		"throw", "throw_potion":
			draw_arc(P.call(0, 10), 14 * k, PI + 0.4, TAU - 0.6, 20, Color(col, 0.7), thin, true)
			if base == "throw_potion":
				_flask(P, col, thin, Vector2(9, -2), 0.6)
			else:
				draw_circle(P.call(10, -4), 4 * k, col)
		"dash", "cunning_dash":
			for x: float in [-8.0, 0.0]:
				draw_polyline(PackedVector2Array([P.call(x, -9), P.call(x + 8, 0), P.call(x, 9)]), col, thick, true)
		"disengage", "cunning_disengage":
			var sh := PackedVector2Array([P.call(0, -13), P.call(11, -8), P.call(9, 6), P.call(0, 13), P.call(-9, 6), P.call(-11, -8), P.call(0, -13)])
			draw_polyline(sh, col, thick, true)
			draw_line(P.call(-5, 0), P.call(5, 0), col, thin, true)
		"hide", "cunning_hide":
			_eye(P, col, thin, Vector2.ZERO, 1.0)
			draw_line(P.call(-12, 10), P.call(12, -10), col, thin, true)
		"help":
			draw_line(P.call(0, -11), P.call(0, 11), col, thick, true)
			draw_line(P.call(-11, 0), P.call(11, 0), col, thick, true)
		"dip":
			var drop := PackedVector2Array([P.call(0, -13), P.call(8, 3), P.call(6, 9), P.call(0, 12), P.call(-6, 9), P.call(-8, 3), P.call(0, -13)])
			draw_polyline(drop, col, thick, true)
		"stand_up":
			draw_line(P.call(0, 12), P.call(0, -8), col, thick, true)
			draw_colored_polygon(PackedVector2Array([P.call(0, -13), P.call(-7, -5), P.call(7, -5)]), col)
		"switch_weapons":
			draw_line(P.call(-11, -5), P.call(9, -5), col, thin, true)
			draw_colored_polygon(PackedVector2Array([P.call(12, -5), P.call(7, -9), P.call(7, -1)]), col)
			draw_line(P.call(11, 5), P.call(-9, 5), col, thin, true)
			draw_colored_polygon(PackedVector2Array([P.call(-12, 5), P.call(-7, 1), P.call(-7, 9)]), col)
		"drink", "feed":
			_flask(P, col, thick, Vector2.ZERO, 1.0)
			if base == "feed":
				draw_line(P.call(8, 10), P.call(14, 10), col, thin, true)
	if kind.begins_with("cunning_"):
		draw_circle(P.call(12, -12), 3 * k, Color(S.BONUS, 0.9))


func _sword(P: Callable, col: Color, t: float) -> void:
	draw_line(P.call(-10, 10), P.call(11, -11), col, t, true)
	draw_line(P.call(-12, 4), P.call(-4, 12), col, t, true)
	draw_line(P.call(-13, 13), P.call(-9, 9), col, t * 1.3, true)


func _eye(P: Callable, col: Color, t: float, at: Vector2, s: float) -> void:
	var pts := PackedVector2Array()
	for i in 13:
		var a := i / 12.0
		pts.append(P.call(at.x + lerpf(-12, 12, a) * s, at.y - sin(a * PI) * 7 * s))
	for i in 13:
		var a := 1.0 - i / 12.0
		pts.append(P.call(at.x + lerpf(-12, 12, a) * s, at.y + sin(a * PI) * 7 * s))
	draw_polyline(pts, col, t, true)
	draw_circle(P.call(at.x, at.y), 3 * s * size.x / 40.0, col)


func _flask(P: Callable, col: Color, t: float, at: Vector2, s: float) -> void:
	var o := at
	var pts := PackedVector2Array([P.call(o.x - 3 * s, o.y - 12 * s), P.call(o.x - 3 * s, o.y - 4 * s), P.call(o.x - 10 * s, o.y + 6 * s),
		P.call(o.x - 6 * s, o.y + 12 * s), P.call(o.x + 6 * s, o.y + 12 * s), P.call(o.x + 10 * s, o.y + 6 * s),
		P.call(o.x + 3 * s, o.y - 4 * s), P.call(o.x + 3 * s, o.y - 12 * s)])
	draw_polyline(pts, col, t, true)
	draw_line(P.call(o.x - 7 * s, o.y + 4 * s), P.call(o.x + 7 * s, o.y + 4 * s), Color(S.HP.lightened(0.2), 0.9), t, true)
