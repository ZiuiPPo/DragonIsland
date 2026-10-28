class_name IslandTerrain
extends TerrainField
## 岛 = 一张抠图（`assets/sprites/island/island_cutout.png`），不是程序化生成的。
##
## 分工：
##   · **陆地形状**：`IslandImage`（Sprite2D）这张图的 alpha。alpha > 阈值算陆地。
##     想改岛的形状，直接改这张图 / 挪这个 Sprite 就行。
##   · **海岸线/水面**：仍然走「高度 → 水陆蒙版 → 倒角距离场 → 烘焙小贴图」，
##     只是高度改成从图片 alpha 采样。所以水会贴着这张图的轮廓走。
##   · **草地**：你自己的 `GrassLayer`，画在岛图**上面**。
##   · **沙滩**：用图里自带的，脚本不再铺瓦片（`paint_tiles = false`）。
##
## 图层顺序：沙滩/底层 -30 < 岛图 -28 < 海水 -25 < 你的草地 -20
##
## 没指定 `island_sprite_path` 时退回程序化椭圆岛（旧行为）。

@export_group("岛")
## 岛图节点（Sprite2D）。留空则退回程序化椭圆岛
@export var island_sprite_path: NodePath
## alpha 高于多少算陆地
@export_range(0.05, 0.95) var alpha_threshold := 0.5

@export_group("程序化椭圆岛（没指定岛图时用）")
@export var island_center := Vector2(0, 120)
@export var island_radius := Vector2(620, 420)
@export var coastline_amplitude := 0.55
@export var island_edge_sharpness := 2.6

@export_group("图层")
## 草地图层（画在岛图上面，脚本不动它）
@export var grass_layer_path: NodePath
## 沙滩图层（用岛图时会清空，不再铺）
@export var beach_layer_path: NodePath
## 是否用脚本铺草地/沙滩瓦片。用岛图时关掉
@export var paint_tiles := false
## 预览用：临时隐藏 GrassLayer，单独看岛图 + 水面（调水线的时候很方便）
@export var preview_hide_grass := false
## 沙滩宽度（格）。只在 paint_tiles = true 时有用
@export var beach_tiles: float = 4.0
## 沙滩往水里多铺几格（水线会摆动，不铺这圈退潮时会露出黑缝）
@export var shore_overlap: float = 6.0
## 「浅水 → 深水」过渡跨多少格。要和 shader 的 shallow_width 一致
@export var sea_depth_tiles: float = 7.0

@export_group("海岸线遮罩")
## 手画海岸线：和岛图同构图，用纯红画一圈**闭合**的线。
## 线圈内 = 陆地，圈外 = 水体，水面的起伏不会越过这条线。留空则退回用岛图 alpha 判断。
@export_file("*.png") var shore_mask_path := "res://assets/sprites/island/shore_mask.png"

@export_group("岸型判定（崖壁 / 沙滩）")
## 崖壁遮罩（可选）：红色 = 崖壁。留空就用自动判断
@export_file("*.png") var cliff_mask_path := ""
## 遮罩向外膨胀几格（1 格 = 16px）。太小效果只有一条线，太大会淹掉沙滩
@export_range(0, 8, 1) var cliff_spread := 3.0

var _grass: TileMapLayer
var _beach: TileMapLayer
var _sprite: Sprite2D
var _island_img: Image
var _cliff_mask: Image
## 海岸线遮罩「洪水填充」后的陆地图：1 = 陆地
var _land_mask := PackedByteArray()
## 遮罩上的红线：1 = 崖壁段
var _cliff_map := PackedByteArray()
var _mask_size := Vector2i.ZERO
var _coast := FastNoiseLite.new()
var _land_cells: Array[Vector2i] = []
var _shore_count := 0
var _cliff_count := 0

## alpha 采样用的小图宽度（原图 4375 宽，缩到 512 够用、省内存）
const SAMPLE_WIDTH := 512


