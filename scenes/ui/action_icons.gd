extends Control
## 행동·주문 아이콘(표현 계층): 검은 바탕 위에 빛나는 두꺼운 붓획 문양(BG3 주문 아이콘 화풍 참고, 문양은 자체).
## 색은 계열별로 통일한다 — 공용 행동 호박, 교활한 행동 보라, 무기 액션 은청, 물약 다홍, 클래스 기능은 클래스 데이터 color(문양은 기능 glyph),
## 주문은 피해 종류 색(불·냉기·번개·산·독·사령·광휘·역장·정신·천둥·물리), 피해가 없으면 회복 초록 또는 학파 색.
## kind = 행동 키(attack, wa_sweep, feature:second_wind, spell:fireball, drink:potion_of_healing ...).

const S := preload("res://scenes/ui/ui_style.gd")

## 계열 색
const FAM := {
	"common": Color(1.0, 0.74, 0.32), "cunning": Color(0.74, 0.52, 1.0), "weapon": Color(0.62, 0.82, 0.98), "item": Color(1.0, 0.45, 0.42),
	"fire": Color(1.0, 0.52, 0.18), "cold": Color(0.5, 0.88, 1.0), "lightning": Color(0.6, 0.62, 1.0), "acid": Color(0.72, 0.95, 0.25),
	"poison": Color(0.45, 0.9, 0.4), "necrotic": Color(0.35, 0.95, 0.7), "radiant": Color(1.0, 0.9, 0.45), "force": Color(0.85, 0.5, 1.0),
	"psychic": Color(1.0, 0.5, 0.82), "thunder": Color(0.55, 0.55, 1.0), "physical": Color(0.82, 0.84, 0.88), "heal": Color(0.45, 1.0, 0.6),
	"abjuration": Color(0.4, 0.72, 1.0), "conjuration": Color(1.0, 0.75, 0.35), "divination": Color(0.6, 0.95, 1.0),
	"enchantment": Color(1.0, 0.55, 0.78), "evocation": Color(1.0, 0.82, 0.6), "illusion": Color(0.68, 0.5, 1.0),
	"necromancy": Color(0.5, 0.9, 0.55), "transmutation": Color(1.0, 0.65, 0.4),
}

## 공용·무기·아이템·기능·존재 행동: [문양, 계열]
const ACTIONS := {
	"attack": ["sword", "common"], "ranged_attack": ["bow", "common"], "offhand_attack": ["dagger", "common"], "jump": ["jump", "common"],
	"shove": ["shove", "common"], "throw": ["throw", "common"], "dash": ["chevrons", "common"], "disengage": ["shield", "common"],
	"hide": ["eye_slash", "common"], "help": ["plus", "common"], "dip": ["drop", "common"], "stand_up": ["up_arrow", "common"],
	"switch_weapons": ["swap", "common"],
	"cunning_dash": ["chevrons", "cunning"], "cunning_disengage": ["shield", "cunning"], "cunning_hide": ["eye_slash", "cunning"],
	"sneak_melee": ["dagger_eye", "cunning"], "sneak_ranged": ["bow_eye", "cunning"],
	"drink": ["flask", "item"], "feed": ["flask_hand", "item"], "throw_potion": ["flask_arc", "item"],
	"wa_sweep": ["sweep", "weapon"], "wa_hamstring": ["hamstring", "weapon"], "wa_pommel": ["pommel", "weapon"],
	"wa_topple": ["topple", "weapon"], "wa_impale": ["spear", "weapon"],
	"entity:spiritual_weapon": ["sword", "force"], "entity:flaming_sphere": ["orb", "fire"], "entity:mage_hand": ["hand", "conjuration"],
}

## 클래스 기능: 기능 데이터 glyph(문양)와 클래스 데이터 color(색). 종족 기능은 공용 색.
static func _feature_icon(fid: String) -> Array:
	for cls: Dictionary in RulesDB.entries("class"):
		var feats: Array = cls.get("features", []).duplicate()
		for sc: Dictionary in cls.get("subclasses", []):
			feats.append_array(sc.get("features", []))
		for f: Dictionary in feats:
			if f["id"] == fid:
				return [str(f.get("glyph", "sparkle")), Color(str(cls.get("color", "#ffbd52")))]
	return ["sparkle", FAM["common"]]



