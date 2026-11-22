extends SceneTree
## 아이콘 견본 한 장(행동·주문 아이콘 확인용): xvfb-run -a godot --rendering-driver opengl3 --path . -s res://tools/icon_sheet.gd -- --out=<png>

var _f := 0
var _out := ""


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	root.size = Vector2i(1280, 860)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.035)
	bg.size = Vector2(1280, 860)
	root.add_child(bg)
	var Icons: Variant = load("res://scenes/ui/action_icons.gd")
	var keys: Array = Icons.ACTIONS.keys()
	for sid: String in Icons.SPELLS.keys():
		keys.append("spell:" + sid)
	var x := 0
	var y := 0
	for k: String in keys:
		var ic: Control = Icons.new()
		ic.kind = k
		ic.position = Vector2(10 + x * 50, 10 + y * 50)
		ic.size = Vector2(46, 46)
		root.add_child(ic)
		x += 1
		if x >= 25:
			x = 0
			y += 1


func _process(_d: float) -> bool:
	_f += 1
	if _f == 5:
		root.get_texture().get_image().save_png(_out)
		return true
	return false
