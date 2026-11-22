extends Node
## 주사위(오토로드). 룰북 8단계 'Godot 구조', 2단계 공통 처리 규칙 5(로그).
## 시드를 고정한 난수를 쓰고 모든 굴림을 roll_log에 남긴다.
## 테스트는 force()로 다음에 나올 눈을 정할 수 있다.

const DiceExpr := preload("res://scripts/rules/dice_expr.gd")

var _rng := RandomNumberGenerator.new()
var _forced: Array[int] = []
## 굴림 기록. 항목: {"kind": "d20"|"dice"|"text", "reason", "rolls", "total", "text"}
var roll_log: Array[Dictionary] = []


func _init() -> void:
	_rng.seed = 1


## 시드를 정하고 로그와 강제 눈을 비운다.
func set_seed(value: int) -> void:
	_rng.seed = value
	roll_log.clear()
	_forced.clear()


## 난수 상태(저장·불러오기). 같은 상태로 돌리면 다음 굴림이 같다(9단계 '불러오기로 다시 굴리기' 옵션).
func get_state() -> int:
	return _rng.state


func set_state(value: int) -> void:
	_rng.state = value


## 다음에 굴릴 주사위 눈을 차례로 정한다(테스트용). d20과 피해 주사위 모두 이 순서대로 쓴다.
func force(values: Array) -> void:
	for v: int in values:
		_forced.append(v)


func clear_forced() -> void:
	_forced.clear()


func forced_left() -> int:
	return _forced.size()


func die(sides: int) -> int:
	if not _forced.is_empty():
		var v: int = _forced.pop_front()
		assert(v >= 1 and v <= sides, "강제 눈 %d가 d%d 범위 밖" % [v, sides])
		return clampi(v, 1, sides)
	return _rng.randi_range(1, sides)


## d20 테스트 한 번. mode: 1 유리, -1 불리, 0 보통. 유리·불리면 두 개를 굴려 고른다.
## 결과: {"rolls": [..], "natural": int, "mode": int}
func d20(mode: int, reason: String = "") -> Dictionary:
	var rolls: Array[int] = [die(20)]
	if mode != 0:
		rolls.append(die(20))
	var natural: int = rolls.max() if mode > 0 else rolls.min()
	var res := {"rolls": rolls, "natural": natural, "mode": mode}
	roll_log.append({"kind": "d20", "reason": reason, "rolls": rolls, "total": natural,
		"text": "d20%s %s → %d" % [_mode_text(mode), str(rolls), natural]})
	return res


## 식을 굴린다. crit이면 주사위만 2배. min_face > 0이면 그보다 작은 눈을 그 값으로(대형 무기 전투).
## 결과: {"expr", "rolls", "flat", "total"}
func roll(expr: String, reason: String = "", crit: bool = false, min_face: int = 0) -> Dictionary:
	var p := DiceExpr.parse(expr)
	assert(not p.is_empty(), "주사위 식을 읽을 수 없다: %s" % expr)
	if p.is_empty():
		return {"expr": expr, "rolls": [], "flat": 0, "total": 0}
	var rolls: Array[int] = []
	var total: int = p["flat"]
	for d: Dictionary in p["dice"]:
		for i in d["count"] * (2 if crit else 1):
			var v := die(d["sides"])
			if min_face > 0 and v < min_face and d["sign"] > 0:
				v = min_face
			rolls.append(v * d["sign"])
			total += v * d["sign"]
	var res := {"expr": expr, "rolls": rolls, "flat": p["flat"], "total": total}
	roll_log.append({"kind": "dice", "reason": reason, "rolls": rolls, "total": total,
		"text": "%s%s %s = %d" % [expr, " (치명타)" if crit else "", str(rolls), total]})
	return res


## 판정 요약 한 줄을 남긴다("주사위 + 수정치 = 합계 vs DC" 형식).
func log_text(text: String, reason: String = "") -> void:
	roll_log.append({"kind": "text", "reason": reason, "rolls": [], "total": 0, "text": text})


func _mode_text(mode: int) -> String:
	if mode > 0:
		return "(유리)"
	if mode < 0:
		return "(불리)"
	return ""
