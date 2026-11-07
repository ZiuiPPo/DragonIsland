@tool
class_name GrassField2D
extends Node2D
## 2D 像素草地：把大量草丛精灵铺在地面上，风、色块、踩踏全在 GPU 上算。
##
## 它对应 3D 版的 MultiMeshInstance（多网格实例）：一堆小四边形铺在地平面上。
## 但 2D 没有深度缓冲，所以这里按**区块**分装：
##   · 一个区块 = 一个 MultiMeshInstance2D = 一次 draw call，方便视口剔除；
##   · chunk_px 决定剔除粒度，192 世界像素 ≈ 12 格瓦片。
##
## 位置上有个坑：**必须以统一整数格来铺**，不能让每个区块各铺各的。
## 否则区块边界会重算一遍、接缝处草丛叠成一团（3D 里这问题被深度测试掩盖了，
## 2D 里会直接变成一条深色的缝）。所以这里按节点局部坐标的统一整数格遍历，
## 再按落点把实例分给各自区块，天然不重不漏。
##
## 用法：
##   1. 新建 Node2D，挂本脚本，Inspector 里填 sprite / area；
##   2. 把 grass_tuft_2d.gdshader 做成 ShaderMaterial 填进 tuft_material
##      （风、色块、交互参数都在材质里调；脚本会去读 patch_scale 让疏密跟色块同步）；
##   3. 只想长在草地上：mask_mode 选 terrain，mask_path 指到 IslandTerrain 节点。
##
## 注意：**别给这一层设 modulate**。逐实例颜色（COLOR）在这套系统里是数据通道
## （随机数 / 相位 / 变体 / 风力），modulate 会把它乘坏。

const NOISE_PATH := "res://assets/textures/noise/grass_noise.png"

@export_group("范围与疏密")
## 局部包围框；椭圆模式下宽高分别是两个直径。
@export var area := Rect2(-672.0, -420.0, 1000.0, 1000.0):
	set(value):
		area = value
		_request_rebuild()
## 宽高相等时，ellipse 为圆形。
@export_enum("rectangle", "ellipse") var area_shape := "rectangle":
	set(value):
		area_shape = value
		_request_rebuild()
## 每棵草平均占多大一格（世界像素）。越小越密，12~24 比较合适
@export var cell_size := 18.0
## 实际铺出来的比例（会再乘上噪声疏密）
@export_range(0.0, 1.0) var density := 0.9
## 位置抖动：0 = 严格网格（看得出格子），0.5 = 抖半格
@export_range(0.0, 0.95) var jitter := 0.5
## 装饰草（异质性 B）：同一格再长一株的概率。默认给小值，多了就变味
@export_range(0.0, 0.5) var decor_chance := 0.03
## 长势旺的色块里，草丛放大成 2 倍的概率。
## 默认 0（关）：放大后的草丛和周围对不上，看着像被拉伸过，实测效果不好。
@export_range(0.0, 0.6) var big_chance := 0.0
@export var world_seed := 20261027
## 镜像比例：x 翻转不破坏左上光源的斜面，是 2D 里最便宜的变体
@export_range(0.0, 1.0) var flip_chance := 0.5

@export_group("精灵")
@export var sprite: Texture2D
## 单帧尺寸（世界像素）。草丛是 32x16 就填 32x16
@export var frame_size := Vector2i(32, 16)
## 精灵横向有几帧（图集式序列帧）。只有一帧就填 1
@export var frame_count := 1
## 整数放大：2 = 每颗像素变成 2x2。**别用小数**，否则像素宽窄不一
@export_range(1, 4) var tuft_scale := 1
## 竖直细分：剪切要逐行取整才不会糊。只有 wind_shear > 0 时才需要，4~8 片够了
@export_range(0, 8) var subdivide := 0
## 着色器材质（风 / 色块 / 交互参数都在里面）
@export var tuft_material: ShaderMaterial

@export_group("区块")
## 一个 MultiMeshInstance2D 覆盖多少世界像素
@export var chunk_px := 192

