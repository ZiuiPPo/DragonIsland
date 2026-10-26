@tool
class_name TerrainField
extends Node2D
## 地形场：柏林噪声 → 高度数组 → 瓦片分类 → 烘焙成一张小贴图 → 跨区块时更新。
##
## 设计上的几个要点（改之前先看一眼）：
##   1. **高度按「世界坐标」采样**，不是按区块局部坐标。否则区块边界会出一圈接缝，
##      这是这类系统最常见的 bug。
##   2. **贴图 1 texel = 1 格瓦片**。高度场是低频数据，不需要按美术像素存；
##      144x144 就够盖住一屏还多，重烤的开销可以忽略。
##   3. **贴图是世界锚定的**：矩形只在跨区块时跳一次，格子里存的是世界量。
##      如果每帧按相机重烤，整片水会跟着镜头滑。
##   4. 分类（草/沙/水）是**硬阈值**，给玩法用；烘焙贴图里的水体蒙版也是硬 0/1，
##      平滑交给 GPU 的双线性采样 —— 玩法所见即所得，画面又是软的。

signal baked(origin: Vector2, size: Vector2)

const MAT_GRASS := 0
const MAT_SAND := 1
const MAT_WATER := 2

@export_group("网格")
## 一格瓦片多少世界像素
@export var tile_size: int = 16
## 一个区块多少格
@export var chunk_tiles: int = 16
## 视距半径（区块）。4 圈 = 9x9 区块 = 2304 世界像素，正好盖住 1920 宽的视口。
@export_range(1, 10) var view_chunks: int = 4
## 烘焙矩形比可见范围多留几格，防止采样到贴图边缘的 clamp
@export var pad_tiles: int = 8

@export_group("地形")
@export var world_seed: int = 20261026
@export var noise_freq_low: float = 0.0016
@export var noise_freq_mid: float = 0.0075
@export_range(0.0, 1.0) var mid_weight: float = 0.12
@export var warp_freq: float = 0.0035
@export var warp_strength: float = 55.0
## 水 / 沙 分界高度
@export var h_water: float = 0.46
## 沙 / 草 分界高度（只用于玩法分类，画面上的沙滩宽度由 shader 的 beach_width 控制）
@export var h_sand: float = 0.49
## 水深归一化范围：从水线往下多少高度算"深水"
@export var depth_range: float = 0.22
## 距离场在多少格之内截止（和 shader 的 sdf_range 要一致）
@export var sdf_range: float = 8.0

@export_group("场景引用")
@export var player_path: NodePath
@export var canvas_path: NodePath
@export var tile_layer_path: NodePath
## 没有 player 时（比如在编辑器里）用它当烘焙中心
@export var bake_center := Vector2.ZERO

var _noise_low := FastNoiseLite.new()
var _noise_mid := FastNoiseLite.new()
var _noise_warp := FastNoiseLite.new()

var _player: Node2D
var _canvas: MeshInstance2D
var _tile_layer: TileMapLayer

## Vector2i(区块坐标) -> PackedFloat32Array(高度)
var _chunks := {}
var _last_chunk := Vector2i(999999, 999999)
var _texture: ImageTexture
## 调试用：哪些区块的瓦片已经写进 TileMapLayer 了
var _tiles_done := {}

var bake_ms: float = 0.0
var last_rect := Rect2i()
var _last_image: Image = null
## 最近一次烘焙出的有符号距离场（>0 在水里，单位「格」），写瓦片时按它分沙滩
var bake_dist := PackedFloat32Array()
var bake_origin := Vector2i.ZERO
var bake_size := Vector2i.ZERO


## 某个瓦片到水线的有符号距离（格）。离得太远就返回一个大值。
func dist_at_tile(t: Vector2i) -> float:
	var lx := t.x - bake_origin.x
	var ly := t.y - bake_origin.y
	if lx < 0 or ly < 0 or lx >= bake_size.x or ly >= bake_size.y:
		return 99.0
	return bake_dist[ly * bake_size.x + lx]


func _ready() -> void:
	_player = get_node_or_null(player_path)
	_canvas = get_node_or_null(canvas_path)
	_tile_layer = get_node_or_null(tile_layer_path)
	# 编辑器里没有相机是正常的（用 bake_center），别刷红字
	if _canvas == null and not Engine.is_editor_hint():
		push_error("[TerrainField] canvas_path 没设对")
		return
	_setup_noise(_noise_low, noise_freq_low, 2)
	_setup_noise(_noise_mid, noise_freq_mid, 1)
	_setup_noise(_noise_warp, warp_freq, 2)
	_noise_warp.seed = world_seed + 7777
	if _tile_layer:
		_tile_layer.visible = false
		_setup_tileset()


