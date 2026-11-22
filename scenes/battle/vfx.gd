extends Node2D
## 전투 효과(표현 계층): 판정 결과 신호만 듣고 그린다.
##   공격: 원거리는 날아가는 빛줄기, 근접은 대상 위 베기 호. 피해·회복: 떠오르는 숫자(피해 종류 색).
##   주문 시전: 조준 칸에 퍼지는 고리(학파 색). 불 표면: 칸마다 불꽃 입자(CPUParticles2D — GL Compatibility).

const V := preload("res://scenes/battle/view3q.gd")
const S := preload("res://scenes/ui/ui_style.gd")
const DMG_COL := {"fire": Color(1.0, 0.55, 0.2), "cold": Color(0.6, 0.85, 1.0), "lightning": Color(0.85, 0.85, 1.0),
	"acid": Color(0.6, 0.9, 0.3), "poison": Color(0.55, 0.8, 0.35), "necrotic": Color(0.6, 0.5, 0.7), "radiant": Color(1.0, 0.9, 0.55),
	"force": Color(0.75, 0.7, 1.0), "psychic": Color(0.9, 0.55, 0.9), "thunder": Color(0.8, 0.75, 0.95)}
const SCHOOL_COL := {"evocation": Color(1.0, 0.5, 0.25), "abjuration": Color(0.45, 0.7, 1.0), "conjuration": Color(0.95, 0.8, 0.4),
	"divination": Color(0.7, 0.9, 1.0), "enchantment": Color(1.0, 0.6, 0.85), "illusion": Color(0.75, 0.6, 1.0),
	"necromancy": Color(0.55, 0.85, 0.5), "transmutation": Color(0.9, 0.7, 0.45)}

var scene: Node
var _fx: Array = []
var _fire: Dictionary = {}  # 칸 → CPUParticles2D


func _ready() -> void:
	z_index = 60
	EventBus.on_after_attack_roll.connect(_on_attack)
	EventBus.on_damage_taken.connect(_on_damage)
	EventBus.on_heal.connect(_on_heal)
	EventBus.on_spell_cast.connect(_on_spell)


func _exit_tree() -> void:
	for pair: Array in [[EventBus.on_after_attack_roll, _on_attack], [EventBus.on_damage_taken, _on_damage],
			[EventBus.on_heal, _on_heal], [EventBus.on_spell_cast, _on_spell]]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])


func _pos(c: Variant) -> Vector2:
	if c is Node and scene.views.has(c):
		return scene.views[c].position + Vector2(0, -50)
	return Vector2.ZERO


func _on_attack(res: Dictionary) -> void:
	if res.get("preview", false) or not scene.views.has(res.get("attacker")) or not scene.views.has(res.get("target")):
		return
	var kind: String = res.get("attack", {}).get("kind", "melee")
	var col := Color(1, 0.95, 0.8) if res.get("hit", false) else Color(0.6, 0.6, 0.6)
	if kind == "ranged":
		_fx.append({"type": "bolt", "a": _pos(res["attacker"]), "b": _pos(res["target"]), "t": 0.0, "life": 0.35, "col": col})
	else:
		_fx.append({"type": "slash", "at": _pos(res["target"]), "t": 0.0, "life": 0.3, "col": col})
	if not res.get("hit", false):
		_fx.append({"type": "text", "at": _pos(res["target"]), "text": "빗나감", "t": 0.0, "life": 0.9, "col": Color(0.7, 0.7, 0.7)})


func _on_damage(info: Dictionary) -> void:
	var t: Variant = info.get("target")
	if not scene.views.has(t) or int(info.get("amount", 0)) <= 0:
		return
	var dtype := ""
	for t2: String in info.get("result", {}).get("by_type", {}):
		dtype = t2
	_fx.append({"type": "text", "at": _pos(t), "text": str(int(info["amount"])), "t": 0.0, "life": 1.0,
		"col": DMG_COL.get(dtype, Color(1.0, 0.85, 0.75)), "big": info.get("opts", {}).get("crit", false)})