@export_group("遮罩")
## none = 铺满所选形状；tilemap = 只铺有瓦片的地方；terrain = 只铺 TerrainField 判定为草地的格子
@export_enum("none", "tilemap", "terrain") var mask_mode := "none"
@export var mask_path: NodePath
## 排除层：这些 TileMapLayer 上有瓦片的格子不长草（农田、沙滩这种"铺了东西"的地方）。
## 注意这些层多半是运行时才铺的，所以本节点会等几帧再生成（见 build_delay_frames）。
@export var avoid_paths: Array[NodePath] = []
## 等几帧再生成：让地形先把瓦片铺出来，排除层才查得到东西。0 = 立刻生成
@export_range(0, 10) var build_delay_frames := 2

@export_group("交互")
## 会踩开草丛的节点（玩家 / 员工 NPC）。也可以改用分组，见 pusher_group
@export var pusher_paths: Array[NodePath] = []
## 按分组找推挤源（员工 NPC 是运行时生成的，用这个更省事）
@export var pusher_group: StringName = &""
@export var pusher_radius := 30.0
@export var pusher_strength := 6.0
## 停住之后多久弹回来（秒）：0 = 立刻
@export var pusher_decay := 0.55
## 调试用：让鼠标当推挤源
@export var push_follow_mouse := false

var build_ms := 0.0
var instance_count := 0
var _rebuild_queued := false

var _noise_w := 0
var _noise_h := 0
var _noise_data := PackedByteArray()

var _chunks := {}                       # Vector2i -> MultiMeshInstance2D
var _heat := {}                         # Node2D -> float
var _last_pos := {}                     # Node2D -> Vector2


func _ready() -> void:
	if tuft_material == null and material is ShaderMaterial:
		tuft_material = material
	_load_noise()
	# 等几帧：地形（IslandTerrain）是运行时才铺沙滩/农田瓦片的，排除层要等它铺完
	if build_delay_frames > 0:
		for i in build_delay_frames:
			await get_tree().process_frame
	rebuild()
	if Engine.is_editor_hint():
		set_process(false)


func _process(delta: float) -> void:
	_push_update(delta)


# ─────────────────────────────────────────────────────────────────────
#  生成
# ─────────────────────────────────────────────────────────────────────

