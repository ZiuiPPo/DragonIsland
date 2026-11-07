extends Node2D
## 2D 草地验证场景：一块铺满草地瓦片的地面 + 一整层草丛，外加一个用来比对的角色。
##
## 跑法：
##   godot --path milky-frog-stead res://scenes/proto/grass_2d_proto.tscn
##   godot ... -- --shot out.png        截图（走 dev_shot）
##   godot ... -- --grass=off           关掉草丛，做"A/B 对比"的 before 图
##
## 这里的东西都是代码搭的，故意不落进 .tscn：参数验证阶段改脚本比改场景快。

const ATLAS := "res://assets/tilesets/grass.png"
const TUFT := "res://assets/sprites/decorations/grass_tuft.png"
const NOISE := "res://assets/textures/noise/grass_noise.png"
const SHADER := "res://shaders/grass_tuft_2d.gdshader"
const GROUND_SHADER := "res://shaders/grass_ground_2d.gdshader"
const PLAYER := "res://assets/sprites/npcs/staff/npc1_idle_move_left.png"

const TILE := 16
const GROUND_COLS := 128
const GROUND_ROWS := 80
const GRASS_CELL := 24.0

var _grass: GrassField2D
var _push := Vector2.INF


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	var cam := Camera2D.new()
	cam.name = "Camera2D"
	cam.enabled = true
	# --zoom=2 看细节；默认 1 = 正式场景的视野
	var zoom := float(_args().get("zoom", 1.0))
	cam.zoom = Vector2(zoom, zoom)
	add_child(cam)

	add_child(_make_ground())
	_grass = _make_grass()
	add_child(_grass)
	add_child(_make_player())
	var hud := _make_hud()
	add_child(hud)

	# 草丛层会等几帧再生成（要让地形的排除层先铺出来），HUD 晚一点再填数
	for i in 4:
		await get_tree().process_frame
	var label := hud.get_child(0) as Label
	if label:
		label.text = "2D 草地验证  |  %s  |  鼠标移进画面=踩开草丛" % _grass.get_debug_info()

	# --mouse=x,y：把系统光标挪到窗口里某个位置，用来截"草被踩开"那张图
	var a := _args()
	if a.has("mouse"):
		var mv := Vector2(float(a["mouse"].get_slice(",", 0)), float(a["mouse"].get_slice(",", 1)))
		await get_tree().process_frame
		Input.warp_mouse(mv)

	# --push=x,y（世界坐标）：脚本里直接写死一个推挤源，截图用（不依赖真的有鼠标在动）
	if a.has("push"):
		_push = Vector2(float(a["push"].get_slice(",", 0)), float(a["push"].get_slice(",", 1)))
		_grass.push_follow_mouse = false
		_grass.set_process(false)

	# --seq=N --seqdir=目录：连着截 N 帧，用来拼成会动的图
	if a.has("seq"):
		await _capture_seq(int(a["seq"]), String(a.get("seqdir", "user://seq")))


func _capture_seq(n: int, dir_path: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir_path)
	await get_tree().create_timer(1.2).timeout
	for i in n:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/f%02d.png" % [dir_path, i])
		await get_tree().create_timer(0.1).timeout
	get_tree().quit()


func _process(_delta: float) -> void:
	if _push == Vector2.INF:
		return
	var arr := PackedVector4Array()
	arr.resize(4)
	for i in 4:
		arr[i] = Vector4.ZERO
	arr[0] = Vector4(_push.x, _push.y, 44.0, 7.0)
	_grass.tuft_material.set_shader_parameter("pushers", arr)


func _make_ground() -> TileMapLayer:
	var tex := load(ATLAS) as Texture2D
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(TILE, TILE)
	# (1,1) 是纯草地（岛上的草就是拿它铺的），别的格子是自动拼接用的边缘块
	for y in 5:
		for x in 11:
			if not src.has_tile(Vector2i(x, y)):
				src.create_tile(Vector2i(x, y))
	ts.add_source(src, 0)

	var layer := TileMapLayer.new()
	layer.name = "Ground"
	layer.tile_set = ts
	# 和正式场景一致：地面在 -20 以下，草丛层在 -5，中间留给角色
	layer.z_index = -20
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 地面色块：同一套噪声、同一个色块尺度，和草丛层对上
	var gmat := ShaderMaterial.new()
	gmat.shader = load(GROUND_SHADER)
	gmat.set_shader_parameter("noise_tex", load(NOISE))
	gmat.set_shader_parameter("patch_strength", float(_args().get("patch", 0.0)))
	if _args().has("gdbg"):
		gmat.set_shader_parameter("debug", float(_args()["gdbg"]))
	layer.material = gmat
	# 地面网格以原点为中心。这里本来就是整数除法，写成 float 再取整只是为了不触发 integer_division 警告
	var c0 := int(-GROUND_COLS / 2.0)
	var r0 := int(-GROUND_ROWS / 2.0)
	for y in range(r0, r0 + GROUND_ROWS):
		for x in range(c0, c0 + GROUND_COLS):
			layer.set_cell(Vector2i(x, y), 0, Vector2i(1, 1))
	return layer


func _make_grass() -> GrassField2D:
	var a := _args()
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER)
	mat.set_shader_parameter("albedo_tex", load(TUFT))
	mat.set_shader_parameter("noise_tex", load(NOISE))
	# 风：往右下吹，稍微慢一点，方便截图对比
	mat.set_shader_parameter("wind_dir", Vector2(1.0, 0.35))
	mat.set_shader_parameter("wind_speed", 34.0)
	mat.set_shader_parameter("anim_fps", 9.0)
	for key in ["patch_scale", "patch_contrast", "wind_slide", "wind_shear", "patch_strength", "anim_fps"]:
		if a.has(key):
			mat.set_shader_parameter(key, float(a[key]))
	# 和正式场景保持一致：色块默认关（--patch=1 可以打开看效果）
	mat.set_shader_parameter("patch_strength", float(a.get("patch", 0.0)))

	var g := GrassField2D.new()
	g.name = "Grass"
	g.sprite = load(TUFT)
	g.frame_size = Vector2i(16, 16)      # 精灵是 64x16 = 4 帧 16x16
	g.frame_count = 4
	g.cell_size = float(a.get("cell", GRASS_CELL))
	g.density = float(a.get("density", 0.85))
	g.jitter = float(a.get("jitter", 0.5))
	g.decor_chance = float(a.get("decor", 0.03))
	g.subdivide = int(a.get("subdivide", 4))
	g.tuft_scale = int(a.get("scale", 1))
	g.area = Rect2(
		-GROUND_COLS * TILE * 0.5, -GROUND_ROWS * TILE * 0.5,
		GROUND_COLS * TILE, GROUND_ROWS * TILE)
	g.tuft_material = mat
	g.z_index = -5
	g.push_follow_mouse = true
	if a.has("grass") and a["grass"] == "off":
		g.visible = false
	return g


func _make_player() -> Sprite2D:
	var s := Sprite2D.new()
	s.name = "Player"
	s.texture = load(PLAYER)
	s.hframes = 8
	s.frame = 0
	s.position = Vector2(96, 48)
	s.z_index = 0
	return s


func _make_hud() -> CanvasLayer:
	var cl := CanvasLayer.new()
	cl.layer = 10
	var label := Label.new()
	label.position = Vector2(24, 20)
	label.text = "2D 草地验证  |  加载中…"
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	cl.add_child(label)
	return cl


## 把 --key=value 收成字典，方便一次跑一组参数做对比
func _args() -> Dictionary:
	var d := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			d[arg.substr(2).get_slice("=", 0)] = arg.get_slice("=", 1)
	return d