func _ready() -> void:
	super()
	sdf_range = sea_depth_tiles + beach_tiles + 12.0
	depth_range = 1.6
	_coast.noise_type = FastNoiseLite.TYPE_PERLIN
	_coast.fractal_type = FastNoiseLite.FRACTAL_FBM
	_coast.fractal_octaves = 3
	_coast.frequency = 0.0022
	_coast.seed = world_seed + 99
	_grass = get_node_or_null(grass_layer_path) as TileMapLayer
	_beach = get_node_or_null(beach_layer_path) as TileMapLayer
	_sprite = get_node_or_null(island_sprite_path) as Sprite2D
	_load_island_image()
	_load_shore_mask()
	_load_cliff_mask()
	_setup_layers()
	if _player == null:
		_player = get_viewport().get_camera_2d()


func _load_island_image() -> void:
	if _sprite == null or _sprite.texture == null:
		return
	var img := _sprite.texture.get_image()
	if img == null:
		return
	var w := SAMPLE_WIDTH
	var h := int(round(float(w) * img.get_height() / img.get_width()))
	img.resize(w, maxi(h, 1), Image.INTERPOLATE_BILINEAR)
	_island_img = img


func _load_cliff_mask() -> void:
	if cliff_mask_path.is_empty() or not ResourceLoader.exists(cliff_mask_path):
		return                                        # 没有遮罩就走自动判断
	var tex := load(cliff_mask_path) as Texture2D
	if tex:
		_cliff_mask = tex.get_image()


## 海岸线遮罩：一圈闭合的线，用「从四边洪水填充」把圈外找出来，
## 剩下（含线本身）就是陆地。画成什么形状都行。
##
## 线的颜色决定这一段岸的**类型**：
##   · 纯红 #FF0000 → 崖壁：水线固定不动，没有湿沙带、没有退浪
##   · 纯蓝 #0000FF → 沙滩：保留潮汐 + 浪花上岸 + 湿沙带
##   · 其他颜色 / 没画 → 按沙滩处理
func _load_shore_mask() -> void:
	if shore_mask_path.is_empty() or not ResourceLoader.exists(shore_mask_path):
		return                                        # 没遮罩就退回用岛图 alpha
	var tex := load(shore_mask_path) as Texture2D
	if tex == null:
		return
	var src := tex.get_image()
	if src == null:
		return
	var w := SAMPLE_WIDTH
	var h := int(round(float(w) * src.get_height() / src.get_width()))
	src.resize(w, maxi(h, 1), Image.INTERPOLATE_BILINEAR)
	var n := w * h

	# 1) 红线 / 蓝线都算「墙」；同时记下这一段是崖壁还是沙滩
	var wall := PackedByteArray()
	wall.resize(n)
	var cliff := PackedByteArray()
	cliff.resize(n)
	for y in h:
		for x in w:
			var c := src.get_pixel(x, y)
			var i := y * w + x
			var is_red := c.r > 0.6 and c.g < 0.25 and c.b < 0.25
			var is_blue := c.b > 0.6 and c.r < 0.3 and c.g < 0.35
			wall[i] = 1 if (is_red or is_blue) else 0
			cliff[i] = 1 if is_red else 0

	# 2) 从四条边往里灌，能灌到的就是「圈外」
	var outside := PackedByteArray()
	outside.resize(n)
	var stack: Array[int] = []
	for x in w:
		stack.append(x)
		stack.append((h - 1) * w + x)
	for y in h:
		stack.append(y * w)
		stack.append(y * w + w - 1)
	while stack.size() > 0:
		var i: int = stack.pop_back()
		if i < 0 or i >= n or outside[i] == 1 or wall[i] == 1:
			continue
		outside[i] = 1
		var x0 := i % w
		var y0 := int(i / w)
		if x0 > 0:
			stack.append(i - 1)
		if x0 < w - 1:
			stack.append(i + 1)
		if y0 > 0:
			stack.append(i - w)
		if y0 < h - 1:
			stack.append(i + w)

	# 3) 既不是墙、也没被灌到 = 圈内 = 陆地
	var land := PackedByteArray()
	land.resize(n)
	var count := 0
	for i in n:
		if outside[i] == 0:
			land[i] = 1
			count += 1
	_land_mask = land
	_cliff_map = cliff
	_mask_size = Vector2i(w, h)
	var cliff_count := 0
	for i in n:
		if cliff[i] == 1:
			cliff_count += 1
	print("[shore] 遮罩 ", _mask_size, "，陆地 %.0f%%，崖壁线 %.0f%%" % [
		100.0 * count / n, 100.0 * cliff_count / n])


