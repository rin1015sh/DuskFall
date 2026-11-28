extends Node2D
## 전투 효과(표현 계층): 판정 결과 신호만 듣고 그린다.
##   도트 효과(pixel_fx.gd — assets/pixel_fx, pixelfx MIT에서 구운 시트)를 3D 세계 그 자리에 띄운다:
##   무기 공격 = 피해 종류별 베기·찌르기·둔기(몬스터 베기는 발톱), 원거리 = 화살이 날아가 맞으면 불꽃 튐, 치명타 번쩍,
##   주문 = 모양(공격 굴림 = 날아가는 탄 → 맞는 자리 터짐, 구·정육면체·원기둥 = 범위 폭발, 원뿔 = 숨결, 선 = 빛줄기, 자기 둘레 = 둘레 폭발)
##        × 피해 종류(불·냉기·번개·광휘·사령·산성·독·천둥·역장/정신 = 비전). 피해 없는 주문: 회복 = 꽃, 보호 = 방패, 강화 = 축복, 약화 = 인장.
##   상태 이상 = 머리 위·발밑 고리 효과(화상·중독·매혹·혼란·저주·기절·수면·느려짐·출혈·격노), 쓰러짐 = 연기, 불 표면 = 칸마다 불꽃.
##   효과는 잠깐 광원이 되어(pixel_view.set_dyn_lights) 둘레 바닥·캐릭터를 물들인다. 피해·회복 숫자는 화면 글자(2D).
## 효과 위치는 3D 세계 좌표로 들고 있다가 그릴 때마다 화면에 투영한다(카메라가 움직여도 따라간다).

const V := preload("res://scenes/battle/view3d.gd")
const S := preload("res://scenes/ui/ui_style.gd")
const PFX := preload("res://scenes/battle/pixel_fx.gd")
const Area := preload("res://scripts/rules/area.gd")
const DMG_COL := {"fire": Color(1.0, 0.55, 0.2), "cold": Color(0.6, 0.85, 1.0), "lightning": Color(0.85, 0.85, 1.0),
	"acid": Color(0.6, 0.9, 0.3), "poison": Color(0.55, 0.8, 0.35), "necrotic": Color(0.6, 0.5, 0.7), "radiant": Color(1.0, 0.9, 0.55),
	"force": Color(0.75, 0.7, 1.0), "psychic": Color(0.9, 0.55, 0.9), "thunder": Color(0.8, 0.75, 0.95)}
## 피해 종류 → 효과 이름 꼬리(bolt_/hit_/area_<꼬리>)
const FAMILY := {"fire": "fire", "cold": "cold", "lightning": "lightning", "radiant": "radiant", "necrotic": "necrotic",
	"acid": "acid", "poison": "poison", "thunder": "thunder", "force": "arcane", "psychic": "arcane"}
## 효과 광원 색(꼬리별)
const FX_LIGHT := {"fire": Color(1.0, 0.55, 0.2), "cold": Color(0.5, 0.75, 1.0), "lightning": Color(0.6, 0.75, 1.0),
	"radiant": Color(1.0, 0.85, 0.45), "necrotic": Color(0.55, 0.3, 0.8), "acid": Color(0.5, 0.9, 0.3), "poison": Color(0.5, 0.85, 0.3),
	"thunder": Color(0.7, 0.7, 0.9), "arcane": Color(0.7, 0.45, 1.0), "heal": Color(0.5, 1.0, 0.6), "holy": Color(1.0, 0.9, 0.6)}
## 상태 이상 → 고리 효과(머리 위 head = true / 발밑)
const STATUS_FX := {"burning": ["st_burning", false], "poisoned": ["st_poisoned", false], "charmed": ["st_charmed", true],
	"hypnotized": ["st_charmed", true], "enthralled": ["st_charmed", true], "dazed": ["st_confused", true], "reeling": ["st_confused", true],
	"maddened": ["st_confused", true], "cursed": ["st_cursed", true], "hexed": ["st_cursed", true], "hexblades_curse": ["st_cursed", true],
	"stunned": ["st_stunned", true], "paralyzed": ["st_stunned", true], "asleep": ["st_sleep", true], "slowed": ["st_slowed", true],
	"bleeding": ["st_bleeding", false], "open_wound": ["st_bleeding", false], "raging": ["st_rage", false], "frenzy": ["st_rage", false]}