func _setup_noise(n: FastNoiseLite, freq: float, octaves: int) -> void:
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	n.frequency = freq
	n.seed = world_seed


# ─────────────────────────────────────────────────────────────────────
#  高度场
# ─────────────────────────────────────────────────────────────────────

## 用世界坐标采样：区块之间天然连续，不会出现接缝。
func _height_at_tile(tx: int, ty: int) -> float:
	var world := Vector2(tx * tile_size, ty * tile_size)
	var wx := _noise_warp.get_noise_2d(world.x, world.y) * warp_strength
	var wy := _noise_warp.get_noise_2d(world.x + 1371.0, world.y - 571.0) * warp_strength
	var p := world + Vector2(wx, wy)
	var n := _noise_low.get_noise_2d(p.x, p.y) * (1.0 - mid_weight) \
			+ _noise_mid.get_noise_2d(p.x, p.y) * mid_weight
	return clampf(0.5 + n * 0.62, 0.0, 1.0)


func _chunk_heights(c: Vector2i) -> PackedFloat32Array:
	if _chunks.has(c):
		return _chunks[c]
	var n := chunk_tiles * chunk_tiles
	var arr := PackedFloat32Array()
	arr.resize(n)
	var base := c * chunk_tiles
	for ty in chunk_tiles:
		for tx in chunk_tiles:
			arr[ty * chunk_tiles + tx] = _height_at_tile(base.x + tx, base.y + ty)
	_chunks[c] = arr
	return arr


func _chunk_of_tile(t: Vector2i) -> Vector2i:
	return Vector2i(floori(float(t.x) / chunk_tiles), floori(float(t.y) / chunk_tiles))


func _player_chunk() -> Vector2i:
	var center := _player.global_position if _player else bake_center
	return _chunk_of_tile(Vector2i(floori(center.x / tile_size), floori(center.y / tile_size)))


## 玩法用的查询接口：某个世界坐标是什么材质。
func material_at_world(pos: Vector2) -> int:
	var t := Vector2i(floori(pos.x / tile_size), floori(pos.y / tile_size))
	var c := _chunk_of_tile(t)
	var arr := _chunk_heights(c)
	var local := t - c * chunk_tiles
	var h := arr[local.y * chunk_tiles + local.x]
	if h < h_water:
		return MAT_WATER
	if h < h_sand:
		return MAT_SAND
	return MAT_GRASS


func height_at_world(pos: Vector2) -> float:
	var t := Vector2i(floori(pos.x / tile_size), floori(pos.y / tile_size))
	var c := _chunk_of_tile(t)
	var arr := _chunk_heights(c)
	var local := t - c * chunk_tiles
	return arr[local.y * chunk_tiles + local.x]


# ─────────────────────────────────────────────────────────────────────
#  烘焙
# ─────────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	# 编辑器里不跟着「玩家」跑，只在打开场景 / 点重新生成时烘一次
	if Engine.is_editor_hint():
		return
	if _player == null:
		return
	var c := _player_chunk()
	if c != _last_chunk:
		_last_chunk = c
		rebake(c)


func bake_rect_for(c: Vector2i) -> Rect2i:
	var side := (2 * view_chunks + 1) * chunk_tiles
	var size := Vector2i(side + 2 * pad_tiles, side + 2 * pad_tiles)
	# 以玩家所在区块为中心：起点要减去视距，否则整张图会整体偏移 (view_chunks * 区块)，
	# 屏幕一侧会一直在采样贴图被 clamp 的边缘（表现为一片"冻住的"纯色）。
	var origin := (c - Vector2i(view_chunks, view_chunks)) * chunk_tiles \
			- Vector2i(pad_tiles, pad_tiles)
	return Rect2i(origin, size)