## 世界坐标 → 这段岸是不是崖壁（0 沙滩 / 1 崖壁）
func _cliff_at_world(world: Vector2) -> float:
	if _cliff_map.is_empty() or _sprite == null or _sprite.texture == null:
		return 0.0
	var local := _sprite.to_local(world)
	var tex_size := Vector2(_sprite.texture.get_width(), _sprite.texture.get_height())
	var uv := local / tex_size + Vector2(0.5, 0.5)
	if uv.x < 0.0 or uv.y < 0.0 or uv.x >= 1.0 or uv.y >= 1.0:
		return 0.0
	var px := Vector2i(int(uv.x * _mask_size.x), int(uv.y * _mask_size.y))
	var idx := px.y * _mask_size.x + px.x
	return 1.0 if _cliff_map[idx] == 1 else 0.0


## 世界坐标 → 是不是陆地（优先用手画海岸线，没有就看岛图 alpha）
func _is_land_at(world: Vector2) -> bool:
	if _land_mask.is_empty() or _sprite == null or _sprite.texture == null:
		return _alpha_at_world(world) > alpha_threshold
	var local := _sprite.to_local(world)
	var tex_size := Vector2(_sprite.texture.get_width(), _sprite.texture.get_height())
	var uv := local / tex_size + Vector2(0.5, 0.5)
	if uv.x < 0.0 or uv.y < 0.0 or uv.x >= 1.0 or uv.y >= 1.0:
		return false
	var px := Vector2i(int(uv.x * _mask_size.x), int(uv.y * _mask_size.y))
	return _land_mask[px.y * _mask_size.x + px.x] == 1


# ── 高度：从岛图 alpha 来 ───────────────────────────────────────

## 世界坐标 → 岛图 alpha（0..1）。图外算 0（水）。
func _alpha_at_world(world: Vector2) -> float:
	if _island_img == null or _sprite == null:
		return 0.0
	# to_local 已经把这层的位移和缩放算进去了，得到的是「原图像素」坐标；
	# 采样图是缩小过的，所以还要按比例折算一次。
	var local := _sprite.to_local(world)
	var ratio := float(_island_img.get_width()) / float(_sprite.texture.get_width())
	var px := local * ratio + Vector2(_island_img.get_width(), _island_img.get_height()) * 0.5
	var x := int(px.x)
	var y := int(px.y)
	if x < 0 or y < 0 or x >= _island_img.get_width() or y >= _island_img.get_height():
		return 0.0
	return _island_img.get_pixel(x, y).a


## 世界坐标 → 岛图颜色（越界返回透明白）
func _color_at_world(world: Vector2) -> Color:
	if _island_img == null or _sprite == null:
		return Color(0, 0, 0, 0)
	var local := _sprite.to_local(world)
	var ratio := float(_island_img.get_width()) / float(_sprite.texture.get_width())
	var px := local * ratio + Vector2(_island_img.get_width(), _island_img.get_height()) * 0.5
	var x := int(px.x)
	var y := int(px.y)
	if x < 0 or y < 0 or x >= _island_img.get_width() or y >= _island_img.get_height():
		return Color(0, 0, 0, 0)
	return _island_img.get_pixel(x, y)