## 바닥 효과(fx_floor.gdshader — 바닥에 눕힌 판, 카메라 각도·실제 범위 크기): 꼬리 → [셰이더 style, 길이(초), 색 계단 5단(어두움 → 밝음, 게임 그림 색에서)]
const FLOOR_STYLE := {
	"fire": [0, 2.2, ["#2a1410", "#5a2414", "#a8401c", "#ec8a34", "#ffd88a"]],
	"cold": [1, 2.4, ["#10202e", "#24506e", "#4c8cb0", "#9cd0e6", "#e6f6ff"]],
	"heal": [2, 2.0, ["#0e2a1c", "#1e5a34", "#3e9a54", "#86d48a", "#d8f6c8"]],
	"lightning": [3, 1.6, ["#101428", "#26306a", "#4a6ac8", "#9cc4ff", "#f0f6ff"]],
	"radiant": [4, 2.0, ["#2a1e0c", "#6a4e1c", "#b8902e", "#ecd27a", "#fff6d8"]],
	"necrotic": [5, 2.4, ["#0c0814", "#24142e", "#4a2858", "#8a5aa8", "#d0b0f0"]],
	"poison": [6, 2.6, ["#0e1a0c", "#22401a", "#4a7a26", "#90c040", "#d8f080"]],
	"acid": [6, 2.4, ["#141a08", "#34420e", "#6a8a1a", "#b4d23a", "#eef8a0"]],
	"arcane": [7, 2.0, ["#140c24", "#2e1a52", "#5a34a0", "#a07ae0", "#ecdcff"]],
	"thunder": [8, 1.6, ["#14120e", "#3a342a", "#6a6050", "#a89a82", "#e6dcc8"]],
}
## 범위 안에 세우는 작은 효과(꼬리 → [이름, 개수 배율]) — 빛 점 계열은 duskfall/heal-motes를 원소 색 계단으로 구운 것
const AREA_PROPS := {"fire": ["ground_fire", 1.0], "cold": ["ice_shard", 1.0], "heal": ["heal", 0.5], "radiant": ["motes_radiant", 0.6],
	"necrotic": ["motes_necrotic", 0.6], "poison": ["motes_poison", 0.6], "acid": ["motes_acid", 0.6], "arcane": ["motes_arcane", 0.35],
	"thunder": ["motes_thunder", 0.4]}
const FLOOR_SHADER := preload("res://scenes/battle/fx_floor.gdshader")
## 연출 박자(초): 근접 공격 동작에서 휘두른 팔이 내려오는 순간(body_templates attack_melee 0.18~0.32, 인형 doll_anims attack_slash·thrust·blunt·shove 0.26),
## 활 놓는 순간(attack_ranged 0.55), 주문 손을 든 순간(cast 0.3). 몬스터(한 장 그림)는 내딛기만 하고 바로.
const SWING_HIT := 0.26
const SHOT_RELEASE := 0.5
const CAST_RELEASE := 0.3
const MONSTER_HIT := 0.1
const BOLT_SPEED := 14.0  # 탄 속도(유닛/초)
const MAX_LONG := 2.6  # 한 번 효과가 이보다 길면 빨리 감는다(초)

var scene: Node
var _drawn := false
var _fx: Array = []  # 화면 글자
var _sp: Array = []  # 도트 효과 {node, name, t, speed, life, delay, follow, from, to, light}
var _status: Dictionary = {}  # 생물 → {조건 id: 효과 항목}
var _pending_bolt: Dictionary = {}  # 주문 탄: 공격 굴림(on_after_attack_roll)이 맞았을 때만 맞는 자리 효과 {caster, fam, fly}
var _text_delay := 0.0  # 빗나감 글자를 탄이 닿을 때 띄운다
var _fire: Dictionary = {}  # 칸 → Sprite3D
## 캡처용(battle_scene --shot): 0보다 크면 효과 시계를 프레임마다 이만큼만 넘긴다(느린 소프트웨어 그리기에서도 장면을 찍을 수 있게)
var fixed_dt := 0.0
var _shake := 0.0  # 화면 흔들림 남은 세기(유닛)
var _shake_t := 0.0
var _calls: Array = []  # 나중에 부를 것 [남은 초, Callable] — 효과 시계(fixed_dt 포함)로 센다


func _ready() -> void:
	z_index = 60
	EventBus.on_after_attack_roll.connect(_on_attack)
	EventBus.on_damage_taken.connect(_on_damage)
	EventBus.on_heal.connect(_on_heal)
	EventBus.on_spell_cast.connect(_on_spell)
	EventBus.on_condition_applied.connect(_on_cond_on)
	EventBus.on_condition_removed.connect(_on_cond_off)
	EventBus.on_hp_zero.connect(_on_down)


func _exit_tree() -> void:
	for pair: Array in [[EventBus.on_after_attack_roll, _on_attack], [EventBus.on_damage_taken, _on_damage],
			[EventBus.on_heal, _on_heal], [EventBus.on_spell_cast, _on_spell], [EventBus.on_condition_applied, _on_cond_on],
			[EventBus.on_condition_removed, _on_cond_off], [EventBus.on_hp_zero, _on_down]]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])


## 생물 몸 가운데(발에서 화면 50px 위 = 1.25단계)
func _pos(c: Variant) -> Vector3:
	if c is Node and scene.views.has(c):
		return scene.views[c].global_position + Vector3(0, 50.0 / V.STEP_PX, 0)
	return Vector3.ZERO