func rebake(c: Vector2i) -> void:
	var t0 := Time.get_ticks_usec()
	var rect := bake_rect_for(c)
	last_rect = rect
	var w := rect.size.x
	var h := rect.size.y

	# 1) 把每个区块的高度数组拼成一整块（区块带缓存，跨区块时只重算新进来的那几个）
	var heights := PackedFloat32Array()
	heights.resize(w * h)
	var cc0 := _chunk_of_tile(rect.position)
	var cc1 := _chunk_of_tile(rect.end - Vector2i.ONE)
	for cy in range(cc0.y, cc1.y + 1):
		for cx in range(cc0.x, cc1.x + 1):
			var arr := _chunk_heights(Vector2i(cx, cy))
			var tile0 := Vector2i(cx, cy) * chunk_tiles
			for ty in chunk_tiles:
				var wy := tile0.y + ty - rect.position.y
				if wy < 0 or wy >= h:
					continue
				var src := ty * chunk_tiles
				var dst := wy * w + tile0.x - rect.position.x
				for tx in chunk_tiles:
					var wx := dst + tx
					if wx < wy * w or wx >= wy * w + w:
						continue
					heights[wx] = arr[src + tx]
	_evict_chunks(rect)

	# 2) 高度 → 水陆分类 → 距离场
	#    距离场必须做真正的距离变换。用「高度差 ÷ 高度梯度」近似会在山脊上
	#    失真（陡坡会算出一堆假的距离），沙滩就会在远离水的地方冒出一条条横带。
	var n := w * h
	var water := PackedByteArray()
	water.resize(n)
	for i in n:
		water[i] = 1 if heights[i] < h_water else 0

	var to_water := _chamfer(water, w, h, 1)   # 每个格到最近水格的距离（水格本身为 0）
	var to_land := _chamfer(water, w, h, 0)    # 每个格到最近陆格的距离

	# 3) 打包成 RGBA
	# 先把有符号距离单独存一份：写瓦片时要按「离岸几格」分沙滩，直接查这个数组。
	bake_origin = rect.position
	bake_size = rect.size
	bake_dist.resize(n)
	for i in n:
		bake_dist[i] = to_land[i] if water[i] == 1 else -to_water[i]
	_smooth_dist(w, h)

	var bytes := PackedByteArray()
	bytes.resize(n * 4)
	for i in n:
		var hv := heights[i]
		var d := bake_dist[i]
		var o := i * 4
		# R = 水深 0..1（水线 0 → 深水 1），用满 0..255 才不会出现色阶断层
		bytes[o] = int(clampf((h_water - hv) / depth_range, 0.0, 1.0) * 255.0)
		# G = 有符号距离（0.5 = 水线），单位「格」
		bytes[o + 1] = int(clampf(0.5 + 0.5 * d / sdf_range, 0.0, 1.0) * 255.0)
		# B = 陆地高度（备用：以后想按高度做草色变化可以直接用）
		bytes[o + 2] = int(clampf((hv - h_water) / 0.12, 0.0, 1.0) * 255.0)
		bytes[o + 3] = 255 if water[i] == 1 else 0

	# 3) 上传
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, bytes)
	_last_image = img
	if _texture == null:
		_texture = ImageTexture.create_from_image(img)
	else:
		_texture.update(img)

	# 4) 告诉 shader：贴图在哪、多大
	#    编辑器里不写这些运行时贴图参数——否则保存场景时会把生成的贴图烤进 .tscn
	if not Engine.is_editor_hint():
		var mat := _canvas.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("mask_tex", _texture)
			mat.set_shader_parameter("rect_origin", Vector2(rect.position) * tile_size)
			mat.set_shader_parameter("rect_size", Vector2(rect.size) * tile_size)
			mat.set_shader_parameter("sdf_range", sdf_range)
			mat.set_shader_parameter("tile_size", float(tile_size))

	if _tile_layer and _tile_layer.visible:
		_sync_tiles(rect)

	bake_ms = (Time.get_ticks_usec() - t0) / 1000.0
	baked.emit(Vector2(rect.position) * tile_size, Vector2(rect.size) * tile_size)


## 倒角距离变换（chamfer 3-4）：两趟扫描，得到每个格到最近 `seed` 格的距离（单位：格）。
## 距离场是浪花和沙滩宽度的唯一依据，所以这里不能糊弄。
func _chamfer(water: PackedByteArray, w: int, h: int, seed: int) -> PackedFloat32Array:
	const INF := 1.0e9
	const DIAG := 1.41421356
	var n := w * h
	var d := PackedFloat32Array()
	d.resize(n)
	for i in n:
		d[i] = 0.0 if water[i] == seed else INF

	for y in h:
		var row := y * w
		for x in w:
			var i := row + x
			var v := d[i]
			if y > 0:
				var up := i - w
				if d[up] + 1.0 < v:
					v = d[up] + 1.0
				if x > 0 and d[up - 1] + DIAG < v:
					v = d[up - 1] + DIAG
				if x < w - 1 and d[up + 1] + DIAG < v:
					v = d[up + 1] + DIAG
			if x > 0 and d[i - 1] + 1.0 < v:
				v = d[i - 1] + 1.0
			d[i] = v

	for y in range(h - 1, -1, -1):
		var row := y * w
		for x in range(w - 1, -1, -1):
			var i := row + x
			var v := d[i]
			if y < h - 1:
				var dn := i + w
				if d[dn] + 1.0 < v:
					v = d[dn] + 1.0
				if x > 0 and d[dn - 1] + DIAG < v:
					v = d[dn - 1] + DIAG
				if x < w - 1 and d[dn + 1] + DIAG < v:
					v = d[dn + 1] + DIAG
			if x < w - 1 and d[i + 1] + 1.0 < v:
				v = d[i + 1] + 1.0
			d[i] = v
	return d


