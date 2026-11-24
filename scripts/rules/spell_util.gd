extends RefCounted
## 스크립트 주문(scripts/rules/effects/*.gd)이 함께 쓰는 도구. 상태 없음.

# spellcasting.gd → 주문 스크립트 → 이 파일 순으로 불리므로 preload하면 순환 참조가 된다. 실행 중에 load한다.
static func _sp() -> Variant:
	return load("res://scripts/rules/spellcasting.gd")


static func grid(ctx: Dictionary) -> Node:
	return ctx["world"]["grid"]


## 조준 칸의 생물(자기 대상 주문이면 시전자)
static func target(ctx: Dictionary) -> Node:
	var g := grid(ctx)
	var aim: Variant = ctx.get("aim")
	if aim is Vector2i and g.in_bounds(aim):
		var t: Node = g.creature_at(aim)
		if t != null:
			return t
	if ctx["spell"].get("range", {}).get("type", "") == "self":
		return ctx["self"]
	return null


static func aim_cell(ctx: Dictionary) -> Vector2i:
	var aim: Variant = ctx.get("aim")
	return aim if aim is Vector2i else grid(ctx).cell_of(ctx["self"])


static func dc(ctx: Dictionary) -> int:
	return _sp().spell_dc(ctx["self"])


static func duration(ctx: Dictionary) -> int:
	return _sp().duration_turns(ctx["spell"])


## 인스턴스에 묶인 상태(주문이 끝나면 걷힘)
static func add_condition(ctx: Dictionary, t: Node, id: String, turns: int = 0, params: Dictionary = {}) -> void:
	var p := params.duplicate()
	p["instance"] = ctx["instance"]["id"]
	t.apply_condition(id, turns if turns != 0 else duration(ctx), ctx["self"], p)
	if not t in ctx["instance"]["targets"]:
		ctx["instance"]["targets"].append(t)


## 값을 바꾸고 주문이 끝나면 되돌린다
static func set_until_end(ctx: Dictionary, t: Node, field: String, value: Variant) -> void:
	ctx["instance"]["reverts"].append({"creature": t, "field": field, "value": t.get(field)})
	t.set(field, value)


## 주문이 끝날 때 할 일을 덧붙인다(여러 개 가능)
static func on_end(ctx: Dictionary, f: Callable) -> void:
	var inst: Dictionary = ctx["instance"]
	if inst.has("on_end"):
		var prev: Callable = inst["on_end"]
		inst["on_end"] = func() -> void:
			prev.call()
			f.call()
	else:
		inst["on_end"] = f


## 이 생물이 피해를 받으면 주문을 끝낸다(Charm Person·Suggestion·Calm Emotions — 원문 '피해를 받으면')
static func end_when_damaged(ctx: Dictionary, t: Node) -> void:
	var id: int = ctx["instance"]["id"]
	var cb := func(info: Dictionary) -> void:
		if info.get("target") == t and int(info.get("amount", 0)) > 0:
			_sp().end_instance(id)
	EventBus.on_damage_taken.connect(cb)
	on_end(ctx, func() -> void:
		if EventBus.on_damage_taken.is_connected(cb):
			EventBus.on_damage_taken.disconnect(cb))


## 원형 칸(Area.circle)
static func circle(ctx: Dictionary, center: Vector2i, r: int) -> Array[Vector2i]:
	return preload("res://scripts/rules/area.gd").circle(grid(ctx), center, r)


static func creatures_in(ctx: Dictionary, cells: Array[Vector2i]) -> Array:
	return preload("res://scripts/rules/area.gd").creatures_in(grid(ctx), cells)


## 표시용 존재(Spiritual Weapon·Flaming Sphere·Mage Hand 등): 인스턴스의 entity {kind, cell}
static func entity(ctx: Dictionary, kind: String, cell: Vector2i) -> Dictionary:
	var e := {"kind": kind, "cell": cell}
	ctx["instance"]["entity"] = e
	return e


## 시전자의 살아 있는 표시 존재 인스턴스(kind)
static func find_entity(caster: Node, kind: String) -> Dictionary:
	for inst: Dictionary in _sp().instances.values():
		if inst["caster"] == caster and inst.get("entity", {}).get("kind", "") == kind:
			return inst
	return {}


## 끌어당기기(가시덩굴 채찍·번개 올가미·휘감는 덩굴): toward 칸 쪽으로 한 칸씩 최대 n칸. 막히거나 toward에 닿기 직전이면 멈춘다.
static func pull(ctx: Dictionary, t: Node, toward: Vector2i, n: int) -> int:
	var g := grid(ctx)
	var Physics := preload("res://scripts/rules/physics.gd")
	var cur: Vector2i = g.cell_of(t)
	var start := cur
	var moved := 0
	for i in n:
		var d := toward - cur
		if maxi(absi(d.x), absi(d.y)) <= 1:
			break
		var nxt := cur + Vector2i(signi(d.x), signi(d.y))
		if Physics._push_step_blocked(g, t, cur, nxt) != "":
			break
		cur = nxt
		moved += 1
	if moved > 0:
		g.move_creature(t, cur)
		var drop: int = g.height(start) - g.height(cur)
		if drop > 0:
			Physics.fall(t, drop)
	return moved