## 생물 발(효과 기준점 — pixelfx 효과는 발 자리를 기준으로 그려져 있다)
func _foot(c: Variant) -> Vector3:
	if c is Node and scene.views.has(c):
		return scene.views[c].global_position
	return Vector3.ZERO


## 공격자가 대상의 오른쪽에 있으면(화면 왼쪽으로 휘두름) 뒤집는다
func _faces_left(a: Node, t: Node) -> bool:
	return _foot(a).x > _foot(t).x + 0.05


func _cam_basis() -> Basis:
	var cam: Camera3D = scene.pixel.cam if scene.get("pixel") != null and scene.pixel != null and scene.pixel.cam != null else scene.camera
	return cam.global_transform.basis if cam != null else Basis.IDENTITY


## 화면 각도(라디안, 오른쪽 0·위 +): 세계 두 점을 카메라 오른쪽·위 축에 비춰서. 22.5° 단계로 끊는다(도트가 덜 깨지게).
func _screen_angle(a: Vector3, b: Vector3) -> float:
	var cb := _cam_basis()
	var d := b - a
	var ang := atan2(d.dot(cb.y), d.dot(cb.x))
	return roundf(ang / (PI / 8.0)) * (PI / 8.0)


## 효과 하나 띄우기. opts: scale·flip·delay·light(광원 꼬리)·power·radius(광원 반지름 칸)·aim_to(이 점을 향해 돌림)·tint·max_life
func _play(name: String, at: Vector3, opts: Dictionary = {}) -> Dictionary:
	if not PFX.has(name):
		return {}
	var o := opts.duplicate()
	o["cam_basis"] = _cam_basis()
	var ang := 0.0
	if opts.has("aim_to"):
		ang = _screen_angle(at, opts["aim_to"])
		# 오른쪽을 보는 효과: 왼쪽으로 쏘면 뒤집고 각도를 되돌려 위아래가 뒤집히지 않게
		if absf(ang) > PI / 2.0:
			o["flip"] = true
			ang = ang - PI if ang > 0.0 else ang + PI
	o["angle"] = ang if not o.get("flip", false) else -ang
	var node := PFX.make(name, o)
	if node == null:
		return {}
	if opts.get("depth", false):
		node.no_depth_test = false  # 바닥에 선 효과는 앞의 벽·나무·캐릭터에 가린다
	node.position = at
	node.visible = false
	if opts.has("tint"):
		node.modulate = opts["tint"]
	scene.add_child(node)
	var life := PFX.duration(name)
	var speed := maxf(1.0, life / MAX_LONG)
	if PFX.info(name).get("loop", false):
		life = float(opts.get("max_life", 1.4))
		speed = 1.0
	life = minf(life / speed, float(opts.get("max_life", 99.0)))
	var e := {"node": node, "name": name, "t": -float(opts.get("delay", 0.0)), "speed": speed, "life": life,
		"light": String(opts.get("light", "")), "power": float(opts.get("power", 0.0)), "radius": float(opts.get("radius", 2.5)), "at": at}
	_sp.append(e)
	return e


## delay초 뒤에 부른다(효과 시계로)
func _later(delay: float, f: Callable) -> void:
	if delay <= 0.0:
		f.call()
	else:
		_calls.append([delay, f])


## 짧은 멈칫(히트스톱): 게임 시간을 잠깐 거의 세운다(실제 시간 dur초). 캡처 중엔 하지 않는다.
func hitstop(dur: float) -> void:
	if fixed_dt > 0.0:
		return
	Engine.time_scale = 0.05
	get_tree().create_timer(dur, true, false, true).timeout.connect(func() -> void: Engine.time_scale = 1.0)


## 화면 흔들림(유닛). battle_scene._apply_camera가 shake_offset()을 더한다(도트 카메라는 그림 도트 격자에 맞춰 끊는다).
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)
	_shake_t = 0.22


func shake_offset() -> Vector3:
	if _shake_t <= 0.0:
		return Vector3.ZERO
	var k := _shake * _shake_t / 0.22
	return Vector3(randf_range(-1.0, 1.0) * k, 0.0, randf_range(-1.0, 1.0) * k)


## 날아가는 탄: a → b, 걸리는 시간(초)을 돌려준다
func _bolt(name: String, a: Vector3, b: Vector3, delay: float = 0.0) -> float:
	var dur := clampf(a.distance_to(b) / BOLT_SPEED, 0.15, 0.9)
	var e := _play(name, a, {"aim_to": b, "max_life": dur + delay, "delay": delay, "light": name.trim_prefix("bolt_") if name != "arrow" else "", "power": 0.5, "radius": 1.5})
	if not e.is_empty():
		e["life"] = dur  # 시계는 delay(음수)에서 시작해 0부터 dur까지 날아간다
	if not e.is_empty():
		e["from"] = a
		e["to"] = b
	return dur