## 重新铺一遍。改了 area / density / sprite 之后调它。
func rebuild() -> void:
	var t0 := Time.get_ticks_usec()
	_clear()
	instance_count = 0
	if sprite == null:
		build_ms = 0.0
		return

	# ★ 关键：着色器里的 frame_count 是**着色器 uniform**，不是上面那个导出量。
	#   不写进去它就永远是 1 —— 整张 64x16 会被压进 16x16 的四边形里（横向压扁 4 倍），
	#   四帧变体也全部失效。这个坑非常隐蔽，因为脚本这边的数值全是对的。
	if tuft_material:
		tuft_material.set_shader_parameter("frame_count", float(maxi(frame_count, 1)))

	# 色块的尺度和对比度以材质为准：疏密必须跟色块同步，
	# 否则会出现"深色块里草反而更密"这种自相矛盾的画面。
	var pscale := _mat_float("patch_scale", 1400.0)
	var pcontrast := _mat_float("patch_contrast", 1.9)
	var pbias := _mat_float("patch_bias", 0.0)

	var cell := maxf(cell_size, 2.0)
	var buckets := {}
	var i0 := floori(area.position.x / cell)
	var i1 := ceili(area.end.x / cell)
	var j0 := floori(area.position.y / cell)
	var j1 := ceili(area.end.y / cell)

	for j in range(j0, j1):
		for i in range(i0, i1):
			var h := _cell_hash(i, j)
			# 抖动后取整：草丛永远落在整数像素上，缩放时像素才是方的
			var pos := Vector2(
				(i + 0.5 + (_rnd(h, 1) - 0.5) * jitter * 2.0) * cell,
				(j + 0.5 + (_rnd(h, 2) - 0.5) * jitter * 2.0) * cell).round()
			if not _contains_point(pos):
				continue

			# 疏密：和色块反向联动。噪声明亮的那一侧（地面调色板是"日照"）草最旺，
			# 暗的一侧稀疏但不至于全秃 —— 全秃的那版在大地图上像一块块斑秃。
			var raw_n := _noise_at(to_global(pos), pscale)
			var patch := clampf((raw_n - 0.5) * pcontrast + 0.5 + pbias, 0.0, 1.0)
			var cover := 0.25 + 0.75 * (1.0 - smoothstep(0.15, 0.85, patch))
			if _rnd(h, 3) > density * cover:
				continue
			if not _in_mask(pos):
				continue

			# ★ 3D 里"高一点的草"= 2D 里"大一号的草丛"。
			#   长势旺的色块里按概率放大成 2 倍，于是浓密的区域是"更高的草"，
			#   而不是"更密的点"——这一条是 2D 版最有用的一个改写。
			var big := 1
			if cover > 0.55 and _rnd(h, 8) < big_chance:
				big = 2
			_add(buckets, pos, h, 0, big)

			# 装饰草（异质性 B）：同一格再多长一株，比"整体放大"更像是长势旺
			if _rnd(h, 4) < decor_chance:
				var ang := _rnd(h, 5) * TAU
				var rad := cell * (0.25 + 0.35 * _rnd(h, 6))
				var extra := 2 if _rnd(h, 9) < big_chance * 0.5 else 1
				var decor_pos := (pos + Vector2(cos(ang), sin(ang)) * rad).round()
				if _contains_point(decor_pos) and _in_mask(decor_pos):
					_add(buckets, decor_pos, h, 7, extra)

	for key in buckets.keys():
		_build_chunk(key, buckets[key])

	build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	print("[grass] ", get_debug_info())


## Inspector 范围修改合并为一次重建。
func _request_rebuild() -> void:
	if not is_node_ready() or _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild_deferred.call_deferred()


func _rebuild_deferred() -> void:
	_rebuild_queued = false
	if is_inside_tree():
		rebuild()


func _contains_point(pos: Vector2) -> bool:
	if area.size.x <= 0.0 or area.size.y <= 0.0 or not area.has_point(pos):
		return false
	if area_shape == "ellipse":
		var offset := (pos - area.get_center()) / (area.size * 0.5)
		return offset.length_squared() <= 1.0
	return true


func _add(buckets: Dictionary, pos: Vector2, h: int, salt: int, size: int) -> void:
	var b := _bucket_of(pos)
	if not buckets.has(b):
		buckets[b] = []
	var frames := maxi(frame_count, 1)
	var frame := mini(int(_rnd(h, 10 + salt) * frames), frames - 1)
	var flip := 0.0 if _rnd(h, 11 + salt) > flip_chance else 1.0
	# 变体编码：shader 里 vv = 变体 * frame_count，整数部分 = 帧号，小数 0.25/0.75 = 是否镜像
	var variant := (float(frame) + (0.25 if flip < 0.5 else 0.75)) / float(frames)
	# 实例颜色四通道 = 随机数 / 时间相位 / 变体 / 风力增益
	var col := Color(
		_rnd(h, 12 + salt),
		_rnd(h, 13 + salt),
		variant,
		0.55 + 0.45 * _rnd(h, 14 + salt))
	buckets[b].append([pos, col, size])