func _height_at_tile(tx: int, ty: int) -> float:
	var world := Vector2(tx * tile_size, ty * tile_size)
	var ripple := _noise_mid.get_noise_2d(world.x, world.y) * 0.04

	if _island_img != null:
		var land := _is_land_at(world)
		return (0.8 + ripple) if land else (0.2 + ripple)

	# 没图 → 程序化椭圆岛
	var p := world - island_center
	var warp := Vector2(
		_coast.get_noise_2d(world.x + 1000.0, world.y) * island_radius.x * 0.34,
		_coast.get_noise_2d(world.x, world.y + 1000.0) * island_radius.y * 0.40)
	var q := p + warp
	var r := sqrt(pow(q.x / island_radius.x, 2.0) + pow(q.y / island_radius.y, 2.0))
	var swell := _coast.get_noise_2d(world.x * 0.42 + 310.0, world.y * 0.42) \
			* coastline_amplitude
	return clampf(0.5 + (1.0 - r) * island_edge_sharpness + swell, 0.0, 1.0)


# ── 图层 ────────────────────────────────────────────────────────

func _setup_layers() -> void:
	if _beach:
		_beach.z_index = -30
		_beach.clear()                                  # 用岛图时不需要铺沙滩
	if _grass:
		_grass.z_index = -20                            # 草地压在岛图上面
		# 只在预览开关打开时「额外隐藏」，其余情况一律不动 visible ——
		# 你在场景里手动隐藏的草地必须保持隐藏，不能被脚本强行打开。
		if preview_hide_grass:
			_grass.visible = false
		if paint_tiles:
			_grass.scale = Vector2.ONE
			_grass.clear()
	_ready_beach_tileset()
	_land_cells.clear()


func _ready_beach_tileset() -> void:
	if _beach == null or _beach.tile_set != null:
		return
	var tex := load("res://assets/tilesets/sand_island.png") as Texture2D
	if tex == null:
		return
	var ts := TileSet.new()
	ts.tile_size = Vector2i(tile_size, tile_size)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(tile_size, tile_size)
	for col in 4:
		src.create_tile(Vector2i(col, 0))
	ts.add_source(src, 0)
	_beach.tile_set = ts


# ── 每跨一个区块：重烤高度图（用岛图时不铺瓦片）────────────────

func rebake(c: Vector2i) -> void:
	super(c)
	if _island_img != null:
		_bake_cliff_channel()
	if not paint_tiles:
		return
	_paint_new_chunks(last_rect)


## 岸型烘焙：沿岸一圈决定这段是「沙滩」还是「崖壁」，写进贴图的 B 通道。
##
## 两种来源，优先级从高到低：
##   1. **手画遮罩** `cliff_mask.png` —— 和岛图同构图，红 > 50% 的像素算崖壁。
##      最可靠，想精细控制就用它（拿 `cliff_mask.png` 那版初稿当底图改就行）。
##   2. 没有遮罩时退回自动判断（亮度 + 绿度），够用但不保证准。
func _bake_cliff_channel() -> void:
	if _island_img == null or _last_image == null or _texture == null or _sprite == null:
		return
	var img := _last_image
	var w := img.get_width()
	var h := img.get_height()
	var center := _sprite.global_position
	var use_mask := _cliff_mask != null
	var has_shore_cliff := not _cliff_map.is_empty()

	# 第一遍：算出每个岸边 texel 的原始崖壁值
	var raw := {}
	for y in h:
		var row := y * w
		for x in w:
			if absf(bake_dist[row + x]) > 6.0:
				continue                                   # 只处理岸边一圈
			var world := Vector2(bake_origin.x + x, bake_origin.y + y) * tile_size
			var rock := 0.0
			if has_shore_cliff:
				rock = _cliff_at_world(world)      # 海岸线遮罩里的红色段
			elif use_mask:
				rock = _mask_at_world(world)       # 单独的崖壁遮罩
			else:
				rock = _auto_rock_at(world, center)
			if rock > 0.5:
				raw[Vector2i(x, y)] = rock

	# 第二遍：向外膨胀 cliff_spread 格。
	# 遮罩是沿着水线画的一条细线，而贴图是「1 texel = 1 格(16px)」，
	# 不膨胀的话效果只剩 16px 宽的一条，根本看不出来。
	var spread := int(round(cliff_spread))
	var dilated := {}
	for cell in raw:
		for dy in range(-spread, spread + 1):
			for dx in range(-spread, spread + 1):
				if dx * dx + dy * dy > spread * spread:
					continue
				var k := Vector2i(cell.x + dx, cell.y + dy)
				var idx := k.y * w + k.x
				if k.x < 0 or k.y < 0 or k.x >= w or k.y >= h:
					continue
				if absf(bake_dist[idx]) > 7.0:
					continue
				dilated[k] = maxf(dilated.get(k, 0.0), raw[cell])

	# 第三遍：写回 B 通道
	for y in h:
		var row := y * w
		for x in w:
			if absf(bake_dist[row + x]) > 6.0:
				continue
			var rock: float = dilated.get(Vector2i(x, y), 0.0)
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(c.r, c.g, clampf(rock, 0.0, 1.0), c.a))
			_shore_count += 1
			if rock > 0.5:
				_cliff_count += 1
	_texture.update(img)