func _on_attack(res: Dictionary) -> void:
	if res.get("preview", false) or not scene.views.has(res.get("attacker")) or not scene.views.has(res.get("target")):
		return
	var atk: Dictionary = res.get("attack", {})
	var a: Node = res["attacker"]
	var t: Node = res["target"]
	var hit: bool = res.get("hit", false)
	var fly := 0.0
	var rig: bool = scene.views[a].has_method("has_rig") and scene.views[a].has_rig()
	var melee := str(atk.get("kind", "melee")) != "ranged"
	if not atk.has("spell") or atk.get("weapon", false):
		fly = (SWING_HIT if melee else SHOT_RELEASE) if rig else MONSTER_HIT
		if not rig and melee:
			scene.views[a].nudge(_foot(t) - _foot(a), 0.28, 0.08, 0.2)  # 몬스터: 대상 쪽으로 내딛기
	if not atk.get("weapon", false) and atk.has("spell"):
		# 주문 공격: 탄은 on_spell_cast가 띄웠다 — 맞았을 때만 닿는 순간 터짐
		if _pending_bolt.get("caster") == a:
			fly = float(_pending_bolt["fly"])
			if hit:
				_play("hit_" + str(_pending_bolt["fam"]), _foot(t), {"delay": fly, "light": _pending_bolt["fam"], "power": 0.8})
			_pending_bolt = {}
	elif str(atk.get("kind", "melee")) == "ranged":
		fly += _bolt("arrow", _pos(a), _pos(t), fly)
		if hit:
			_play("hit", _foot(t), {"delay": fly, "light": "holy", "power": 0.5})
	else:
		var name := melee_style(atk, a)
		_play(name, _foot(t), {"flip": _faces_left(a, t), "tint": Color(1, 1, 1, 1.0 if hit else 0.45), "delay": fly})
	if hit:
		# 맞는 순간: 대상이 뒤로 밀렸다 돌아오고, 치명타는 짧게 멈칫(히트스톱) + 화면 흔들림
		scene.views[t].nudge(_foot(t) - _foot(a), 0.12 if not res.get("crit", false) else 0.2, 0.05, 0.2, fly)
		if res.get("crit", false):
			_later(fly, func() -> void: hitstop(0.09); shake(0.06))
	if res.get("crit", false):
		_play("crit", _foot(t), {"light": "holy", "power": 1.0, "delay": fly})
	_text_delay = fly  # 이어지는 피해 숫자도 탄이 닿을 때
	if not hit:
		_fx.append({"type": "text", "at": _pos(t), "text": "빗나감", "t": -fly, "life": 0.9, "col": Color(0.7, 0.7, 0.7)})


func _on_damage(info: Dictionary) -> void:
	var t: Variant = info.get("target")
	if not scene.views.has(t) or int(info.get("amount", 0)) <= 0:
		return
	var dtype := ""
	for t2: String in info.get("result", {}).get("by_type", {}):
		dtype = t2
	_fx.append({"type": "text", "at": _pos(t), "text": str(int(info["amount"])), "t": -_text_delay, "life": 1.0,
		"col": DMG_COL.get(dtype, Color(1.0, 0.85, 0.75)), "big": info.get("opts", {}).get("crit", false)})


func _on_heal(info: Dictionary) -> void:
	if scene.views.has(info.get("target")) and int(info.get("amount", 0)) > 0:
		_play("heal", _foot(info["target"]), {"light": "heal", "power": 0.5})
		_fx.append({"type": "text", "at": _pos(info["target"]), "text": "+%d" % int(info["amount"]), "t": 0.0, "life": 1.0, "col": Color(0.5, 0.95, 0.5)})


func _on_spell(ctx: Dictionary) -> void:
	var aim: Variant = ctx.get("aim")
	var sp := RulesDB.get_entry("spell", str(ctx.get("spell", "")))
	if sp.is_empty():
		return
	var caster: Node = ctx.get("caster")
	var g: Node = scene.world["grid"]
	var from := _pos(caster) if scene.views.has(caster) else Vector3.ZERO
	var at_c: Variant = g.creature_at(aim) if aim is Vector2i else null
	var to: Vector3 = (_pos(at_c) if scene.views.has(at_c) else V.top(g, aim) + Vector3(0, 0.6, 0)) if aim is Vector2i else from
	var foot: Vector3 = (_foot(at_c) if scene.views.has(at_c) else V.top(g, aim)) if aim is Vector2i else (_foot(caster) if scene.views.has(caster) else from)
	var d := spell_look(sp)
	var fam: String = d["family"]
	var rig: bool = scene.views.has(caster) and scene.views[caster].has_method("has_rig") and scene.views[caster].has_rig()
	var cd := CAST_RELEASE if rig else 0.1  # 손을 든 순간에 나간다
	if str(d["kind"]) != "bolt":
		_later(cd, func() -> void: _spell_fx(ctx, sp, d, from, to, foot))
		return
	var fly := _bolt("bolt_" + ("acid" if fam == "poison" else fam), from, to, cd)
	_pending_bolt = {"caster": caster, "fam": fam, "fly": cd + fly}