func _on_heal(info: Dictionary) -> void:
	if scene.views.has(info.get("target")) and int(info.get("amount", 0)) > 0:
		_fx.append({"type": "text", "at": _pos(info["target"]), "text": "+%d" % int(info["amount"]), "t": 0.0, "life": 1.0, "col": Color(0.5, 0.95, 0.5)})


func _on_spell(ctx: Dictionary) -> void:
	var aim: Variant = ctx.get("aim")
	if not (aim is Vector2i):
		return
	var g: Node = scene.world["grid"]
	var sp := RulesDB.get_entry("spell", str(ctx.get("spell", "")))
	var p := V.top(aim, g.height(aim)) + Vector2(V.T * 0.5, V.T * 0.4)
	_fx.append({"type": "ring", "at": p, "t": 0.0, "life": 0.6, "col": SCHOOL_COL.get(sp.get("school", ""), Color(0.9, 0.85, 0.7))})


## 불 표면 칸마다 불꽃 입자(맵이 바뀔 때 부른다)
func sync_surfaces() -> void:
	var g: Node = scene.world["grid"]
	var want := {}
	for c in g.all_cells():
		if g.surface_id(c) == "fire":
			want[c] = true
	for c: Vector2i in _fire.keys():
		if not want.has(c) or not is_instance_valid(_fire[c]):
			if is_instance_valid(_fire[c]):
				_fire[c].queue_free()
			_fire.erase(c)
	for c: Vector2i in want:
		if _fire.has(c):
			continue
		var p := CPUParticles2D.new()
		p.amount = 10
		p.lifetime = 0.8
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		p.emission_rect_extents = Vector2(V.T * 0.4, V.T * 0.25)
		p.direction = Vector2(0, -1)
		p.spread = 15.0
		p.gravity = Vector2(0, -40)
		p.initial_velocity_min = 20.0
		p.initial_velocity_max = 45.0
		p.scale_amount_min = 2.0
		p.scale_amount_max = 4.0
		var grad := Gradient.new()
		grad.set_color(0, Color(1.0, 0.75, 0.3, 0.9))
		grad.set_color(1, Color(0.8, 0.2, 0.05, 0.0))
		p.color_ramp = grad
		p.position = V.top(c, g.height(c)) + Vector2(V.T * 0.5, V.T * 0.5)
		add_child(p)
		_fire[c] = p


func _process(delta: float) -> void:
	if _fx.is_empty():
		return
	for f: Dictionary in _fx:
		f["t"] += delta
	_fx = _fx.filter(func(f: Dictionary) -> bool: return f["t"] < f["life"])
	queue_redraw()


func _draw() -> void:
	var font := S.title_font()
	for f: Dictionary in _fx:
		var k: float = f["t"] / f["life"]
		var col: Color = f["col"]
		match f["type"]:
			"bolt":
				var head: Vector2 = f["a"].lerp(f["b"], minf(k * 1.6, 1.0))
				var tail: Vector2 = f["a"].lerp(f["b"], maxf(k * 1.6 - 0.35, 0.0))
				draw_line(tail, head, Color(col, 1.0 - k * 0.5), 3.0, true)
				draw_circle(head, 3.5, Color(col, 1.0 - k))
			"slash":
				var c: Vector2 = f["at"]
				draw_arc(c, 22.0, -2.4 + k * 1.2, -0.6 + k * 1.2, 16, Color(col, 1.0 - k), 4.0, true)
			"ring":
				draw_arc(f["at"], 10.0 + k * 50.0, 0, TAU, 40, Color(col, 1.0 - k), 3.0, true)
				draw_circle(f["at"], 8.0 * (1.0 - k), Color(col, 0.6 * (1.0 - k)))
			"text":
				var size := 26 if f.get("big", false) else 20
				var at: Vector2 = f["at"] + Vector2(-20, -30 * k)
				draw_string_outline(font, at, f["text"], HORIZONTAL_ALIGNMENT_CENTER, 40, size, 5, Color(0, 0, 0, 1.0 - k))
				draw_string(font, at, f["text"], HORIZONTAL_ALIGNMENT_CENTER, 40, size, Color(col, 1.0 - k * 0.8))
