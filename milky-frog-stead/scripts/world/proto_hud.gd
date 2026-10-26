extends Label
## 原型 HUD：显示烘焙耗时、区块、当前位置的材质，并接管几个调试按键。

@export var field_path: NodePath

var _field: TerrainField
var _t := 0.0


func _ready() -> void:
	_field = get_node_or_null(field_path) as TerrainField
	# 开发用：godot ... scene -- --shot out.png [jump_x jump_y]
	#   → 截一张、平移、再截一张（验证世界锚定），然后退出
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0] == "--shot":
		var jump := Vector2(38, 22)
		if args.size() >= 4:
			jump = Vector2(float(args[2]), float(args[3]))
		_capture(args[1], jump)


func _capture(path: String, jump: Vector2) -> void:
	var canvas := _field.get_node_or_null("../WaterCanvas") as MeshInstance2D
	var mat: ShaderMaterial = null
	if canvas:
		mat = canvas.material as ShaderMaterial
	# 冻结水面动画，这样两张图可以逐像素对比（验证世界锚定）；
	# --anim 则相反：开着动画截两张，用来验证"水在动、地不动"
	var anim := "--anim" in OS.get_cmdline_user_args()
	if mat:
		mat.set_shader_parameter("anim_speed", 1.0 if anim else 0.0)
	# --tiles：顺手验证一下「分类 → 写瓦片」那条路（关掉底图，只留瓦片 + 水）
	if "--tiles" in OS.get_cmdline_user_args():
		_field.toggle_tiles()
		if mat:
			mat.set_shader_parameter("ground_mix", 0.0)
	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	_field.save_mask_debug(path.replace(".png", "_mask.png"))
	print("[shot] ", path, "  ", img.get_size(), "  fps=", Engine.get_frames_per_second(),
			"  bake=", _field.bake_ms)

	# 平移一段再截一张：小位移（不跨区块）两张图应该只差整体平移；
	# 大位移会触发跨区块重烤，可以顺便看烘焙耗时和新区域有没有接缝。
	var p := _field.get_parent().get_node_or_null("Player") as Node2D
	if anim:
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(path.replace(".png", "_b.png"))
		print("[shot] animated second frame")
	elif p:
		p.global_position += jump
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		var img2 := get_viewport().get_texture().get_image()
		img2.save_png(path.replace(".png", "_b.png"))
		print("[shot] moved ", jump, "  bake=", _field.bake_ms)
	get_tree().quit()


func _process(delta: float) -> void:
	_t += delta
	if _t < 0.15 or _field == null:
		return
	_t = 0.0
	var p := _field.get_parent().get_node_or_null("Player") as Node2D
	var pos := p.global_position if p else Vector2.ZERO
	var mats := ["草地", "沙滩", "水体"]
	var mat_name: String = mats[_field.material_at_world(pos)]
	text = "FPS %d    烘焙 %.1f ms    贴图 %dx%d\n世界 (%.0f, %.0f)    区块 (%d, %d)    脚下：%s\nWASD 移动  Shift 加速  F1 瓦片  F2 底图  R 回原点" % [
		Engine.get_frames_per_second(),
		_field.bake_ms,
		_field.last_rect.size.x, _field.last_rect.size.y,
		pos.x, pos.y,
		int(floor(pos.x / 16.0 / 16.0)), int(floor(pos.y / 16.0 / 16.0)),
		mat_name,
	]


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_F1:
			_field.toggle_tiles()
		KEY_F2:
			var canvas := _field.get_node_or_null("../WaterCanvas") as MeshInstance2D
			if canvas and canvas.material is ShaderMaterial:
				var mat := canvas.material as ShaderMaterial
				var cur: float = mat.get_shader_parameter("ground_mix")
				mat.set_shader_parameter("ground_mix", 0.0 if cur > 0.5 else 1.0)
		KEY_R:
			var p := _field.get_parent().get_node_or_null("Player") as Node2D
			if p:
				p.global_position = Vector2.ZERO
