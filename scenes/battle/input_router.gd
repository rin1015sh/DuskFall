extends RefCounted
## 입력 상태기계 하나(CLAUDE.md '미리보기 → 확정'). 마우스와 터치를 같은 의미 신호로 바꾼다.
##  마우스: 올리기 = 미리보기, 왼쪽 클릭 = 실행, 휠 = 확대, 오른쪽·가운데 끌기 = 화면 이동.
##  터치: 첫 탭 = 미리보기, 같은 칸 두 번째 탭 = 실행, 길게 누르기 = 정보, 한 손가락 끌기 = 화면 이동,
##        두 손가락 = 확대(핀치).
## 이 파일은 칸 좌표를 cell_at(화면 점) 콜백으로만 안다.

signal preview(pos: Vector2)
signal confirm(pos: Vector2)
signal info(pos: Vector2)
signal pan(delta: Vector2)
signal zoom(factor: float, at: Vector2)
## 우클릭(끌지 않고 뗌) = 고르던 행동 취소(BG3)
signal cancel()

const DRAG_THRESHOLD := 12.0
const LONG_PRESS_MS := 500
const WHEEL_STEP := 1.1

enum State { IDLE, MOUSE_DOWN, MOUSE_PAN, TOUCH_DOWN, TOUCH_PAN, PINCH, LONG_PRESSED }

var state := State.IDLE
var cell_at: Callable
## 마지막으로 미리보기한 칸(터치 두 번째 탭 판정)
var previewed_cell := Vector2i(-1, -1)

var _press_pos := Vector2.ZERO
var _right_dragged := false
var _press_ms := 0
var _touches := {}  # index → 위치
var _pinch_dist := 0.0


func handle(event: InputEvent, now_ms: int) -> void:
	if event is InputEventMouseMotion:
		_mouse_motion(event)
	elif event is InputEventMouseButton:
		_mouse_button(event)
	elif event is InputEventScreenTouch:
		_touch(event, now_ms)
	elif event is InputEventScreenDrag:
		_drag(event)
	elif event is InputEventMagnifyGesture:
		zoom.emit(event.factor, event.position)
	elif event is InputEventPanGesture:
		pan.emit(-event.delta * 20.0)


## 시간 흐름(길게 누르기 판정). 매 프레임 부른다.
func update(now_ms: int) -> void:
	if state == State.TOUCH_DOWN and now_ms - _press_ms >= LONG_PRESS_MS:
		state = State.LONG_PRESSED
		info.emit(_press_pos)


func _show(pos: Vector2) -> void:
	previewed_cell = cell_at.call(pos) if cell_at.is_valid() else Vector2i(-1, -1)
	preview.emit(pos)


# ---------- 마우스 ----------

func _mouse_motion(e: InputEventMouseMotion) -> void:
	match state:
		State.MOUSE_PAN:
			pan.emit(e.relative)
			if e.relative.length() > 1.0:
				_right_dragged = true
		State.IDLE:
			_show(e.position)


func _mouse_button(e: InputEventMouseButton) -> void:
	match e.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if e.pressed:
				zoom.emit(WHEEL_STEP, e.position)
		MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed:
				zoom.emit(1.0 / WHEEL_STEP, e.position)
		MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
			if e.pressed:
				_right_dragged = false
			elif e.button_index == MOUSE_BUTTON_RIGHT and not _right_dragged:
				cancel.emit()
			state = State.MOUSE_PAN if e.pressed else State.IDLE
		MOUSE_BUTTON_LEFT:
			if e.pressed:
				state = State.MOUSE_DOWN
				_press_pos = e.position
			elif state == State.MOUSE_DOWN:
				state = State.IDLE
				var cell: Variant = cell_at.call(e.position) if cell_at.is_valid() else null
				if cell != previewed_cell:
					_show(e.position)
				confirm.emit(e.position)


# ---------- 터치 ----------

func _touch(e: InputEventScreenTouch, now_ms: int) -> void:
	if e.pressed:
		_touches[e.index] = e.position
		if _touches.size() == 1:
			state = State.TOUCH_DOWN
			_press_pos = e.position
			_press_ms = now_ms
		elif _touches.size() == 2:
			state = State.PINCH
			_pinch_dist = _touch_distance()
		return
	_touches.erase(e.index)
	if state == State.TOUCH_DOWN and _touches.is_empty():
		var cell: Variant = cell_at.call(e.position) if cell_at.is_valid() else null
		if cell != null and cell == previewed_cell:
			confirm.emit(e.position)  # 같은 곳 두 번째 탭 = 실행
		else:
			_show(e.position)  # 첫 탭 = 미리보기
	if _touches.is_empty():
		state = State.IDLE


func _drag(e: InputEventScreenDrag) -> void:
	_touches[e.index] = e.position
	match state:
		State.TOUCH_DOWN:
			if e.position.distance_to(_press_pos) > DRAG_THRESHOLD:
				state = State.TOUCH_PAN
				pan.emit(e.position - _press_pos)
		State.TOUCH_PAN:
			pan.emit(e.relative)
		State.PINCH:
			var d := _touch_distance()
			if _pinch_dist > 0.0 and d > 0.0:
				zoom.emit(d / _pinch_dist, _touch_center())
			_pinch_dist = d


func _touch_distance() -> float:
	var p: Array = _touches.values()
	return (p[0] as Vector2).distance_to(p[1]) if p.size() >= 2 else 0.0


func _touch_center() -> Vector2:
	var p: Array = _touches.values()
	return ((p[0] as Vector2) + (p[1] as Vector2)) / 2.0 if p.size() >= 2 else Vector2.ZERO