## 手画遮罩：按归一化 UV 取，和岛图同构图就行，尺寸随意
func _mask_at_world(world: Vector2) -> float:
	if _cliff_mask == null or _sprite == null or _sprite.texture == null:
		return 0.0
	var local := _sprite.to_local(world)
	var tex_size := Vector2(_sprite.texture.get_width(), _sprite.texture.get_height())
	var uv := local / tex_size + Vector2(0.5, 0.5)
	if uv.x < 0.0 or uv.y < 0.0 or uv.x >= 1.0 or uv.y >= 1.0:
		return 0.0
	var px := Vector2i(int(uv.x * _cliff_mask.get_width()),
			int(uv.y * _cliff_mask.get_height()))
	# 「纯红」判定：R 高 + G/B 都低。
	# 这样你可以直接拿岛图当底图去涂红 —— 沙色 (0.99,0.89,0.64)、
	# 草色 (0.67,0.84,0.13) 的 G 都很高，不会被误判成崖壁。
	var c := _cliff_mask.get_pixel(px.x, px.y)
	return 1.0 if (c.r > 0.6 and c.g < 0.25 and c.b < 0.25) else 0.0


## 没画崖壁遮罩时：一律当沙滩（返回 0）。
## 之前的自动判断会被岛图自带的深色描边骗到，把整圈海岸判成崖壁，
## 所以干脆关掉 —— 想要崖壁效果，画一张 cliff_mask.png 就好。
func _auto_rock_at(_world: Vector2, _center: Vector2) -> float:
	return 0.0


func _paint_new_chunks(rect: Rect2i) -> void:
	if _beach == null:
		return
	var cols := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	var ct := chunk_tiles
	var cc0 := _chunk_of_tile(rect.position)
	var cc1 := _chunk_of_tile(rect.end - Vector2i.ONE)
	for cy in range(cc0.y, cc1.y + 1):
		for cx in range(cc0.x, cc1.x + 1):
			var key := Vector2i(cx, cy)
			if _tiles_done.has(key):
				continue
			_tiles_done[key] = true
			var base := key * ct
			for ty in ct:
				for tx in ct:
					var cell := base + Vector2i(tx, ty)
					var d := dist_at_tile(cell)
					if d > shore_overlap:
						continue
					if -d <= beach_tiles:
						_beach.set_cell(cell, 0, cols[absi(hash(cell)) % 4])
					elif _grass:
						_land_cells.append(cell)
	if _grass == null or _land_cells.is_empty():
		return
	for cell in _land_cells:
		_grass.set_cell(cell, 0, Vector2i(1, 1))