func _spell_fx(ctx: Dictionary, sp: Dictionary, d: Dictionary, _from: Vector3, to: Vector3, foot: Vector3) -> void:
	var aim: Variant = ctx.get("aim")
	var caster: Node = ctx.get("caster")
	var g: Node = scene.world["grid"]
	var fam: String = d["family"]
	var area: Dictionary = sp.get("area") if sp.get("area") is Dictionary else {}
	var shape := str(area.get("shape", ""))
	var r := float(area.get("radius_tiles", area.get("size_tiles", area.get("length_tiles", 1))))
	var big := 2.0 if r >= 4.0 else 1.0  # 큰 범위(4칸↑)만 효과 2배(도트 2×2)
	match str(d["kind"]):
		"area":
			var name := "area_" + fam
			if not PFX.has(name):
				name = "hit_" + fam
			var center: Vector3 = V.top(g, aim) if aim is Vector2i else foot
			if shape == "emanation" or str(sp.get("range", {}).get("type", "")) == "self":
				center = _foot(caster) if scene.views.has(caster) else center
			if FLOOR_STYLE.has(fam):
				area_burst(fam, center, r + 0.5)
				if r >= 3.0:
					shake(0.04 + 0.01 * r)
			else:
				_play(name, center, {"scale": big, "light": fam, "power": 1.2, "radius": maxf(r + 1.0, 2.0)})
		"cone", "line":
			# 규칙 범위 그대로(Area.cov_cone·cov_line): 시작 칸 가운데에서 조준 칸 쪽으로 길이 N + 0.5칸
			if scene.views.has(caster) and aim is Vector2i:
				var o := V.pos(g.cell_of(caster), 0.0)
				o.y = _foot(caster).y
				var tgt := V.pos(aim, 0.0)
				var dv := Vector2(tgt.x - o.x, tgt.z - o.z)
				if dv.length() < 0.01:
					dv = Vector2.RIGHT
				var fam2: String = fam if FLOOR_STYLE.has(fam) else "arcane"
				area_burst(fam2, o, float(area.get("length_tiles", r)) + 0.5, 1 if d["kind"] == "cone" else 2, dv.normalized(), float(area.get("width_tiles", 1)) * 0.5)
			else:
				_play("hit_" + fam, foot, {"light": fam, "power": 0.9})
		"hit":
			_play("hit_" + fam, foot, {"light": fam, "power": 0.8})
		"heal_area":
			area_burst("heal", _foot(caster) if shape == "emanation" and scene.views.has(caster) else V.top(g, aim) if aim is Vector2i else foot, r + 0.5)
		"heal":
			pass  # 한 대상 회복은 on_heal이 꽃을 띄운다(물약·기능 회복과 같이)
		"shield", "buff", "hex", "charm":
			_play(str(d["kind"]), foot, {"light": "holy" if d["kind"] in ["shield", "buff"] else "arcane", "power": 0.5, "max_life": 1.6})


## 주문 → 효과 모양·종류: {kind: bolt/area/cone/line/hit/heal/heal_area/shield/buff/hex/charm, family: 피해 꼬리}
## 근접 공격 모양(무기 자국·캐릭터 동작이 같이 쓴다): 피해 종류로 베기 slash·찌르기 thrust·둔기 blunt, 몬스터(종족 없음) 베기 = 발톱 claw
static func melee_style(atk: Dictionary, attacker: Object) -> String:
	var dmg: Array = atk.get("damage", [])
	var dt := str((dmg[0] as Dictionary).get("damage_type", "slashing")) if not dmg.is_empty() and dmg[0] is Dictionary else "slashing"
	if dt == "piercing":
		return "thrust"
	if dt == "bludgeoning":
		return "blunt"
	if attacker != null and str(attacker.get("species_id")) == "":
		return "claw"
	return "slash"


static func spell_look(sp: Dictionary) -> Dictionary:
	var dtype := ""
	var heal := false
	var stack: Array = [sp.get("effects", {})]
	while not stack.is_empty():
		var e: Variant = stack.pop_back()
		if e is Dictionary:
			if (e as Dictionary).has("damage_type") and dtype == "":
				dtype = str(e["damage_type"])
			if str((e as Dictionary).get("type", "")) == "heal":
				heal = true
			for v: Variant in (e as Dictionary).values():
				stack.append(v)
		elif e is Array:
			stack.append_array(e)
	var fam: String = FAMILY.get(dtype, "arcane")
	var check := str(sp.get("effects", {}).get("check", {}).get("type", "")) if sp.get("effects") is Dictionary else ""
	var area: Dictionary = sp.get("area") if sp.get("area") is Dictionary else {}
	var shape := str(area.get("shape", ""))
	if dtype != "":
		if check == "attack":
			return {"kind": "bolt", "family": fam}
		if shape == "cone":
			return {"kind": "cone", "family": fam}
		if shape == "line":
			return {"kind": "line", "family": fam}
		if shape != "":
			return {"kind": "area", "family": fam}
		return {"kind": "hit", "family": fam}
	if heal:
		return {"kind": "heal_area" if shape != "" else "heal", "family": "heal"}
	if shape == "cone" or shape == "line":
		# 피해 없는 원뿔·선(색 분사·공포): 학파로 색
		return {"kind": shape, "family": "necrotic" if str(sp.get("school", "")) == "necromancy" else "arcane"}
	if check == "save":
		return {"kind": "hex" if str(sp.get("school", "")) in ["necromancy", "enchantment"] else "charm", "family": "arcane"}
	return {"kind": "shield" if str(sp.get("school", "")) == "abjuration" else "buff", "family": "holy"}