var kind := ""
var dim := false
var _c := Vector2.ZERO
var _k := 1.0
var _col := Color.WHITE


static func has_icon(_key: String) -> bool:
	return true  # 모든 행동·주문(모르는 것은 계열 색 별 문양)


## 행동 키 → [문양, 색]
static func spec(key: String) -> Array:
	if ACTIONS.has(key):
		return [ACTIONS[key][0], FAM[ACTIONS[key][1]]]
	var base := key.get_slice(":", 0)
	if ACTIONS.has(base):
		return [ACTIONS[base][0], FAM[ACTIONS[base][1]]]
	if key.begins_with("spell:"):
		var sid := key.trim_prefix("spell:")
		var sp := RulesDB.get_entry("spell", sid)
		if sp.has("icon"):
			return [str(sp["icon"]["glyph"]), FAM.get(str(sp["icon"]["family"]), FAM["evocation"])]  # 주문 데이터 icon
		return ["star", FAM.get(sp.get("school", ""), FAM["evocation"])]
	if key.begins_with("feature:"):
		return _feature_icon(key.trim_prefix("feature:"))
	return ["star", FAM["common"]]


func _draw() -> void:
	var sp := spec(kind)
	_c = size / 2.0
	_k = minf(size.x, size.y) / 40.0
	_col = sp[1]
	if dim:
		_col = Color(_col.lerp(Color(0.5, 0.5, 0.5), 0.6), 0.45)
	# 바탕: 검은 원 + 아주 옅은 계열 색 안개
	draw_circle(_c, 19.5 * _k, Color(0.02, 0.02, 0.025))
	draw_circle(_c, 15.0 * _k, Color(_col, 0.07))
	_motif(sp[0])


# ---------- 붓획 도구(빛 번짐 3겹 + 심) ----------

func _p(x: float, y: float) -> Vector2:
	return _c + Vector2(x, y) * _k


func L(pts: Array, w: float = 1.0) -> void:
	var pv := PackedVector2Array()
	for q: Vector2 in pts:
		pv.append(_p(q.x, q.y))
	var base := 2.7 * _k * w
	draw_polyline(pv, Color(_col, 0.10 * _col.a), base * 3.4, true)
	draw_polyline(pv, Color(_col, 0.22 * _col.a), base * 2.0, true)
	draw_polyline(pv, _col, base, true)
	draw_polyline(pv, Color(_col.lightened(0.65), 0.85 * _col.a), base * 0.38, true)
	# 붓끝: 끝점을 둥글게
	for q: Vector2 in [pts[0], pts[pts.size() - 1]]:
		draw_circle(_p(q.x, q.y), base * 0.5, _col)


func A(x: float, y: float, r: float, a0: float, a1: float, w: float = 1.0) -> void:
	var pts: Array = []
	var n := maxi(8, int(absf(a1 - a0) * 8))
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		pts.append(Vector2(x + cos(a) * r, y + sin(a) * r))
	L(pts, w)


func D(x: float, y: float, r: float) -> void:
	draw_circle(_p(x, y), r * _k * 2.2, Color(_col, 0.15 * _col.a))
	draw_circle(_p(x, y), r * _k, _col)
	draw_circle(_p(x, y), r * _k * 0.45, Color(_col.lightened(0.7), _col.a))


func V2(x: float, y: float) -> Vector2:
	return Vector2(x, y)


# ---------- 문양 ----------