func _build_chunk(key: Vector2i, items: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true          # 必须在 instance_count 之前打开

	# 网格永远按 1 倍建，放大走实例变换的 scale —— 这样同一块里能混 1x / 2x
	var quad := QuadMesh.new()
	quad.size = Vector2(frame_size)
	if subdivide > 0:
		# 4.7 的 QuadMesh 竖直方向叫 subdivide_depth（没有 height）
		quad.subdivide_depth = subdivide     # 逐行取整的剪切靠这个细分
	mm.mesh = quad
	mm.instance_count = items.size()

	for idx in items.size():
		var s := float(tuft_scale * int(items[idx][2]))
		mm.set_instance_transform_2d(idx, Transform2D(0.0, Vector2(s, s), 0.0, items[idx][0]))
		mm.set_instance_color(idx, items[idx][1])

	var node := MultiMeshInstance2D.new()
	node.name = "Chunk_%d_%d" % [key.x, key.y]
	node.multimesh = mm
	node.material = tuft_material
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(node)
	_chunks[key] = node
	instance_count += items.size()


func _clear() -> void:
	for node in _chunks.values():
		if is_instance_valid(node):
			node.queue_free()
	_chunks.clear()


# ─────────────────────────────────────────────────────────────────────
#  遮罩
# ─────────────────────────────────────────────────────────────────────

func _in_mask(pos: Vector2) -> bool:
	var world_pos := to_global(pos)
	if mask_mode == "none":
		return true
	# 排除层优先：农田/沙滩铺过瓦片的地方一律不长（否则草丛会盖在菜地和沙子上）
	for p in avoid_paths:
		var av := get_node_or_null(p) as TileMapLayer
		# tile_set 还是 null 的层（沙滩层就是这样，图集是运行时才建的）肯定一格瓦片都没有，
		# 直接跳过。硬调 local_to_map() 会刷一整屏 "Condition tile_set.is_null()" 的报错。
		if av == null or av.tile_set == null:
			continue
		if av.get_cell_source_id(av.local_to_map(av.to_local(world_pos))) != -1:
			return false
	var m := get_node_or_null(mask_path)
	if m == null:
		return true
	if mask_mode == "terrain":
		# 编辑器里：本脚本是 @tool，遮罩目标不是的话拿到的是 placeholder 实例 ——
		# 这种实例 has_method() 会谎报 true，真 call() 才报 "placeholder instance"。
		# 所以先看它的脚本是不是 tool 脚本，不是就当"没有遮罩"，别去 call。
		if Engine.is_editor_hint():
			var scr := m.get_script() as Script
			if scr == null or not scr.is_tool():
				return true
		if m.has_method("material_at_world"):
			return int(m.call("material_at_world", world_pos)) == 0   # TerrainField.MAT_GRASS
		return true
	# tilemap：有瓦片的地方才长草（图层可能带 scale，必须走它自己的坐标变换）
	var layer := m as TileMapLayer
	if layer == null or layer.tile_set == null:
		return true
	return layer.get_cell_source_id(layer.local_to_map(layer.to_local(world_pos))) != -1


# ─────────────────────────────────────────────────────────────────────
#  交互：把推挤源写进 shader 的 pushers[]
# ─────────────────────────────────────────────────────────────────────

func _push_update(delta: float) -> void:
	if tuft_material == null:
		return

	var arr := PackedVector4Array()
	arr.resize(4)
	for i in 4:
		arr[i] = Vector4.ZERO

	var slot := 0
	if push_follow_mouse:
		var mp := get_global_mouse_position()
		arr[slot] = Vector4(mp.x, mp.y, pusher_radius, pusher_strength * 0.8)
		slot += 1

	for n in _resolve_pushers():
		if slot >= 4:
			break
		var p: Vector2 = n.global_position
		# 只有"在动"才踩开：停住后 heat 衰减，草丛自己弹回来
		var moved := 999.0
		if _last_pos.has(n):
			moved = p.distance_to(_last_pos[n])
		_last_pos[n] = p

		var target := 1.0 if moved > 0.35 else 0.0
		var heat: float = _heat.get(n, 0.0)
		if pusher_decay <= 0.001:
			heat = target
		else:
			heat = lerpf(heat, target, 1.0 if target > heat else clampf(delta / pusher_decay, 0.0, 1.0))
		_heat[n] = heat

		arr[slot] = Vector4(p.x, p.y, pusher_radius, pusher_strength * heat)
		slot += 1

	tuft_material.set_shader_parameter("pushers", arr)


func _resolve_pushers() -> Array:
	var out: Array = []
	for p in pusher_paths:
		var n := get_node_or_null(p) as Node2D
		if n and is_instance_valid(n):
			out.append(n)
	if String(pusher_group) != "":
		for n in get_tree().get_nodes_in_group(pusher_group):
			if n is Node2D and not out.has(n):
				out.append(n)
	# 只有 4 个槽位：离镜头近的先占，屏幕外的就不用算了
	if out.size() > 4:
		var cam := get_viewport().get_camera_2d()
		if cam:
			var center := cam.get_screen_center_position()
			out.sort_custom(func(a: Node2D, b: Node2D) -> bool:
				return a.global_position.distance_squared_to(center) \
					< b.global_position.distance_squared_to(center))
	return out


# ─────────────────────────────────────────────────────────────────────
#  噪声采样（和 shader 同一张贴图、同一个尺度）
# ─────────────────────────────────────────────────────────────────────

func _load_noise() -> void:
	var tex := load(NOISE_PATH) as Texture2D
	if tex == null:
		return
	var img := tex.get_image()
	if img == null:
		return
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	_noise_w = img.get_width()
	_noise_h = img.get_height()
	_noise_data = img.get_data()


## 双线性采样 R 通道（可平铺，和 shader 的 repeat_enable 一致）
func _noise_at(pos: Vector2, scale_px: float) -> float:
	if _noise_data.is_empty():
		return 0.5
	var s := maxf(scale_px, 1.0)
	var u := pos.x / s * float(_noise_w)
	var v := pos.y / s * float(_noise_h)
	var xf := floorf(u)
	var yf := floorf(v)
	var fx := u - xf
	var fy := v - yf
	var x0 := posmod(int(xf), _noise_w)
	var y0 := posmod(int(yf), _noise_h)
	var x1 := (x0 + 1) % _noise_w
	var y1 := (y0 + 1) % _noise_h
	var a := float(_noise_data[(y0 * _noise_w + x0) * 4]) / 255.0
	var b := float(_noise_data[(y0 * _noise_w + x1) * 4]) / 255.0
	var c := float(_noise_data[(y1 * _noise_w + x0) * 4]) / 255.0
	var d := float(_noise_data[(y1 * _noise_w + x1) * 4]) / 255.0
	# 转成线性：canvas_item 里纹理采样是线性的，不转的话 CPU 判的疏密
	# 会和 GPU 判的色块边界对不上（两边看到的是同一张图、不同的曲线）
	return _srgb_to_linear(lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy))


