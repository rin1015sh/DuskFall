extends RefCounted
## 컷아웃 초상(표현 계층): 생물마다 앞모습(앞쪽 대각선, 서 있기)을 숨은 SubViewport에 그려 둔다.
## 초상·소지품 창 전신(ui_style.portrait_tex)이 이 그림을 잘라 쓴다. 모습(장비)이 바뀌면 다시 입힌다.

const Cutout := preload("res://scripts/rules/cutout.gd")
const Rig := preload("res://scenes/battle/cutout_rig.gd")
const HOLDER := "CutoutPortraits"
static var _holder: Node


static func texture_for(c: Node) -> Texture2D:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	if _holder == null or not is_instance_valid(_holder):
		_holder = Node.new()
		_holder.name = HOLDER
		tree.root.add_child.call_deferred(_holder)  # 장면 준비 중에도 붙일 수 있게 다음 프레임에
	var holder: Node = _holder
	for ch in holder.get_children():
		if not is_instance_valid(ch.get_meta("creature", null)):
			ch.queue_free()  # 사라진 생물의 그림은 치운다
	var key := "c%d" % c.get_instance_id()
	var vp: SubViewport = holder.get_node_or_null(key)
	if vp == null:
		vp = SubViewport.new()
		vp.name = key
		vp.set_meta("creature", c)
		vp.transparent_bg = true
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var lk := Cutout.look(c)
		var canvas: Array = Cutout.template(str(lk["template"])).get("canvas", [160, 240])
		vp.size = Vector2i(int(canvas[0]), int(canvas[1]))
		var rig := Rig.new()
		rig.name = "rig"
		vp.add_child(rig)
		holder.add_child(vp)
	var r: Node = vp.get_node("rig")
	r.apply_look(Cutout.look(c))
	r.set_facing(0)
	r.play("idle")
	return vp.get_texture()
