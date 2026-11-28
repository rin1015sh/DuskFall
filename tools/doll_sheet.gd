extends Node
## 간이 3D 인형 확인 시트(그림만): 4방향 × 동작 장면을 한 장 PNG로(창 화소 그대로 × 배율).
##   xvfb-run godot --path . --rendering-driver opengl3 res://tools/doll_sheet.tscn -- --out=<png> [--species=human] [--anim=idle,walk] [--frames=6] [--scale=4]

const Doll := preload("res://scenes/battle/doll_rig.gd")
const Cutout := preload("res://scripts/rules/cutout.gd")


func _ready() -> void:
	_run.call_deferred()


func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + k + "="):
			return a.substr(k.length() + 3)
	return d


func _run() -> void:
	await get_tree().process_frame
	var sp := Cutout.species_look(_arg("species", "human"))
	var lk := {"template": str(sp.get("template", "medium")), "skin": str(sp.get("skin")), "hair": str(sp.get("hair")),
		"extras": Array(sp.get("extras", []))}
	lk["key"] = JSON.stringify(lk)
	var anims := _arg("anim", "idle,walk").split(",")
	var nf := int(_arg("frames", "6"))
	var sc := int(_arg("scale", "4"))
	var vps: Array = []
	var dolls: Array = []
	for ai in anims.size():
		for f in 4:
			for i in nf:
				var vp := SubViewport.new()
				vp.transparent_bg = true
				vp.own_world_3d = true
				vp.msaa_3d = Viewport.MSAA_DISABLED
				vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
				add_child(vp)
				var d := Doll.new()
				d.dot = Doll.BASE_DOT
				vp.add_child(d)
				d.apply_look(lk)
				vp.size = d.canvas_px()
				d.set_facing([0, 2, 3, 1][f])
				d.set_process(false)
				var length := float(d.tpl.get("animations", {}).get(anims[ai], {}).get("length", 0.8))
				d.anim = anims[ai]
				d.pose(anims[ai], length * float(i) / float(nf))
				vps.append([vp, ai, f, i])
				dolls.append(d)
	for k in 4:
		await get_tree().process_frame
	var cw: int = vps[0][0].size.x
	var ch: int = vps[0][0].size.y
	var cols := 4 * nf
	var img := Image.create(cw * cols, ch * anims.size(), false, Image.FORMAT_RGBA8)
	img.fill(Color(0.17, 0.17, 0.26))
	for e: Array in vps:
		var im: Image = e[0].get_texture().get_image()
		im.convert(Image.FORMAT_RGBA8)
		var x: int = (int(e[2]) * nf + int(e[3])) * cw
		img.blend_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(x, int(e[1]) * ch))
	img.resize(img.get_width() * sc, img.get_height() * sc, Image.INTERPOLATE_NEAREST)
	img.save_png(_arg("out", "user://doll_sheet.png"))
	get_tree().quit()