func _srgb_to_linear(v: float) -> float:
	if v <= 0.04045:
		return v / 12.92
	return pow((v + 0.055) / 1.055, 2.4)


func _mat_float(param: String, fallback: float) -> float:
	if tuft_material == null:
		return fallback
	var v = tuft_material.get_shader_parameter(param)
	return float(v) if v != null else fallback


# ─────────────────────────────────────────────────────────────────────
#  工具
# ─────────────────────────────────────────────────────────────────────

func _bucket_of(pos: Vector2) -> Vector2i:
	return Vector2i(
		floori((pos.x - area.position.x) / float(chunk_px)),
		floori((pos.y - area.position.y) / float(chunk_px)))


func _cell_hash(i: int, j: int) -> int:
	return hash(Vector3i(i, j, world_seed))


## 稳定伪随机：同一格每次生成的草都一样（读档、重进不该变样）
func _rnd(h: int, salt: int) -> float:
	var x: int = h ^ (salt * -1640531535)
	x = (x ^ (x >> 16)) * -2048144777
	x = (x ^ (x >> 13)) * -1028477379
	x = x ^ (x >> 16)
	var m := x % 65536
	if m < 0:
		m += 65536
	return float(m) / 65536.0


func get_debug_info() -> String:
	return "草丛 %d 个 / %d 块，生成 %.1f ms" % [instance_count, _chunks.size(), build_ms]