func _motif(m: String) -> void:
	match m:
		"sword":
			L([V2(-11, 11), V2(10, -10)]); L([V2(-13, 5), V2(-5, 13)]); L([V2(-14, 14), V2(-10, 10)], 1.2)
		"bow":
			A(-4, 0, 13, -1.25, 1.25); L([V2(0, -12), V2(0, 12)], 0.5); L([V2(-9, 0), V2(13, 0)], 0.8); L([V2(9, -4), V2(13, 0), V2(9, 4)], 0.8)
		"dagger":
			L([V2(-8, 8), V2(9, -9)]); L([V2(-11, 4), V2(-4, 11)]); D(-11, 11, 1.6)
		"dagger_eye":
			L([V2(-10, 10), V2(6, -6)]); L([V2(-12, 6), V2(-6, 12)]); _eye(6, -6, 0.55)
		"bow_eye":
			A(-6, 0, 12, -1.2, 1.2); L([V2(-10, 0), V2(9, 0)], 0.8); _eye(8, 8, 0.5)
		"jump":
			A(0, 9, 13, PI + 0.35, TAU - 0.35); L([V2(8, 1), V2(12, 5), V2(15, -1)], 0.8); L([V2(-14, 13), V2(14, 13)], 0.5)
		"shove":
			for y: float in [-6.0, 0.0, 6.0]:
				L([V2(-13, y), V2(3, y)], 0.7)
			L([V2(3, -11), V2(13, 0), V2(3, 11)])
		"throw":
			A(0, 11, 14, PI + 0.45, TAU - 0.7, 0.7); D(10, -5, 3.2)
		"chevrons":
			L([V2(-12, -10), V2(-3, 0), V2(-12, 10)]); L([V2(-1, -10), V2(8, 0), V2(-1, 10)]); L([V2(9, -6), V2(13, 0), V2(9, 6)], 0.6)
		"shield":
			L([V2(0, -14), V2(11, -9), V2(9, 5), V2(0, 14), V2(-9, 5), V2(-11, -9), V2(0, -14)]); L([V2(0, -8), V2(0, 8)], 0.6)
		"eye":
			_eye(0, 0, 1.0)
		"eye_slash":
			_eye(0, 0, 1.0); L([V2(-13, 11), V2(13, -11)], 0.8)
		"plus":
			L([V2(0, -12), V2(0, 12)]); L([V2(-12, 0), V2(12, 0)])
		"drop":
			L([V2(0, -14), V2(8, 2), V2(7, 8), V2(0, 12), V2(-7, 8), V2(-8, 2), V2(0, -14)])
		"drops":
			for q: Vector2 in [V2(-7, -4), V2(6, -7), V2(0, 7)]:
				L([q + V2(0, -6), q + V2(4, 1), q + V2(0, 4), q + V2(-4, 1), q + V2(0, -6)], 0.75)
		"up_arrow":
			L([V2(0, 13), V2(0, -10)]); L([V2(-8, -3), V2(0, -12), V2(8, -3)])
		"swap":
			L([V2(-12, -5), V2(10, -5)], 0.8); L([V2(6, -10), V2(12, -5), V2(6, 0)], 0.8)
			L([V2(12, 6), V2(-10, 6)], 0.8); L([V2(-6, 1), V2(-12, 6), V2(-6, 11)], 0.8)
		"flask", "flask_hand", "flask_arc":
			var s := 0.65 if m == "flask_arc" else 1.0
			var o := V2(6, -3) if m == "flask_arc" else V2(0, 0)
			L([o + V2(-3, -12) * s, o + V2(-3, -4) * s, o + V2(-10, 6) * s, o + V2(-6, 12) * s, o + V2(6, 12) * s, o + V2(10, 6) * s, o + V2(3, -4) * s, o + V2(3, -12) * s])
			L([o + V2(-7, 5) * s, o + V2(7, 5) * s], 0.6)
			if m == "flask_hand":
				A(0, 14, 9, PI + 0.3, TAU - 0.3, 0.6)
			elif m == "flask_arc":
				A(-4, 12, 12, PI + 0.6, TAU - 1.1, 0.6)
		"sweep":
			L([V2(-9, 9), V2(9, -9)]); A(0, 0, 14, -2.8, -0.2, 0.8)
		"hamstring":
			L([V2(-12, -2), V2(10, -2)]); L([V2(-6, 4), V2(-2, 10), V2(2, 4)], 0.7); L([V2(4, 4), V2(8, 10), V2(12, 4)], 0.7)
		"pommel":
			D(0, 0, 4.0)
			for i in 8:
				var a := TAU * i / 8.0
				L([V2(cos(a) * 8, sin(a) * 8), V2(cos(a) * 13, sin(a) * 13)], 0.6)
		"topple":
			L([V2(-11, -11), V2(6, 6)]); L([V2(-12, 12), V2(12, 12)], 0.8); L([V2(6, 0), V2(6, 6), V2(0, 6)], 0.8)
		"spear":
			L([V2(-13, 13), V2(9, -9)]); L([V2(6, -13), V2(13, -13), V2(13, -6)]); L([V2(7, -7), V2(13, -13)], 0.6)
		"breath":
			A(-3, -2, 8, -0.5, 4.2); A(5, 4, 6, 2.6, 7.0, 0.8); D(-11, 10, 2.0)
		"surge":
			L([V2(-12, 12), V2(-4, 2), V2(-8, 2), V2(2, -12)]); L([V2(3, 12), V2(9, 3), V2(6, 3), V2(13, -8)], 0.7)
		"crosshair":
			A(0, 0, 10, 0, TAU, 0.8); L([V2(0, -15), V2(0, -6)], 0.7); L([V2(0, 6), V2(0, 15)], 0.7)
			L([V2(-15, 0), V2(-6, 0)], 0.7); L([V2(6, 0), V2(15, 0)], 0.7); D(0, 0, 1.6)
		"sparkle":
			L([V2(0, -14), V2(0, 14)], 0.7); L([V2(-14, 0), V2(14, 0)], 0.7)
			L([V2(-8, -8), V2(8, 8)], 0.5); L([V2(8, -8), V2(-8, 8)], 0.5); D(0, 0, 2.5)
		"skull", "skull_rays":
			A(0, -2, 9, PI * 0.85, PI * 2.15)
			L([V2(-7, 4), V2(-5, 11), V2(5, 11), V2(7, 4)], 0.8)
			D(-4, -2, 2.2); D(4, -2, 2.2)
			if m == "skull_rays":
				for i in 5:
					var a := -PI * 0.9 + i * 0.45
					L([V2(cos(a) * 13, sin(a) * 13 - 2), V2(cos(a) * 17, sin(a) * 17 - 2)], 0.5)
		"heart", "heart_plus":
			L([V2(0, 12), V2(-11, 1), V2(-11, -6), V2(-6, -11), V2(0, -6), V2(6, -11), V2(11, -6), V2(11, 1), V2(0, 12)])
			if m == "heart_plus":
				L([V2(0, -4), V2(0, 5)], 0.6); L([V2(-4, 0), V2(4, 0)], 0.6)
		"heal_cross":
			L([V2(-4, -13), V2(4, -13), V2(4, -4), V2(13, -4), V2(13, 4), V2(4, 4), V2(4, 13), V2(-4, 13), V2(-4, 4), V2(-13, 4), V2(-13, -4), V2(-4, -4), V2(-4, -13)], 0.8)
		"up_arrows", "down_arrows":
			var d := 1.0 if m == "down_arrows" else -1.0
			for x: float in [-7.0, 7.0]:
				L([V2(x, -10 * d), V2(x, 9 * d)], 0.7); L([V2(x - 5, 4 * d), V2(x, 10 * d), V2(x + 5, 4 * d)], 0.7)
		"moon":
			A(0, 0, 12, 0.6, 5.7); A(5, -2, 9, 1.2, 5.1, 0.7)
		"spiral":
			var pts: Array = []
			for i in 40:
				var a := i * 0.4
				pts.append(V2(cos(a) * (2 + i * 0.32), sin(a) * (2 + i * 0.32)))
			L(pts, 0.75)
		"mask":
			L([V2(-14, -6), V2(14, -6), V2(12, 4), V2(4, 7), V2(0, 3), V2(-4, 7), V2(-12, 4), V2(-14, -6)], 0.85)
			D(-6, -1, 2.0); D(6, -1, 2.0)
		"chains":
			for q: Vector2 in [V2(-7, -7), V2(0, 0), V2(7, 7)]:
				A(q.x, q.y, 5, 0, TAU, 0.6)
		"lock":
			A(0, -5, 6, PI, TAU, 0.8); L([V2(-9, -3), V2(9, -3), V2(9, 12), V2(-9, 12), V2(-9, -3)]); D(0, 5, 1.8)
		"key":
			A(-6, -6, 6, 0, TAU, 0.8); L([V2(-2, -2), V2(12, 12)]); L([V2(8, 8), V2(12, 4)], 0.7); L([V2(5, 5), V2(9, 1)], 0.7)
		"counter":
			A(0, 0, 12, 0, TAU, 0.9); L([V2(-9, 9), V2(9, -9)])
		"rune":
			L([V2(0, -13), V2(0, 13)]); L([V2(0, -6), V2(8, -12)], 0.7); L([V2(0, 2), V2(-8, -4)], 0.7); L([V2(0, 8), V2(8, 13)], 0.7)
			A(0, 0, 16, 0, TAU, 0.4)
		"wing":
			L([V2(-13, 8), V2(-6, -4), V2(4, -11), V2(13, -12)])
			L([V2(-10, 9), V2(-2, 2), V2(9, -3)], 0.7); L([V2(-7, 11), V2(1, 8), V2(8, 6)], 0.6)
		"feather":
			L([V2(-12, 13), V2(10, -11)], 0.7)
			for i in 5:
				var t := -6.0 + i * 3.5
				L([V2(t, -t), V2(t - 7 + i, -t - 3 - i)], 0.5)
				L([V2(t, -t), V2(t + 3 + i, -t + 7 - i)], 0.5)
		"swirl":
			A(0, 0, 11, 0.3, 5.0); A(0, 0, 6, 3.4, 7.8, 0.7); D(0, 0, 1.6)
		"cloud":
			A(-6, 2, 6, 1.6, 4.9); A(1, -3, 7, 3.4, 6.2); A(8, 2, 5, 4.4, 7.9); L([V2(-6, 8), V2(9, 8)], 0.8)
		"wind":
			for y: float in [-7.0, 0.0, 7.0]:
				L([V2(-13, y), V2(6, y)], 0.7)
				A(6, y - 3, 3, -PI / 2, PI / 2, 0.6)
		"waves":
			for r: float in [5.0, 10.0, 15.0]:
				A(-8, 0, r, -0.9, 0.9, 0.8)
		"web":
			for i in 6:
				var a := TAU * i / 6.0
				L([V2(0, 0), V2(cos(a) * 14, sin(a) * 14)], 0.5)
			A(0, 0, 6, 0, TAU, 0.5); A(0, 0, 11, 0, TAU, 0.5)
		"voice":
			L([V2(-12, -4), V2(-6, -4), V2(0, -10), V2(0, 10), V2(-6, 4), V2(-12, 4), V2(-12, -4)], 0.8)
			A(2, 0, 6, -0.8, 0.8, 0.6); A(2, 0, 11, -0.8, 0.8, 0.6)
		"voice_slash":
			L([V2(-12, -4), V2(-6, -4), V2(0, -10), V2(0, 10), V2(-6, 4), V2(-12, 4), V2(-12, -4)], 0.8); L([V2(-14, 12), V2(14, -12)], 0.7)
		"hand":
			L([V2(-6, 13), V2(-8, 0), V2(-8, -8)], 0.8); L([V2(-3, -1), V2(-3, -13)], 0.7); L([V2(2, -1), V2(2, -14)], 0.7)
			L([V2(7, 0), V2(7, -11)], 0.7); L([V2(8, 4), V2(12, -3)], 0.7); L([V2(-6, 13), V2(6, 13), V2(9, 5)], 0.8)
		"book":
			L([V2(0, -9), V2(-12, -12), V2(-12, 10), V2(0, 13), V2(12, 10), V2(12, -12), V2(0, -9), V2(0, 13)], 0.8)
		"resize":
			L([V2(-12, -12), V2(12, 12)], 0.7); L([V2(-12, -4), V2(-12, -12), V2(-4, -12)], 0.7); L([V2(12, 4), V2(12, 12), V2(4, 12)], 0.7)
		"spike":
			L([V2(-12, 12), V2(10, -10)]); L([V2(5, -12), V2(12, -12), V2(12, -5)], 0.8); A(-4, 4, 5, 0, TAU, 0.5)
		"arrow":
			L([V2(-12, 12), V2(11, -11)]); L([V2(4, -12), V2(12, -12), V2(12, -4)]); L([V2(-12, 6), V2(-9, 9), V2(-6, 12)], 0.6)
		"leaf":
			L([V2(-11, 12), V2(-4, 0), V2(4, -8), V2(12, -12)], 0.6); A(4, 4, 11, -2.4, -0.2, 0.9); A(-4, -4, 11, 0.7, 2.9, 0.9)
		"mend":
			L([V2(-12, 12), V2(12, -12)], 0.8); L([V2(-12, -12), V2(12, 12)], 0.8); A(0, 0, 5, 0, TAU, 0.6)
		"dome":
			A(0, 6, 13, PI, TAU); L([V2(-15, 6), V2(15, 6)], 0.8); D(0, 2, 2.0)
		"sun":
			A(0, 0, 6, 0, TAU, 0.9)
			for i in 8:
				var a := TAU * i / 8.0
				L([V2(cos(a) * 10, sin(a) * 10), V2(cos(a) * 14, sin(a) * 14)], 0.6)
		"star":
			L([V2(0, -14), V2(4, -4), V2(14, 0), V2(4, 4), V2(0, 14), V2(-4, 4), V2(-14, 0), V2(-4, -4), V2(0, -14)], 0.8)
		"flame":
			L([V2(0, 13), V2(-9, 4), V2(-7, -4), V2(-2, -1), V2(-3, -13), V2(6, -5), V2(9, 4), V2(0, 13)])
			L([V2(0, 10), V2(-3, 4), V2(0, -1), V2(3, 4), V2(0, 10)], 0.6)
		"flame_cone":
			# 손에서 부채꼴로 뻗는 불꽃 혀 셋
			for a: float in [-1.15, -0.7, -0.25]:
				var d := V2(cos(a), sin(a))
				var n := V2(-d.y, d.x)
				var b := V2(-12, 11)
				L([b, b + d * 9 + n * 3, b + d * 14 - n * 2, b + d * 22], 0.7)
		"fireball":
			A(2, -2, 8, 0, TAU, 1.0); L([V2(-4, 4), V2(-13, 13)], 0.8); L([V2(-2, 8), V2(-9, 14)], 0.5); L([V2(-8, 0), V2(-14, 6)], 0.5)
		"orb":
			A(0, 0, 9, 0, TAU, 1.0); A(0, 0, 14, 0.5, 2.0, 0.5); A(0, 0, 14, 3.6, 5.1, 0.5); D(-3, -3, 2.0)
		"snowflake":
			for i in 3:
				var a := PI * i / 3.0
				L([V2(cos(a) * 13, sin(a) * 13), V2(-cos(a) * 13, -sin(a) * 13)], 0.7)
			for i in 6:
				var a := TAU * i / 6.0
				var tip := V2(cos(a) * 9, sin(a) * 9)
				L([tip + V2(cos(a + 2.4) * 4, sin(a + 2.4) * 4), tip, tip + V2(cos(a - 2.4) * 4, sin(a - 2.4) * 4)], 0.5)
		"shard":
			L([V2(-12, 12), V2(-4, -2), V2(8, -13), V2(4, 2), V2(-12, 12)], 0.85); L([V2(-4, -2), V2(4, 2)], 0.5)
		"bolt":
			L([V2(3, -14), V2(-6, 1), V2(2, 1), V2(-4, 14)]); L([V2(8, -6), V2(4, 0), V2(9, 0), V2(5, 7)], 0.6)
		"darts":
			for y: float in [-8.0, 0.0, 8.0]:
				L([V2(-12, y + 4), V2(10, y - 3)], 0.7)
				D(10, y - 3, 1.7)
		"rays":
			for y: float in [-8.0, 0.0, 8.0]:
				L([V2(-13, y + 6), V2(13, y - 6)], 0.7)
		_:
			L([V2(0, -14), V2(4, -4), V2(14, 0), V2(4, 4), V2(0, 14), V2(-4, 4), V2(-14, 0), V2(-4, -4), V2(0, -14)], 0.8)


func _eye(x: float, y: float, s: float) -> void:
	var pts: Array = []
	for i in 13:
		var a := i / 12.0
		pts.append(V2(x + lerpf(-13, 13, a) * s, y - sin(a * PI) * 8 * s))
	for i in 13:
		var a := 1.0 - i / 12.0
		pts.append(V2(x + lerpf(-13, 13, a) * s, y + sin(a * PI) * 8 * s))
	L(pts, 0.8 if s >= 1.0 else 0.55)
	D(x, y, 3.0 * s)
