@tool
class_name IslandTerrain
extends TerrainField
## 水体场景：(只做水，不造陆地)
##
## 分工（改之前先看这段）：
##   · **草地**：完全用你原来的 `GrassLayer`。这个脚本**只读**它，不 clear、不铺、不动 z_index。
##     岛是什么形状，就看你草地画成什么形状。
##   · **沙滩**：脚本在最底层（z = -30）铺满一整片沙，平时被草地盖住，
##     只在草地外面那圈露出来，就是沙滩。
##   · **海水**：`SeaCanvas` 那层四边形。水面从「草地边缘往外 `beach_tiles` 格」开始，
##     所以草地和海水之间自然留出一圈沙滩。
##
## 海岸线怎么来的：草地有格子的地方算陆地、没格子算水，
## 再走一遍「高度 → 水陆蒙版 → 倒角距离场」的烘焙。
## 改完草地形状后，拨一下 `regenerate_now` 重算（只影响沙滩层和高度图，不碰草地）。
##
## ⚠️ 编辑器里**默认什么都不做**。之前加了自动生成，结果 tool 脚本把生成结果
##    写进了 level.tscn，把手工摆的草地和农田覆盖掉了。现在只有你手动拨
##    `regenerate_now` 才会动。

@export_group("生成")
## 拨一下 = 按当前草地形状重算一次（编辑器里当按钮用）。只改沙滩层，不动草地。
@export var regenerate_now := false:
	set(value):
		regenerate_now = false
		if value:
			_setup_layers()
			_regenerate()

@export_group("图层")
## 你的草地层（脚本只读它）
@export var grass_layer_path: NodePath
## 沙滩层（最底层，脚本会铺满）
@export var beach_layer_path: NodePath
## 草地边缘到水面之间留几格沙滩。改这个要同步颜色的 shore_offset（= 这个值）。
@export var beach_tiles: float = 4.5
## 「浅水 → 深水」的过渡跨多少格。改这个要同步材质的 shallow_width。
@export var sea_depth_tiles: float = 6.0

var _grass: TileMapLayer
var _beach: TileMapLayer
var _written := false


func _ready() -> void:
	super()
	sdf_range = sea_depth_tiles + beach_tiles + 12.0
	depth_range = 4.0          # 关闭「按高度算水深」，统一按到岸距离算
	_grass = get_node_or_null(grass_layer_path) as TileMapLayer
	_beach = get_node_or_null(beach_layer_path) as TileMapLayer

	if Engine.is_editor_hint():
		return                 # 编辑器里绝不自动动场景

	_setup_layers()
	if _player == null:
		_player = get_viewport().get_camera_2d()
	if _player == null:
		_regenerate()


func _regenerate() -> void:
	_chunks.clear()
	_tiles_done.clear()
	_written = false
	_last_chunk = Vector2i(999999, 999999)
	bake_center = _grass_bounds_center()
	rebake(_player_chunk())


func _grass_bounds_center() -> Vector2:
	if _grass == null:
		return Vector2.ZERO
	var r := _grass.get_used_rect()
	if r.size == Vector2i.ZERO:
		return Vector2.ZERO
	return Vector2(r.get_center()) * tile_size


# ── 高度：只用来区分「草地」和「非草地」────────────────────────

func _height_at_tile(tx: int, ty: int) -> float:
	if _grass == null:
		return 0.2
	# 草地层可能被非等比缩放过（你原来是 0.945 x 0.854）。把「世界格坐标」
	# 换算回它的 cell 坐标，否则水线会和你看到的地面错开一大截。
	var sc := _grass.scale
	var cell := Vector2i(
		floori(float(tx) / sc.x) if sc.x != 0.0 else tx,
		floori(float(ty) / sc.y) if sc.y != 0.0 else ty)
	var has_grass := _grass.get_cell_source_id(cell) != -1
	# 加一点点噪声，别让水线正好卡在瓦片边上；大起伏交给 shader 的 edge_wobble
	var ripple := _noise_mid.get_noise_2d(tx * tile_size, ty * tile_size) * 0.04
	return (0.8 + ripple) if has_grass else (0.2 + ripple)


# ── 图层 ────────────────────────────────────────────────────────

func _setup_layers() -> void:
	if _beach == null:
		return
	_beach.z_index = -30       # 沙滩压在最底下，草地和海水都在它上面
	_ready_beach_tileset()


func _ready_beach_tileset() -> void:
	if _beach.tile_set != null:      # 你已经手动配过就别覆盖
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


# ── 烘焙完 → 铺满沙滩 ───────────────────────────────────────────

func rebake(c: Vector2i) -> void:
	super(c)
	if _written:
		return
	_written = true
	_paint_sand(last_rect)


func _paint_sand(rect: Rect2i) -> void:
	if _beach == null:
		return
	_beach.clear()
	var cols := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	for ty in range(rect.position.y, rect.end.y):
		for tx in range(rect.position.x, rect.end.x):
			var cell := Vector2i(tx, ty)
			_beach.set_cell(cell, 0, cols[absi(hash(cell)) % 4])
	if Engine.is_editor_hint():
		print("[water] 沙滩铺满 %d 格（Ctrl+S 保存）" % _beach.get_used_cells().size())