func _on_cond_on(c: Object, id: String) -> void:
	if not STATUS_FX.has(id) or not scene.views.has(c):
		return
	var st: Dictionary = _status.get(c, {})
	if st.has(id):
		return
	var pair: Array = STATUS_FX[id]
	var e := _play(pair[0], _foot(c), {"max_life": 1e9, "light": "fire" if id == "burning" else "", "power": 0.35, "radius": 1.2})
	if e.is_empty():
		return
	e["follow"] = c
	e["head"] = pair[1]
	st[id] = e
	_status[c] = st


func _on_cond_off(c: Object, id: String) -> void:
	var st: Dictionary = _status.get(c, {})
	if st.has(id):
		st[id]["life"] = 0.0  # 다음 프레임에 지운다
		st.erase(id)


func _on_down(info: Dictionary) -> void:
	var c: Variant = info.get("creature")
	if scene.views.has(c) and str(c.get("species_id")) == "":
		_play("death", _foot(c), {"delay": 0.15})


## 불 표면 칸마다 불꽃(도트 효과 ground_fire 고리 — tools/pixelfx/src/fx/fire/ground-flames.js, 이 게임용으로 만든 효과 — 칸마다 자리·박자 다르게). 맵이 바뀔 때 부른다.
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
		if _fire.has(c) or not PFX.has("ground_fire"):
			continue
		var p := V.pos(c, g.height(c))
		var h := float(posmod(c.x * 73 + c.y * 151, 100)) / 100.0
		p.x += (h - 0.5) * 0.4
		p.y = scene.map_view.ground_at(Vector2(p.x, p.z))
		var node := PFX.make("ground_fire", {"cam_basis": _cam_basis(), "flip": h > 0.5})
		node.position = p
		node.set_meta("phase", h * 3.0)
		scene.add_child(node)
		_fire[c] = node


func _process(delta: float) -> void:
	_text_delay = 0.0  # 한 판정 묶음(같은 프레임) 안에서만 쓴다
	if fixed_dt > 0.0:
		delta = fixed_dt
	if _shake_t > 0.0:
		_shake_t -= delta
	var due: Array = []
	for c: Array in _calls:
		c[0] -= delta
		if c[0] <= 0.0:
			due.append(c)
	for c: Array in due:
		_calls.erase(c)
		(c[1] as Callable).call()
	_step_sprites(delta)
	if _fx.is_empty():
		if _drawn:
			_drawn = false
			queue_redraw()
		return
	_drawn = true
	for f: Dictionary in _fx:
		f["t"] += delta
	_fx = _fx.filter(func(f: Dictionary) -> bool: return f["t"] < f["life"])
	queue_redraw()


func _step_sprites(delta: float) -> void:
	var lights: Array = []
	var keep: Array = []
	for e: Dictionary in _sp:
		var node: Node3D = e["node"]
		if not is_instance_valid(node):
			continue
		e["t"] += delta
		var t: float = e["t"]
		if t >= float(e["life"]):
			node.queue_free()
			continue
		keep.append(e)
		if t < 0.0:
			continue
		if e.has("floor"):
			(e["floor"] as ShaderMaterial).set_shader_parameter("t", t / float(e["life"]))
		elif node is Sprite3D:
			var spr := node as Sprite3D
			var f := PFX.frame_at(e["name"], t * float(e["speed"]))
			if f < 0:
				spr.visible = false
				continue
			spr.visible = true
			spr.frame = mini(f, spr.hframes * spr.vframes - 1)
		if e.has("from"):
			node.position = (e["from"] as Vector3).lerp(e["to"], clampf(t / maxf(float(e["life"]), 0.01), 0.0, 1.0))
		if e.has("follow"):
			var c: Variant = e["follow"]
			if not is_instance_valid(c) or not scene.views.has(c) or c.get("dead"):
				e["life"] = 0.0
			else:
				node.position = _foot(c) + (Vector3(0, 1.55, 0) if e.get("head", false) else Vector3.ZERO)
		if e["light"] != "" and float(e["power"]) > 0.0:
			# 터지는 순간 밝고 빠르게 사그라든다(고리 효과는 일렁이며 약하게 계속)
			var k: float = float(e["power"]) * (0.7 + 0.3 * sin(t * 9.0) if float(e["life"]) > 100.0 else exp(-t * 2.2))
			lights.append([node.position, float(e["radius"]), FX_LIGHT.get(e["light"], Color.WHITE), k])
	_sp = keep
	for c: Vector2i in _fire:
		var n: Sprite3D = _fire[c]
		if is_instance_valid(n):
			n.frame = PFX.frame_at("ground_fire", Time.get_ticks_msec() / 1000.0 + float(n.get_meta("phase", 0.0)))
	if scene.get("pixel") != null and scene.pixel != null:
		lights.sort_custom(func(a: Array, b: Array) -> bool: return float(a[3]) > float(b[3]))
		scene.pixel.set_dyn_lights(lights.slice(0, 8))