## 给距离场做两遍分离式平滑。
## 倒角距离变换出来的等值线是八方向折线，直接拿来画海线会是一段直边接一段直边，
## 拐角特别硬（看起来像拿尺子画的）；磨一下之后等值线才是圆滑的曲线。
func _smooth_dist(w: int, h: int) -> void:
	var tmp := PackedFloat32Array()
	tmp.resize(w * h)
	for _pass in 2:
		for y in h:
			var row := y * w
			for x in w:
				var i := row + x
				var l := bake_dist[i - 1] if x > 0 else bake_dist[i]
				var r := bake_dist[i + 1] if x < w - 1 else bake_dist[i]
				tmp[i] = (l + bake_dist[i] * 2.0 + r) * 0.25
		for y in h:
			var row := y * w
			for x in w:
				var i := row + x
				var up := tmp[i - w] if y > 0 else tmp[i]
				var dn := tmp[i + w] if y < h - 1 else tmp[i]
				bake_dist[i] = (up + tmp[i] * 2.0 + dn) * 0.25


func _evict_chunks(rect: Rect2i) -> void:
	if _chunks.size() < 400:
		return
	var cc0 := _chunk_of_tile(rect.position) - Vector2i.ONE
	var cc1 := _chunk_of_tile(rect.end) + Vector2i.ONE
	for key in _chunks.keys():
		if key.x < cc0.x or key.y < cc0.y or key.x > cc1.x or key.y > cc1.y:
			_chunks.erase(key)


# ─────────────────────────────────────────────────────────────────────
#  瓦片（调试用：直接看分类结果，验证完就可以换成正式美术）
# ─────────────────────────────────────────────────────────────────────

func _setup_tileset() -> void:
	var tex := load("res://assets/tilesets/terrain_placeholder.png") as Texture2D
	if tex == null:
		return
	var ts := TileSet.new()
	ts.tile_size = Vector2i(tile_size, tile_size)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(tile_size, tile_size)
	# 图集是 4 列 3 行：第 0 行草、第 1 行沙、第 2 行水
	for row in 3:
		for col in 4:
			src.create_tile(Vector2i(col, row))
	ts.add_source(src, 0)
	_tile_layer.tile_set = ts


func _sync_tiles(rect: Rect2i) -> void:
	var cc0 := _chunk_of_tile(rect.position)
	var cc1 := _chunk_of_tile(rect.end - Vector2i.ONE)
	for cy in range(cc0.y, cc1.y + 1):
		for cx in range(cc0.x, cc1.x + 1):
			var key := Vector2i(cx, cy)
			if _tiles_done.has(key):
				continue
			_tiles_done[key] = true
			var arr := _chunk_heights(key)
			var base := key * chunk_tiles
			for ty in chunk_tiles:
				for tx in chunk_tiles:
					var hv := arr[ty * chunk_tiles + tx]
					var row := MAT_GRASS
					if hv < h_water:
						row = MAT_WATER
					elif hv < h_sand:
						row = MAT_SAND
					var variant := absi(hash(Vector2i(base.x + tx, base.y + ty))) % 4
					_tile_layer.set_cell(Vector2i(base.x + tx, base.y + ty), 0, Vector2i(variant, row))
	print("[tiles] used rect = ", _tile_layer.get_used_rect())


func toggle_tiles() -> void:
	if _tile_layer == null:
		return
	_tile_layer.visible = not _tile_layer.visible
	if _tile_layer.visible:
		_sync_tiles(bake_rect_for(_player_chunk()))


## 调试用：把烘焙出来的小图按通道拆开存成一张 2x2 对比图（左上 R / 右上 G / 左下 B / 右下 A）。
func save_mask_debug(path: String) -> void:
	if _last_image == null:
		return
	var src := _last_image
	var w := src.get_width()
	var h := src.get_height()
	var bytes := src.get_data()
	var side := w * 2
	var out := PackedByteArray()
	out.resize(side * side * 3)
	for ch in 4:
		var ox := (ch % 2) * w
		var oy := (ch >> 1) * h
		for y in h:
			for x in w:
				var v := bytes[(y * w + x) * 4 + ch]
				var o := ((oy + y) * side + ox + x) * 3
				out[o] = v
				out[o + 1] = v
				out[o + 2] = v
	var img := Image.create_from_data(side, side, false, Image.FORMAT_RGB8, out)
	img.resize(side * 2, side * 2, Image.INTERPOLATE_NEAREST)
	img.save_png(path)