func _draw() -> void:
	var font := S.title_font()
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# 확대에 맞춰 크기도 옛 2D처럼(그림 1px = 화면 z px)
	var z: float = get_viewport().get_visible_rect().size.y / (cam.size * V.T)
	for f: Dictionary in _fx:
		if f["t"] < 0.0:
			continue  # 아직(탄이 닿기 전)
		var k: float = f["t"] / f["life"]
		var col: Color = f["col"]
		var sp := {}
		for key: String in ["a", "b", "at"]:
			if f.has(key):
				sp[key] = cam.unproject_position(f[key])
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		match f["type"]:
			"text":
				var size := 26 if f.get("big", false) else 20
				draw_set_transform(sp["at"], 0, Vector2(z, z))
				# 너비를 글자에 맞춘다(고정 너비면 '빗나감'이 '빗나'로 잘렸다)
				var w := font.get_string_size(f["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
				var at := Vector2(-w / 2.0, -30 * k)
				draw_string_outline(font, at, f["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color(0, 0, 0, 1.0 - k))
				draw_string(font, at, f["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(col, 1.0 - k * 0.8))


## 범위 효과(우리 구도): 바닥 판(카메라 각도 타원, 반지름 rad 유닛 = 규칙 범위 N + 0.5칸) + 원 안·둘레에 세운 효과.
##   불 = 퍼지는 불 고리 → 그을린 바닥 + 고리가 닿는 자리마다 낮은 불꽃(ground_fire), 가운데 작은 폭발
##   냉기 = 퍼지는 서리 고리 → 얼음 금 서리 + 둘레·안쪽에 솟았다 부서지는 얼음 조각(ice_shard)
##   회복 = 천천히 번지는 빛 고리 + 안쪽 점선 원 + 군데군데 꽃(heal)
func area_burst(fam: String, center: Vector3, rad: float, shape: int = 0, dir := Vector2.RIGHT, half_w := 0.5) -> void:
	var st: Array = FLOOR_STYLE[fam]
	var life: float = st[1]
	_floor(center, rad, int(st[0]), life, st[2], shape, dir, half_w)
	var area_k := rad * rad if shape == 0 else (rad * rad * tan(Area.CONE_HALF) if shape == 1 else rad * half_w * 2.0)
	var n := clampi(int(area_k * 1.1), 3, 26)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(center.x * 73.0 + center.z * 151.0)
	var spread: float = {"fire": 0.32, "cold": 0.4, "lightning": 0.1, "thunder": 0.3}.get(fam, 0.55)
	for i in n:
		# 원 안에 고르게(가운데는 덜) — 고리가 그 자리에 닿을 때 솟는다
		var u := sqrt(rng.randf_range(0.08, 1.0)) * 0.88
		if fam == "cold" and i % 2 == 0 and shape == 0:
			u = rng.randf_range(0.82, 0.95)  # 냉기는 반은 둘레에 줄지어
		var ang := rng.randf() * TAU
		var p := center + Vector3(cos(ang) * u * rad, 0, sin(ang) * u * rad)
		if shape != 0:
			# 원뿔·선 안: 앞쪽 거리(시작 칸 다음부터) × 옆 거리
			u = rng.randf_range(0.6 / rad, 0.95)
			var side := rng.randf_range(-0.85, 0.85) * (tan(Area.CONE_HALF) * u * rad if shape == 1 else half_w)
			var fw := Vector3(dir.x, 0, dir.y)
			p = center + fw * (u * rad) + Vector3(-dir.y, 0, dir.x) * side
		p.y = scene.map_view.ground_at(Vector2(p.x, p.z)) if scene.get("map_view") != null else center.y
		var delay := u * spread * life * (0.9 + rng.randf() * 0.2)
		var prop: Array = AREA_PROPS.get(fam, [])
		if prop.is_empty() or float(i) >= float(n) * float(prop[1]):
			continue
		var o := {"delay": delay, "flip": rng.randf() < 0.5, "depth": true}
		if fam == "fire":
			o["max_life"] = life * 0.7 - delay
		_play(String(prop[0]), p, o)
	if shape != 0:
		# 원뿔·선: 가운데 터짐 대신 앞으로 번지는 광원 하나(범위 가운데쯤)
		var mid := center + Vector3(dir.x, 0, dir.y) * rad * 0.5
		_dyn_only(mid, fam, 1.0, rad * 0.6, life * 0.6)
		return
	match fam:
		"fire":
			_play("hit_fire", center, {"light": "fire", "power": 1.3, "radius": rad + 1.0})
		"cold":
			_play("ice_shard", center, {"light": "cold", "power": 1.0, "radius": rad + 0.5, "depth": true})
		"lightning":
			_play("area_lightning", center, {"light": "lightning", "power": 1.4, "radius": rad + 1.0})
		_:
			_dyn_only(center, fam, 0.9, rad + 0.5, life * 0.6)


## 바닥 판 하나(fx_floor.gdshader). 진행 t는 _step_sprites가 넘긴다.
func _floor(center: Vector3, rad: float, style: int, life: float, ramp: Array, shape: int = 0, dir := Vector2.RIGHT, half_w := 0.5) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(rad * 2.0 + 0.4, rad * 2.0 + 0.4)  # 원뿔·선도 시작점 둘레 정사각(밖은 셰이더가 버린다)
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = FLOOR_SHADER
	var cols := PackedVector3Array()
	for h: String in ramp:
		var c := Color(h)
		cols.append(Vector3(c.r, c.g, c.b))
	m.set_shader_parameter("ramp", cols)
	m.set_shader_parameter("center", center)
	m.set_shader_parameter("radius", rad)
	m.set_shader_parameter("style", style)
	m.set_shader_parameter("shape", shape)
	m.set_shader_parameter("dir", dir)
	m.set_shader_parameter("half_ang", Area.CONE_HALF)
	m.set_shader_parameter("half_w", half_w)
	m.set_shader_parameter("seed", fmod(center.x * 3.7 + center.z * 1.3, 97.0))
	m.render_priority = 127
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = center + Vector3(0, 0.03, 0)
	scene.add_child(mi)
	_sp.append({"node": mi, "name": "", "floor": m, "t": 0.0, "speed": 1.0, "life": life, "light": "", "power": 0.0, "radius": rad, "at": center})


## 그림 없이 광원만(회복 범위 등)
func _dyn_only(at: Vector3, light: String, power: float, rad: float, life: float) -> void:
	var holder := Node3D.new()
	holder.position = at
	scene.add_child(holder)
	_sp.append({"node": holder, "name": "", "t": 0.0, "speed": 1.0, "life": life, "light": light, "power": power, "radius": rad, "at": at})


## 캡처용 맛보기: 이름마다 기준 생물 오른쪽으로 2칸씩 늘어놓는다(bolt_·arrow·cone_·line_은 오른쪽 6칸을 향해)
func demo(names: Array, who: Node) -> void:
	if not scene.views.has(who):
		return
	var base := _foot(who)
	for i in names.size():
		var n := String(names[i])
		var at := base + Vector3(2.0 * float(i + 1), 0, 0)
		if n.begins_with("cone:") or n.begins_with("line:"):
			var o := V.pos(scene.world["grid"].cell_of(who), 0.0)
			o.y = base.y
			var dz := float(n.get_slice(":", 3)) if n.get_slice_count(":") >= 4 else 0.0
			area_burst(n.get_slice(":", 1), o, float(n.get_slice(":", 2)) + 0.5, 1 if n.begins_with("cone:") else 2, Vector2(1.0, dz).normalized())
		elif n.begins_with("area:"):
			var off := Vector3(float(n.get_slice(":", 3)), 0, float(n.get_slice(":", 4))) if n.get_slice_count(":") >= 5 else Vector3(float(n.get_slice(":", 2)), 0, 0)
			area_burst(n.get_slice(":", 1), base + off, float(n.get_slice(":", 2)) + 0.5)
		elif n.begins_with("bolt_") or n == "arrow":
			var e := _play(n, at + Vector3(0, 0.8, 0), {"aim_to": at + Vector3(6, 0.8, 0), "max_life": 3.0, "light": n.trim_prefix("bolt_"), "power": 0.6})
			if not e.is_empty():
				e["from"] = at + Vector3(0, 0.8, 0)
				e["to"] = at + Vector3(1.5, 0.8, 0)
		elif n.begins_with("cone_") or n.begins_with("line_"):
			_play(n, at + Vector3(0, 0.8, 0), {"aim_to": at + Vector3(6, 0.8, 0), "light": n.get_slice("_", 1), "power": 1.0, "radius": 3.0})
		else:
			_play(n, at, {"light": n.get_slice("_", 1) if "_" in n else "holy", "power": 1.0, "radius": 2.5})

