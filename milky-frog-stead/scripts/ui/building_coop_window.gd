extends "res://scripts/ui/building_window_base.gd"
## 鸡舍建筑独立页面（星露谷式鸡舍内部）。
##
## 场景不再是一块绿色网格 + 几张图标，而是「木墙 + 木地板」的室内：
##   上方 34% 是木板墙（小窗），下方 66% 是鸡活动 / 食槽所在的木地板；
##   鸡蛋由小鸡自己走到指定地板位置、蹲下之后掉在脚边（不会在固定槽里凭空生成）。
## 数值仍全部在 CoopState autoload 里，本页只画场景 + 把点击转成数据操作。
## 窗口打开时 CoopState.ui_active = true，由本页 _process 驱动鸡走到食槽进食；
## 窗口关闭后交还数据层自动进食，保证关掉建筑界面时蛋也在慢慢产出。

const CHICKEN_SCENE := preload("res://scenes/chicken/chicken.tscn")
const CHICKEN_SHEET := preload("res://assets/sprites/chickens/chicken_all_left.png")
const GRASS_TUFT := preload("res://assets/sprites/decorations/grass_tuft.png")

# ---------------- 场景尺寸 ----------------
const CHICKEN_SLOTS: int = 6
const EGG_BUTTON_COUNT: int = 6
const EGG_BUTTON_SIZE := Vector2(38.0, 38.0)
const EGG_ICON_MAX_WIDTH: int = 34
## 上方木板墙占场景高度的比例
const WALL_RATIO: float = 0.34
## 木板墙竖缝数量：场景宽约 900 时每 33px 一条，落在 28~36px 的区间里
const WALL_SEAMS: int = 26
const FLOOR_SEAMS: int = 11
const ARENA_MIN_HEIGHT: float = 520.0
const SIDE_PANEL_WIDTH: float = 340.0

# ---------------- 小鸡 ----------------
## 帧图是 128x128，但小鸡美术只占中间约 48x53 像素；
## 0.92 时视觉高度约 49px，和鸡蛋（36px）比例合适（旧版 0.68 明显偏小）。
const CHICKEN_SCALE: float = 0.98
## 帧内脚底在 y≈84、帧中心 64：-20 让节点原点落回脚底，站姿和影子都用脚底坐标
const CHICKEN_ART_OFFSET := Vector2(0.0, -20.0)
const CHICKEN_SHADOW_SIZE := Vector2(57.0, 18.0)
const CHICKEN_SPEED_MIN: float = 38.0
const CHICKEN_SPEED_MAX: float = 56.0
const EAT_SECONDS: float = 2.0
const ARRIVE_DISTANCE: float = 26.0
## 小鸡活动区：距墙脚留 74px、距场景底边留 26px，脚底坐标
const WALK_TOP_PADDING: float = 74.0
const WALK_BOTTOM_PADDING: float = 26.0
const WALK_SIDE_MARGIN: float = 48.0

# ---------------- 场景配色 ----------------
const WALL_BASE := Color("66492b")
const WALL_SEAM := Color("452f18")
const WALL_TOP := Color("2f2110")
const FLOOR_BASE := Color("9a7245")
const FLOOR_SEAM := Color("6b4a28")
const FLOOR_GRAIN := Color(0.22, 0.13, 0.05, 0.20)
const BASEBOARD := Color("4a3419")
const STRAW := Color("d9b64e")
const STRAW_DARK := Color("a9842f")
const WATER := Color("6fa7c4")
const SHADOW_BG := Color(0.10, 0.06, 0.02, 0.30)

# ---------------- 场景布局（比例坐标，窗口缩放时自动跟随） ----------------
## 6 个可以落蛋的木地板位置（比例坐标）：鸡会走到这里蹲下，蛋掉在脚边。
## 避开左下角食槽和小水盆，尽量铺开在鸡舍中间偏右。
const EGG_FLOOR_SPOTS := [
	Vector2(0.40, 0.56),
	Vector2(0.55, 0.53),
	Vector2(0.70, 0.60),
	Vector2(0.46, 0.80),
	Vector2(0.62, 0.86),
	Vector2(0.78, 0.76),
]
## 地板上的木纹，让木地板不至于平得像纯色色块
const FLOOR_GRAIN_RECTS := [
	Rect2(0.10, 0.47, 0.09, 0.005),
	Rect2(0.55, 0.53, 0.12, 0.005),
	Rect2(0.30, 0.63, 0.07, 0.005),
	Rect2(0.72, 0.72, 0.10, 0.005),
	Rect2(0.18, 0.84, 0.08, 0.005),
	Rect2(0.60, 0.90, 0.11, 0.005),
]
## 散落在地上的草屑
const STRAW_BITS := [
	Rect2(0.12, 0.56, 0.020, 0.006),
	Rect2(0.24, 0.68, 0.016, 0.006),
	Rect2(0.40, 0.60, 0.022, 0.007),
	Rect2(0.52, 0.78, 0.018, 0.006),
	Rect2(0.66, 0.64, 0.021, 0.006),
	Rect2(0.78, 0.86, 0.016, 0.006),
	Rect2(0.36, 0.92, 0.020, 0.006),
	Rect2(0.88, 0.70, 0.018, 0.006),
]
## 地板上的稻草簇：x, y, 像素尺寸, 旋转弧度
const FLOOR_TUFTS := [
	[0.09, 0.53, 46.0, -0.30],
	[0.20, 0.70, 40.0, 0.18],
	[0.30, 0.88, 50.0, -0.10],
	[0.43, 0.64, 44.0, 0.26],
	[0.56, 0.84, 46.0, -0.22],
	[0.65, 0.56, 38.0, 0.12],
	[0.78, 0.72, 46.0, -0.16],
	[0.88, 0.60, 38.0, 0.24],
	# 右下角堆一小垛干草，让角落不空
	[0.90, 0.88, 64.0, -0.08],
	[0.95, 0.84, 52.0, 0.16],
	[0.86, 0.93, 56.0, 0.10],
]

# 鸡的行走模式。只影响画面，饥饿 / 产蛋数值由 CoopState 决定。
const MODE_WANDER: int = 0
const MODE_SEEK: int = 1
const MODE_EAT: int = 2
const MODE_IDLE: int = 3
const MODE_TO_SPOT: int = 4
const MODE_LAY: int = 5
## 走到下蛋点、蹲下到蛋出现的时间
const LAY_SECONDS: float = 1.8


## 一只鸡的界面状态：把「画面上怎么走」和 CoopState 里的数值解耦。
## pos 是脚底坐标（和精灵 offset 对齐），影子 / 站位都直接用它。
class ChickenView:
	var sprite: AnimatedSprite2D = null
	var shadow: Panel = null
	var pos: Vector2 = Vector2.ZERO
	var target: Vector2 = Vector2.ZERO
	var speed: float = 46.0
	var facing: int = 1
	var mode: int = 0
	var timer: float = 0.0
	var lay_slot: int = -1


var _arena: Control = null
var _trough_button: Button = null
var _trough_label: Label = null
var _egg_buttons: Array[Button] = []
var _egg_shadows: Array[Panel] = []
var _chicken_frames: SpriteFrames = null
var _chickens: Array = []
var _chickens_initialized: bool = false
## 同一时间只让一只鸡去下蛋，避免两只鸡抢位置 / 蛋位顺序错乱
var _laying_chicken: int = -1
var _laying_slot: int = -1

# 右侧状态面板
var _chicken_name_labels: Array[Label] = []
var _chicken_state_labels: Array[Label] = []
var _chicken_hunger_bars: Array = []
var _chicken_lay_bars: Array = []
var _chicken_card_panels: Array[PanelContainer] = []
var _chicken_count_label: Label = null
var _trough_stock_label: Label = null
var _wheat_label: Label = null
var _fill_button: Button = null
var _ground_eggs_label: Label = null
var _collected_label: Label = null
var _collect_button: Button = null


# ---------------- 基类接口 ----------------

func page_title() -> String:
	return "鸡舍"


func page_hint() -> String:
	return "点食槽投喂 · 鸡饿了自己来吃 · 点木地板上的蛋收进仓库 · Esc 返回建筑"


func _build_body(parent: VBoxContainer) -> void:
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 18)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(main)

	_build_arena(main)
	_build_side_panel(main)

	# 数据层任何变化（投喂 / 吃食 / 产蛋 / 收蛋）都刷新右侧数字和地板上的蛋
	CoopState.changed.connect(_refresh)
	_refresh()


# ---------------- 左边：鸡舍内部场景 ----------------

func _build_arena(main: HBoxContainer) -> void:
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	main.add_child(left)

	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UI.dark_style(Color("2f2110")))
	left.add_child(panel)

	_arena = Control.new()
	_arena.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_arena.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_arena.custom_minimum_size = Vector2(0.0, ARENA_MIN_HEIGHT)
	_arena.clip_contents = true
	panel.add_child(_arena)

	_build_coop_room()
	_build_egg_field()
	_build_trough()
	_build_water_bowl()
	_build_floor_decor()

	_chicken_frames = _load_chicken_frames()
	for index in range(CHICKEN_SLOTS):
		_build_chicken(index)

	# 暗角放最后压住整块场景增加纵深；mouse_filter=IGNORE 所以不挡食槽 / 蛋的点击
	var vignette := UI.vignette(0.30)
	vignette.z_index = 10
	_arena.add_child(vignette)

	left.add_child(UI.wrapped_label(
		"小鸡只在木地板上活动，饿了会走到左下角食槽；下蛋时会自己找块地板蹲下，蛋掉在脚边，点一下收进仓库。", 13))


## 木板墙 + 木地板 + 踢脚线 + 小窗，全部用色块拼，不依赖草地 / 泥地贴图
func _build_coop_room() -> void:
	# 1) 木板墙：底色 + 深色竖缝
	_add_rect(_arena, WALL_BASE, Rect2(0.0, 0.0, 1.0, WALL_RATIO))
	for index in range(WALL_SEAMS + 1):
		# 每块木板明暗交替，比单色墙更像真木板
		var left := float(index) / float(WALL_SEAMS + 1)
		var width := 1.0 / float(WALL_SEAMS + 1)
		if index % 2 == 0:
			_add_rect(_arena, Color(1.0, 0.90, 0.70, 0.035),
				Rect2(left, 0.014, width, WALL_RATIO - 0.014))
	for index in range(WALL_SEAMS):
		var x := float(index + 1) / float(WALL_SEAMS + 1)
		_add_vline(_arena, x, 3.0, 0.0, WALL_RATIO, WALL_SEAM)
	# 墙顶压条和腰线，让墙有厚度
	_add_rect(_arena, WALL_TOP, Rect2(0.0, 0.0, 1.0, 0.014))
	_add_hline(_arena, 0.150, 2.0, 0.0, 1.0, Color(0.0, 0.0, 0.0, 0.18))
	_add_hline(_arena, 0.154, 1.0, 0.0, 1.0, Color(1.0, 0.9, 0.7, 0.12))

	# 2) 木地板：底色 + 明暗交替的板条 + 横向木缝 + 木纹
	_add_rect(_arena, FLOOR_BASE, Rect2(0.0, WALL_RATIO, 1.0, 1.0 - WALL_RATIO))
	var plank_height := (1.0 - WALL_RATIO) / float(FLOOR_SEAMS + 1)
	for index in range(FLOOR_SEAMS + 1):
		var top := WALL_RATIO + float(index) * plank_height
		var tint := Color(1.0, 0.94, 0.78, 0.035) if index % 2 == 0 else Color(0.16, 0.09, 0.03, 0.055)
		_add_rect(_arena, tint, Rect2(0.0, top, 1.0, plank_height))
	for index in range(FLOOR_SEAMS):
		var y := WALL_RATIO + float(index + 1) * plank_height
		_add_hline(_arena, y, 2.0, 0.0, 1.0, FLOOR_SEAM)
	for grain in FLOOR_GRAIN_RECTS:
		_add_rect(_arena, FLOOR_GRAIN, grain)

	# 3) 踢脚线：墙和地板的交界，给场景一条明确的“地平线”
	_add_rect(_arena, BASEBOARD, Rect2(0.0, WALL_RATIO - 0.010, 1.0, 0.021))
	_add_hline(_arena, WALL_RATIO - 0.010, 2.0, 0.0, 1.0, Color(0.86, 0.70, 0.44, 0.50))
	_add_hline(_arena, WALL_RATIO + 0.011, 2.0, 0.0, 1.0, Color(0.0, 0.0, 0.0, 0.35))

	_build_window()


## 墙上的小窗：浅蓝天空 + 十字木框 + 窗台，给室内一点生活感
func _build_window() -> void:
	var frame := Panel.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.z_index = 1
	frame.add_theme_stylebox_override("panel", _window_style())
	_arena.add_child(frame)
	_apply_anchor_rect(frame, Rect2(0.022, 0.020, 0.098, 0.245))

	var sky := Panel.new()
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky.add_theme_stylebox_override("panel", _inner_style(Color("9cc9d8"), Color("4d6f7a")))
	frame.add_child(sky)
	_apply_anchor_rect(sky, Rect2(0.12, 0.09, 0.76, 0.82))

	# 天空上浅下深 + 太阳 + 两朵云
	_add_rect(sky, Color(0.85, 0.94, 1.0, 0.55), Rect2(0.0, 0.0, 1.0, 0.40))
	_add_rect(sky, Color(1.0, 0.96, 0.80, 0.95), Rect2(0.60, 0.12, 0.20, 0.20))
	_add_rect(sky, Color(1.0, 1.0, 1.0, 0.55), Rect2(0.10, 0.30, 0.32, 0.10))
	_add_rect(sky, Color(1.0, 1.0, 1.0, 0.40), Rect2(0.42, 0.50, 0.42, 0.09))
	# 十字窗框
	_add_vline(sky, 0.5, 5.0, 0.0, 1.0, UI.WOOD_LIGHT)
	_add_hline(sky, 0.5, 5.0, 0.0, 1.0, UI.WOOD_LIGHT)

	# 窗台
	_add_rect(_arena, UI.WOOD, Rect2(0.012, 0.258, 0.118, 0.011), 1)
	_add_hline(_arena, 0.268, 2.0, 0.012, 0.130, Color(0.0, 0.0, 0.0, 0.35))


## 地板上 6 个落蛋点：蛋只出现在这些位置，且必须由鸡走过去蹲下后才出现
func _build_egg_field() -> void:
	for index in range(EGG_BUTTON_COUNT):
		# 地板上的小影子：让蛋看起来是放在木地板上，而不是浮在画面里
		var shadow := Panel.new()
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shadow.add_theme_stylebox_override("panel", _egg_shadow_style())
		shadow.z_index = 1
		_arena.add_child(shadow)
		_place_egg_shadow(shadow, index)
		_egg_shadows.append(shadow)

		var button := _create_egg_button(index)
		_arena.add_child(button)
		_place_egg_on_floor(button, index)


func _place_egg_on_floor(button: Button, index: int) -> void:
	var spot: Vector2 = EGG_FLOOR_SPOTS[index % EGG_FLOOR_SPOTS.size()]
	button.anchor_left = spot.x
	button.anchor_right = spot.x
	button.anchor_top = spot.y
	button.anchor_bottom = spot.y
	button.offset_left = -EGG_BUTTON_SIZE.x * 0.5
	button.offset_right = EGG_BUTTON_SIZE.x * 0.5
	button.offset_top = -EGG_BUTTON_SIZE.y * 0.5
	button.offset_bottom = EGG_BUTTON_SIZE.y * 0.5
	button.pivot_offset = EGG_BUTTON_SIZE * 0.5
	button.z_index = 2


func _place_egg_shadow(shadow: Panel, index: int) -> void:
	var spot: Vector2 = EGG_FLOOR_SPOTS[index % EGG_FLOOR_SPOTS.size()]
	shadow.anchor_left = spot.x
	shadow.anchor_right = spot.x
	shadow.anchor_top = spot.y
	shadow.anchor_bottom = spot.y
	shadow.offset_left = -17.0
	shadow.offset_right = 17.0
	shadow.offset_top = 10.0
	shadow.offset_bottom = 18.0


func _egg_shadow_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.07, 0.03, 0.22)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(0)
	return style


## 第 index 个落蛋点在地板上的像素坐标
func _egg_floor_point(index: int) -> Vector2:
	var spot: Vector2 = EGG_FLOOR_SPOTS[clampi(index, 0, EGG_FLOOR_SPOTS.size() - 1)]
	return Vector2(spot.x * _arena.size.x, spot.y * _arena.size.y)


func _create_egg_button(index: int) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.flat = true
	button.icon = ItemDB.icon(CoopState.EGG_ITEM_ID)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", EGG_ICON_MAX_WIDTH)
	button.tooltip_text = "点击把这枚鸡蛋收进仓库"
	button.visible = false
	button.z_index = 2
	# flat Button 默认样式会带来额外内边距，撑大 36px 蛋位；换成空样式并自己画 hover
	var empty := StyleBoxEmpty.new()
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1.0, 0.95, 0.75, 0.16)
	hover.set_corner_radius_all(10)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(1.0, 0.90, 0.55, 0.26)
	pressed.set_corner_radius_all(10)
	button.add_theme_stylebox_override("normal", empty)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", empty)
	button.pressed.connect(press_collect_egg_at.bind(index))
	_egg_buttons.append(button)
	return button


## 左下角木质食槽：点击 = 从仓库倒 3 份小麦进食槽
func _build_trough() -> void:
	_trough_button = Button.new()
	_trough_button.focus_mode = Control.FOCUS_NONE
	_trough_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_trough_button.tooltip_text = "点击从仓库倒 3 份小麦饲料进食槽"
	_trough_button.add_theme_stylebox_override("normal", _trough_style(UI.WOOD, false))
	_trough_button.add_theme_stylebox_override("hover", _trough_style(UI.WOOD_LIGHT, false))
	_trough_button.add_theme_stylebox_override("pressed", _trough_style(UI.WOOD_DARK, true))
	_trough_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_trough_button.z_index = 6
	_trough_button.pressed.connect(press_trough)
	_arena.add_child(_trough_button)
	_trough_button.anchor_left = 0.035
	_trough_button.anchor_right = 0.30
	_trough_button.anchor_top = 1.0
	_trough_button.anchor_bottom = 1.0
	_trough_button.offset_left = 0.0
	_trough_button.offset_right = 0.0
	_trough_button.offset_top = -98.0
	_trough_button.offset_bottom = -26.0

	# 顶部木沿高光
	_add_rect(_trough_button, Color(1.0, 0.92, 0.70, 0.22), Rect2(0.03, 0.05, 0.94, 0.035))

	# 深色槽口
	var cavity := Panel.new()
	cavity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cavity.add_theme_stylebox_override("panel", _inner_style(Color("2e1d0c"), Color("160d04"), 2, 8))
	_trough_button.add_child(cavity)
	_apply_anchor_rect(cavity, Rect2(0.05, 0.52, 0.90, 0.38))

	# 槽口里的小麦
	var wheat_icon := TextureRect.new()
	wheat_icon.texture = ItemDB.icon(CoopState.FEED_ITEM_ID)
	wheat_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wheat_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	wheat_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	wheat_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trough_button.add_child(wheat_icon)
	wheat_icon.anchor_left = 0.13
	wheat_icon.anchor_right = 0.13
	wheat_icon.anchor_top = 0.72
	wheat_icon.anchor_bottom = 0.72
	wheat_icon.offset_left = -20.0
	wheat_icon.offset_right = 20.0
	wheat_icon.offset_top = -18.0
	wheat_icon.offset_bottom = 18.0

	# 饲料数量
	_trough_label = UI.label("饲料 0/9", 18, UI.TEXT_LIGHT)
	_trough_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_trough_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_trough_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trough_button.add_child(_trough_label)
	_apply_anchor_rect(_trough_label, Rect2(0.10, 0.08, 0.86, 0.40))
	var hint := UI.label("点击投喂", 12, Color(1.0, 0.95, 0.82, 0.9))
	hint.add_theme_color_override("font_outline_color", Color(0.16, 0.10, 0.04, 0.9))
	hint.add_theme_constant_override("outline_size", 2)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trough_button.add_child(hint)
	_apply_anchor_rect(hint, Rect2(0.10, 0.44, 0.86, 0.16))


## 食槽旁边的小水盆，纯装饰（鸡不用喝水，只是让角落不空）
func _build_water_bowl() -> void:
	var bowl := Panel.new()
	bowl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bowl.z_index = 5
	bowl.add_theme_stylebox_override("panel", _inner_style(UI.WOOD_LIGHT, UI.WOOD_DARK, 3, 10))
	_arena.add_child(bowl)
	bowl.anchor_left = 0.318
	bowl.anchor_right = 0.378
	bowl.anchor_top = 1.0
	bowl.anchor_bottom = 1.0
	bowl.offset_left = 0.0
	bowl.offset_right = 0.0
	bowl.offset_top = -66.0
	bowl.offset_bottom = -30.0

	var water := Panel.new()
	water.mouse_filter = Control.MOUSE_FILTER_IGNORE
	water.add_theme_stylebox_override("panel", _inner_style(WATER, Color("3f6f8a"), 2, 8))
	bowl.add_child(water)
	_apply_anchor_rect(water, Rect2(0.14, 0.24, 0.72, 0.62))


## 地板上的稻草簇 / 草屑，去掉「绿色网格摆图标」的塑料感
func _build_floor_decor() -> void:
	for tuft_info in FLOOR_TUFTS:
		_add_floor_tuft(
			float(tuft_info[0]), float(tuft_info[1]),
			float(tuft_info[2]), float(tuft_info[3]))
	for bit in STRAW_BITS:
		var straw := _add_rect(_arena, STRAW_DARK, bit, 1)
		straw.rotation = randf_range(-0.35, 0.35)


func _add_floor_tuft(x_ratio: float, y_ratio: float, size_px: float, angle: float) -> void:
	var tuft := TextureRect.new()
	tuft.texture = GRASS_TUFT
	tuft.modulate = Color("e8c95f")
	tuft.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tuft.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tuft.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tuft.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tuft.z_index = 1
	_arena.add_child(tuft)
	tuft.anchor_left = x_ratio
	tuft.anchor_right = x_ratio
	tuft.anchor_top = y_ratio
	tuft.anchor_bottom = y_ratio
	tuft.offset_left = -size_px * 0.5
	tuft.offset_right = size_px * 0.5
	tuft.offset_top = -size_px * 0.5
	tuft.offset_bottom = size_px * 0.5
	tuft.pivot_offset = Vector2(size_px, size_px) * 0.5
	tuft.rotation = angle


# ---------------- 场景工具 ----------------

## 用比例锚点把控件摆到场景里（窗口缩放时自动跟随）
func _apply_anchor_rect(control: Control, ratio: Rect2) -> void:
	control.anchor_left = ratio.position.x
	control.anchor_right = ratio.position.x + ratio.size.x
	control.anchor_top = ratio.position.y
	control.anchor_bottom = ratio.position.y + ratio.size.y
	control.offset_left = 0.0
	control.offset_right = 0.0
	control.offset_top = 0.0
	control.offset_bottom = 0.0


func _add_rect(parent: Control, color: Color, ratio: Rect2, layer: int = 0) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.z_index = layer
	parent.add_child(rect)
	_apply_anchor_rect(rect, ratio)
	return rect


func _add_vline(parent: Control, x_ratio: float, width: float, top_ratio: float,
		bottom_ratio: float, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	rect.anchor_left = x_ratio
	rect.anchor_right = x_ratio
	rect.anchor_top = top_ratio
	rect.anchor_bottom = bottom_ratio
	rect.offset_left = -width * 0.5
	rect.offset_right = width * 0.5
	rect.offset_top = 0.0
	rect.offset_bottom = 0.0
	return rect


func _add_hline(parent: Control, y_ratio: float, height: float, left_ratio: float,
		right_ratio: float, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	rect.anchor_left = left_ratio
	rect.anchor_right = right_ratio
	rect.anchor_top = y_ratio
	rect.anchor_bottom = y_ratio
	rect.offset_left = 0.0
	rect.offset_right = 0.0
	rect.offset_top = -height * 0.5
	rect.offset_bottom = height * 0.5
	return rect


func _inner_style(bg: Color, border: Color, border_width: int = 2, radius: int = 3) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(0)
	return style


func _window_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI.WOOD_LIGHT
	style.border_color = UI.WOOD_DARK
	style.set_border_width_all(4)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(0)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.30)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 3)
	return style


func _trough_style(bg: Color, pressed: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = UI.WOOD_DARK
	style.set_border_width_all(3)
	style.set_corner_radius_all(7)
	style.set_content_margin_all(4)
	style.shadow_color = Color(0.08, 0.05, 0.02, 0.35)
	style.shadow_size = 0 if pressed else 4
	style.shadow_offset = Vector2.ZERO if pressed else Vector2(0, 4)
	return style


func _chicken_shadow_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = SHADOW_BG
	style.set_corner_radius_all(8)
	style.set_content_margin_all(0)
	return style


# ---------------- 小鸡 ----------------

## 直接从 chicken.tscn 里取调好的 SpriteFrames，动画名和帧布局不用在 UI 里重拼。
## 临时实例化只为了拿资源，取完立刻 free，不进场景树就不会跑小鸡自己的脚本逻辑。
func _load_chicken_frames() -> SpriteFrames:
	var temp := CHICKEN_SCENE.instantiate()
	var animated := temp.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	var frames: SpriteFrames = null
	if animated != null:
		frames = animated.sprite_frames
	temp.free()
	return frames


func _build_chicken(index: int) -> void:
	# 脚下影子：深色半透明圆角 Panel，跟着脚底坐标走
	var shadow := Panel.new()
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.add_theme_stylebox_override("panel", _chicken_shadow_style())
	shadow.z_index = 2
	shadow.visible = false
	_arena.add_child(shadow)
	shadow.size = CHICKEN_SHADOW_SIZE

	var sprite := AnimatedSprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(CHICKEN_SCALE, CHICKEN_SCALE)
	sprite.offset = CHICKEN_ART_OFFSET
	sprite.z_index = 3
	# 先藏起来：等场景排版完成、_ensure_chickens_ready 摆好位置再显示，
	# 否则打开窗口的第一帧会看到 3 只鸡挤在左上角
	sprite.visible = false
	if _chicken_frames != null:
		sprite.sprite_frames = _chicken_frames
		sprite.play("idle_left")
	_arena.add_child(sprite)

	var view := ChickenView.new()
	view.sprite = sprite
	view.shadow = shadow
	view.speed = randf_range(CHICKEN_SPEED_MIN, CHICKEN_SPEED_MAX)
	view.facing = -1 if index % 2 == 0 else 1
	_chickens.append(view)


## 右侧卡片的鸡头像：从鸡贴图里切一帧，idle / move / eat 各取一帧，三只不重样
func _chicken_avatar(index: int) -> AtlasTexture:
	var row_offsets := [0.0, 256.0, 128.0]
	var atlas := AtlasTexture.new()
	atlas.atlas = CHICKEN_SHEET
	atlas.region = Rect2(32.0, float(row_offsets[index % row_offsets.size()]) + 26.0, 64.0, 64.0)
	return atlas


# ---------------- 右边：状态面板 ----------------

func _build_side_panel(main: HBoxContainer) -> void:
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = SIDE_PANEL_WIDTH
	right.add_theme_constant_override("separation", 8)
	main.add_child(right)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	right.add_child(title_row)
	title_row.add_child(UI.title_label("鸡舍状态", 22))
	var title_spacer := Control.new()
	title_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_spacer)
	var count_chip := UI.chip("%d 只小鸡" % CoopState.chickens.size(), UI.GREEN, 12)
	title_row.add_child(count_chip)
	_chicken_count_label = count_chip.get_child(0) as Label

	# 最多 6 只鸡的卡片放进滚动区，买满也不会把旁边的食槽/鸡蛋卡挤爆
	var chicken_scroll := ScrollContainer.new()
	chicken_scroll.custom_minimum_size = Vector2(0, 258)
	chicken_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chicken_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(chicken_scroll)
	var chicken_list := VBoxContainer.new()
	chicken_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chicken_list.add_theme_constant_override("separation", 6)
	chicken_scroll.add_child(chicken_list)
	for index in range(CHICKEN_SLOTS):
		_chicken_card_panels.append(_build_chicken_card(chicken_list, index))

	# 食槽
	var feed_card := _make_card(right)
	var feed_header := HBoxContainer.new()
	feed_header.add_theme_constant_override("separation", 8)
	feed_card.add_child(feed_header)
	feed_header.add_child(UI.label("食槽", 18, UI.INK))
	var feed_spacer := Control.new()
	feed_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feed_header.add_child(feed_spacer)
	_trough_stock_label = UI.label("", 15, UI.INK)
	feed_header.add_child(_trough_stock_label)
	_wheat_label = UI.wrapped_label("", 13)
	feed_card.add_child(_wheat_label)
	_fill_button = UI.primary_button("投喂 3 份", 15, 40)
	_fill_button.pressed.connect(press_trough)
	feed_card.add_child(_fill_button)
	# 仅编辑器调试运行可见：方便测试/演示时快速补小麦，正式导出不会出现
	if OS.is_debug_build():
		var debug_gift := UI.ghost_button("调试补给：小麦 +10", 12, 28)
		debug_gift.tooltip_text = "仅编辑器调试运行可见；正式导出不会出现"
		debug_gift.pressed.connect(_debug_gift_wheat)
		feed_card.add_child(debug_gift)

	# 地板上的蛋
	var egg_card := _make_card(right)
	var egg_header := HBoxContainer.new()
	egg_header.add_theme_constant_override("separation", 8)
	egg_card.add_child(egg_header)
	egg_header.add_child(UI.label("地板上的鸡蛋", 18, UI.INK))
	var egg_spacer := Control.new()
	egg_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	egg_header.add_child(egg_spacer)
	_ground_eggs_label = UI.label("", 15, UI.INK)
	egg_header.add_child(_ground_eggs_label)
	_collected_label = UI.wrapped_label("", 13)
	egg_card.add_child(_collected_label)
	_collect_button = UI.primary_button("一键收蛋", 15, 40)
	_collect_button.pressed.connect(press_collect_all)
	egg_card.add_child(_collect_button)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	right.add_child(UI.wrapped_label(
		"鸡蛋要点地板上的蛋才收得到；食槽一次最多 9 份，仓库小麦不够时先去农田收小麦。", 13))


func _make_card(parent: VBoxContainer) -> VBoxContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UI.card_style())
	parent.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	card.add_child(column)
	return column


func _build_chicken_card(parent: VBoxContainer, index: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UI.card_style())
	parent.add_child(card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	row.add_child(UI.icon_slot(_chicken_avatar(index), 46.0))

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	row.add_child(column)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	column.add_child(head)
	var name_label := UI.label(_chicken_display_name(index), 16, UI.INK)
	head.add_child(name_label)
	var head_spacer := Control.new()
	head_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(head_spacer)
	var state_label := UI.label("", 12, UI.INK_SOFT)
	head.add_child(state_label)

	# 饥饿条：越长越饿，颜色按饥饿值换绿 / 橙 / 红
	var hunger_row := HBoxContainer.new()
	hunger_row.add_theme_constant_override("separation", 6)
	column.add_child(hunger_row)
	var hunger_caption := UI.label("饥饿", 11, UI.INK_SOFT)
	hunger_caption.custom_minimum_size.x = 22.0
	hunger_row.add_child(hunger_caption)
	var hunger_bar := UI.growth_bar(UI.GREEN, 0.0, 8.0)
	hunger_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hunger_row.add_child(hunger_bar)

	# 产蛋进度：金色细条
	var lay_row := HBoxContainer.new()
	lay_row.add_theme_constant_override("separation", 6)
	column.add_child(lay_row)
	var lay_caption := UI.label("产蛋", 11, UI.INK_SOFT)
	lay_caption.custom_minimum_size.x = 22.0
	lay_row.add_child(lay_caption)
	var lay_bar := UI.growth_bar(UI.GOLD, 0.0, 5.0)
	lay_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lay_row.add_child(lay_bar)

	_chicken_name_labels.append(name_label)
	_chicken_state_labels.append(state_label)
	_chicken_hunger_bars.append(hunger_bar)
	_chicken_lay_bars.append(lay_bar)
	return card


# ---------------- 刷新 ----------------

func _refresh() -> void:
	if _trough_button == null:
		return

	# 食槽：场景里的木槽 + 右侧卡片
	var stock := CoopState.trough_stock
	var stock_text := "饲料 %d/%d" % [stock, CoopState.TROUGH_MAX]
	_trough_label.text = stock_text
	_trough_stock_label.text = stock_text
	var wheat := Inventory.get_amount(CoopState.FEED_ITEM_ID)
	_wheat_label.text = "仓库小麦：%d 份" % wheat
	_fill_button.disabled = stock >= CoopState.TROUGH_MAX or wheat <= 0

	# 地板上的蛋
	_ground_eggs_label.text = "%d / %d 枚" % [
		CoopState.eggs_on_ground, CoopState.MAX_EGGS_ON_GROUND]
	_collected_label.text = "累计收蛋：%d 枚" % CoopState.total_collected
	_collect_button.disabled = CoopState.eggs_on_ground <= 0
	_sync_egg_buttons()

	if _chicken_count_label != null:
		_chicken_count_label.text = "%d 只小鸡" % CoopState.chickens.size()
	for index in range(_chicken_card_panels.size()):
		_chicken_card_panels[index].visible = index < CoopState.chickens.size()
	for index in range(_chicken_name_labels.size()):
		_chicken_name_labels[index].text = _chicken_display_name(index)
	_sync_chicken_views()
	_refresh_chicken_status()


func _refresh_chicken_status() -> void:
	for index in range(_chicken_state_labels.size()):
		var hunger := _hunger_of(index)
		var hunger_bar = _chicken_hunger_bars[index]
		hunger_bar.call("set_progress", clampf(hunger / CoopState.HUNGER_MAX, 0.0, 1.0))
		hunger_bar.call("set_fill_color", _hunger_color(hunger))
		var lay_bar = _chicken_lay_bars[index]
		var lay_progress := 0.0 if CoopState.lay_blocked(index) else CoopState.lay_progress(index)
		lay_bar.call("set_progress", lay_progress)
		var state_text := _chicken_state_text(index)
		var state_label: Label = _chicken_state_labels[index]
		if state_label.text != state_text:
			state_label.text = state_text
			state_label.add_theme_color_override("font_color", _chicken_state_color(index))


func _sync_egg_buttons() -> void:
	var visible_count := mini(CoopState.eggs_on_ground, EGG_BUTTON_COUNT)
	for index in range(_egg_buttons.size()):
		var button := _egg_buttons[index]
		var should_show := index < visible_count
		if should_show and not button.visible:
			button.visible = true
			_pop_egg(button)
		elif not should_show and button.visible:
			button.visible = false
		if index < _egg_shadows.size():
			_egg_shadows[index].visible = should_show


## 新蛋落地时做一个小弹跳，避免数字变了但画面上没变化
func _pop_egg(button: Button) -> void:
	button.pivot_offset = EGG_BUTTON_SIZE * 0.5
	button.scale = Vector2(0.35, 0.35)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2.ONE, 0.32)


func _hunger_of(index: int) -> float:
	if index < 0 or index >= CoopState.chickens.size():
		return 0.0
	return float(CoopState.chickens[index]["hunger"])


func _chicken_display_name(index: int) -> String:
	var display := CoopState.chicken_name(index)
	if not display.is_empty():
		return display
	if index >= 0 and index < CoopState.CHICKEN_NAMES.size():
		return CoopState.CHICKEN_NAMES[index]
	return "小鸡 %d" % (index + 1)


func _chicken_state_text(index: int) -> String:
	var mode := int(_chickens[index].mode) if index >= 0 and index < _chickens.size() else -1
	if mode == MODE_LAY:
		return "正在下蛋…"
	if mode == MODE_TO_SPOT:
		return "去下蛋"
	if mode == MODE_EAT:
		return "正在吃"
	if CoopState.lay_blocked(index):
		return "太饿停产"
	if CoopState.hungry(index):
		return "饿了"
	return "下蛋中 %d%%" % roundi(CoopState.lay_progress(index) * 100.0)


func _chicken_state_color(index: int) -> Color:
	var mode := int(_chickens[index].mode) if index >= 0 and index < _chickens.size() else -1
	if mode == MODE_EAT:
		return UI.GREEN_DARK
	if mode == MODE_LAY or mode == MODE_TO_SPOT:
		return UI.GOLD_DARK
	if CoopState.lay_blocked(index):
		return UI.RED
	if CoopState.hungry(index):
		return UI.GOLD_DARK
	return UI.INK_SOFT


func _hunger_color(hunger: float) -> Color:
	if hunger >= CoopState.LAY_HUNGER_LIMIT:
		return UI.RED
	if hunger >= CoopState.HUNGRY_AT:
		return UI.GOLD
	return UI.GREEN


# ---------------- 操作 ----------------

## 点食槽 / 点「投喂 3 份」：从仓库扣小麦倒进食槽。
## 返回实际倒进去的份数（0 = 仓库没小麦或食槽已满）。
func press_trough() -> int:
	var filled := CoopState.fill_trough(3)
	if filled > 0:
		show_feedback("倒进 %d 份小麦饲料，食槽现在 %d/%d。" % [
			filled, CoopState.trough_stock, CoopState.TROUGH_MAX], UI.GREEN_DARK)
	elif CoopState.trough_stock >= CoopState.TROUGH_MAX:
		show_feedback("食槽已经装满了（%d/%d），等小鸡吃一些再倒。" % [
			CoopState.trough_stock, CoopState.TROUGH_MAX], UI.GOLD_DARK)
	else:
		show_feedback("仓库里没有小麦了，先去农田收小麦再回仓库拿。", UI.RED)
	_refresh()
	return filled


## 调试补给（仅 debug build）：快速补 10 小麦，方便反复测试投喂/产蛋。
func _debug_gift_wheat() -> void:
	if not OS.is_debug_build():
		return
	Inventory.add(CoopState.FEED_ITEM_ID, 10)
	show_feedback("调试补给：小麦 +10（仓库共 %d 颗）" % Inventory.get_amount(CoopState.FEED_ITEM_ID), UI.GREEN)
	_refresh()


## 点「一键收蛋」：把地板上的蛋全部入库，返回入库数量。
func press_collect_all() -> int:
	var collected := CoopState.collect_all()
	if collected > 0:
		show_feedback("一键收蛋：%d 枚鸡蛋已入库。" % collected, UI.GREEN_DARK)
	else:
		show_feedback("地板上暂时没有鸡蛋。", UI.GOLD_DARK)
	_refresh()
	return collected


## 点第 index 枚蛋：成功入库返回 1，否则返回 0（只收一枚，防重复点击）。
func press_collect_egg_at(index: int) -> int:
	_sync_egg_buttons()
	var available := mini(CoopState.eggs_on_ground, EGG_BUTTON_COUNT)
	if index < 0 or index >= available:
		return 0
	if not _egg_buttons.is_empty():
		if index >= _egg_buttons.size() or not _egg_buttons[index].visible:
			return 0
	var collected := CoopState.collect_egg()
	if collected > 0:
		if index < _egg_buttons.size():
			_float_text(_egg_buttons[index], "+1", UI.GOLD)
		show_feedback("收了一枚鸡蛋，已入库（+1）", UI.GREEN_DARK)
	_refresh()
	return collected


# ---------------- 调试 / 测试接口 ----------------

## 当前鸡舍里有几只鸡（商店买鸡后会变多）
func chicken_visual_count() -> int:
	return CoopState.chickens.size()


## 当前显示了多少枚可点击的蛋（= min(eggs_on_ground, 6)）
func visible_egg_count() -> int:
	if _egg_buttons.is_empty():
		return mini(CoopState.eggs_on_ground, EGG_BUTTON_COUNT)
	_sync_egg_buttons()
	var count := 0
	for button in _egg_buttons:
		if button.visible:
			count += 1
	return count


# ---------------- 每帧更新 ----------------

func _process(delta: float) -> void:
	# 建筑层可能被侧栏整个隐藏，那种情况下也别让小鸡继续走 / 吃
	if not is_visible_in_tree():
		return
	_ensure_chickens_ready()
	_update_chickens(delta)
	# 饥饿值每帧都在涨，条形进度必须每帧刷新
	_refresh_chicken_status()


func _ensure_chickens_ready() -> void:
	if _chickens_initialized or _arena == null:
		return
	if _arena.size.x < 80.0 or _arena.size.y < 80.0:
		return
	_chickens_initialized = true
	_sync_chicken_views()


## 按 CoopState 里的鸡数量显示/隐藏鸡只：商店买鸡后新鸡也会出现。
func _sync_chicken_views() -> void:
	if not _chickens_initialized:
		return
	var bounds := _walk_bounds()
	var active := CoopState.chickens.size()
	for index in range(_chickens.size()):
		var view: ChickenView = _chickens[index]
		var should_show := index < active
		if should_show and not view.sprite.visible:
			var t := 0.18 + 0.16 * float(index % 5)
			view.pos = Vector2(
				lerpf(bounds.position.x + 56.0, bounds.end.x - 56.0, t),
				lerpf(bounds.position.y + 26.0, bounds.end.y - 46.0, 0.30 + 0.24 * float(index % 2)))
			view.target = view.pos
			view.mode = MODE_IDLE
			view.timer = 0.6 + 0.4 * float(index)
			view.facing = 1 if index % 2 == 0 else -1
			view.sprite.position = view.pos
			view.sprite.visible = true
			view.shadow.position = view.pos - CHICKEN_SHADOW_SIZE * 0.5
			view.shadow.visible = true
			_play_anim(view, "idle")
		view.sprite.visible = should_show
		view.shadow.visible = should_show
		if not should_show and _laying_chicken == index:
			_laying_chicken = -1
			_laying_slot = -1


func _update_chickens(delta: float) -> void:
	if _arena == null or _arena.size.x < 80.0:
		return
	var bounds := _walk_bounds()
	var active := mini(_chickens.size(), CoopState.chickens.size())
	for index in range(active):
		var view: ChickenView = _chickens[index]
		_update_chicken(index, view, bounds, delta)


func _update_chicken(index: int, view: ChickenView, bounds: Rect2, delta: float) -> void:
	match view.mode:
		MODE_LAY:
			_play_anim(view, "crouch")
			view.timer -= delta
			if view.timer <= 0.0:
				_finish_laying(index, view)
		MODE_TO_SPOT:
			if not CoopState.lay_ready(index):
				_abort_laying(index, view)
			else:
				var nest_point := _lay_spot_point(int(view.lay_slot))
				if view.pos.distance_to(nest_point) <= ARRIVE_DISTANCE:
					_start_laying(index, view)
				else:
					_play_anim(view, "move")
					_walk_towards(view, nest_point, delta)
		MODE_EAT:
			_play_anim(view, "eat")
			view.timer -= delta
			if view.timer <= 0.0:
				_pick_wander_target(view, bounds)
		MODE_SEEK:
			if not _should_seek(index):
				_pick_wander_target(view, bounds)
			else:
				var eat_point := _trough_eat_point(index)
				if view.pos.distance_to(eat_point) <= ARRIVE_DISTANCE:
					_start_eating(index, view, eat_point)
				else:
					_play_anim(view, "move")
					_walk_towards(view, eat_point, delta)
		MODE_IDLE:
			_play_anim(view, "idle")
			view.timer -= delta
			if _should_seek(index):
				view.mode = MODE_SEEK
			elif _try_start_laying(index, view):
				pass
			elif view.timer <= 0.0:
				_pick_wander_target(view, bounds)
		_:
			# MODE_WANDER：朝随机点走过去，到了就站着歇一会儿
			if _should_seek(index):
				view.mode = MODE_SEEK
			elif _try_start_laying(index, view):
				pass
			elif view.pos.distance_to(view.target) <= 6.0:
				view.mode = MODE_IDLE
				view.timer = randf_range(0.7, 2.0)
				_play_anim(view, "idle")
			else:
				_play_anim(view, "move")
				_walk_towards(view, view.target, delta)
	_apply_chicken_position(view, bounds)


func _start_eating(index: int, view: ChickenView, eat_point: Vector2) -> void:
	if not CoopState.feed_chicken(index):
		# 走到时食槽已经被别的鸡吃空了：重新溜达，等玩家再投喂
		_pick_wander_target(view, _walk_bounds())
		return
	view.facing = 1 if eat_point.x >= view.pos.x else -1
	view.mode = MODE_EAT
	view.timer = EAT_SECONDS
	_play_anim(view, "eat")
	show_feedback("%s 在食槽吃了一份饲料，还剩 %d 份。" % [
		_chicken_display_name(index), CoopState.trough_stock], UI.GREEN_DARK)


func _try_start_laying(index: int, view: ChickenView) -> bool:
	# 同一时间只让一只鸡去下蛋；其他鸡即便计时到了也先继续溜达
	if _laying_chicken >= 0:
		return false
	if not CoopState.lay_ready(index):
		return false
	if CoopState.eggs_on_ground >= CoopState.MAX_EGGS_ON_GROUND:
		return false
	var slot := clampi(CoopState.eggs_on_ground, 0, EGG_BUTTON_COUNT - 1)
	_laying_chicken = index
	_laying_slot = slot
	view.lay_slot = slot
	view.mode = MODE_TO_SPOT
	view.target = _lay_spot_point(slot)
	show_feedback("%s 去找一块空地下蛋了…" % _chicken_display_name(index), UI.INK_SOFT)
	return true


func _start_laying(index: int, view: ChickenView) -> void:
	view.mode = MODE_LAY
	view.timer = LAY_SECONDS
	view.facing = 1 if view.lay_slot % 2 == 0 else -1
	_play_anim(view, "crouch")
	show_feedback("%s 蹲下来下蛋了…" % _chicken_display_name(index), UI.INK_SOFT)


func _finish_laying(index: int, view: ChickenView) -> void:
	var laid := CoopState.lay_egg(index)
	_laying_chicken = -1
	_laying_slot = -1
	view.lay_slot = -1
	if laid > 0:
		_sync_egg_buttons()
		var egg_index := mini(CoopState.eggs_on_ground - 1, _egg_buttons.size() - 1)
		if egg_index >= 0:
			_float_text(_egg_buttons[egg_index], "+1 蛋", UI.GOLD)
		show_feedback("%s 下了一枚蛋，掉在木地板上，点一下收进仓库。" % _chicken_display_name(index), UI.GREEN_DARK)
		view.mode = MODE_IDLE
		view.timer = 1.4
	else:
		_pick_wander_target(view, _walk_bounds())


func _abort_laying(index: int, view: ChickenView) -> void:
	if _laying_chicken == index:
		_laying_chicken = -1
		_laying_slot = -1
	view.lay_slot = -1
	_pick_wander_target(view, _walk_bounds())


## 鸡下蛋时站的位置：对应的落蛋点往上错开一点，蛋落点在鸡脚前
func _lay_spot_point(slot: int) -> Vector2:
	var bounds := _walk_bounds()
	var point := _egg_floor_point(slot) - Vector2(0.0, 20.0)
	return Vector2(
		clampf(point.x, bounds.position.x + 28.0, bounds.end.x - 28.0),
		clampf(point.y, bounds.position.y + 10.0, bounds.end.y - 10.0))


func _should_seek(index: int) -> bool:
	return CoopState.hungry(index) and CoopState.trough_stock > 0


func _walk_towards(view: ChickenView, point: Vector2, delta: float) -> void:
	var offset := point - view.pos
	var distance := offset.length()
	if distance <= 0.5:
		return
	view.facing = 1 if offset.x > 0.0 else -1
	view.pos += offset / distance * minf(view.speed * delta, distance)
	view.sprite.position = view.pos
	view.shadow.position = view.pos - CHICKEN_SHADOW_SIZE * 0.5


func _pick_wander_target(view: ChickenView, bounds: Rect2) -> void:
	view.target = Vector2(
		randf_range(bounds.position.x + 24.0, bounds.end.x - 24.0),
		randf_range(bounds.position.y + 16.0, bounds.end.y - 16.0))
	if view.target.distance_to(view.pos) < 80.0:
		view.target += Vector2(randf_range(-60.0, 60.0), randf_range(-16.0, 16.0))
	view.mode = MODE_WANDER


func _apply_chicken_position(view: ChickenView, bounds: Rect2) -> void:
	var margin := 24.0
	view.pos.x = clampf(view.pos.x, bounds.position.x + margin, bounds.end.x - margin)
	view.pos.y = clampf(view.pos.y, bounds.position.y + margin, bounds.end.y - margin)
	view.sprite.position = view.pos
	view.shadow.position = view.pos - CHICKEN_SHADOW_SIZE * 0.5


func _walk_bounds() -> Rect2:
	var area_size := _arena.size
	var top := area_size.y * WALL_RATIO + WALK_TOP_PADDING
	var bottom := area_size.y - WALK_BOTTOM_PADDING
	return Rect2(
		WALK_SIDE_MARGIN,
		top,
		maxf(area_size.x - WALK_SIDE_MARGIN * 2.0, 120.0),
		maxf(bottom - top, 90.0))


## 鸡吃饭时站的位置：食槽正上方、每只鸡左右错开一点，避免叠在一起
func _trough_eat_point(index: int) -> Vector2:
	var bounds := _walk_bounds()
	var center_x := bounds.position.x + bounds.size.x * 0.5
	var stand_y := bounds.end.y - 2.0
	if _trough_button != null and _trough_button.size.x > 1.0:
		center_x = _trough_button.position.x + _trough_button.size.x * 0.5
		stand_y = _trough_button.position.y - 6.0
	var active_count := maxi(1, CoopState.chickens.size())
	var spread := (float(index) - float(active_count - 1) * 0.5) * 44.0
	return Vector2(center_x + spread, clampf(stand_y, bounds.position.y, bounds.end.y))


func _play_anim(view: ChickenView, kind: String) -> void:
	if view.sprite == null or view.sprite.sprite_frames == null:
		return
	var side := "right" if view.facing > 0 else "left"
	var animation := StringName(kind + "_" + side)
	if view.sprite.animation != animation:
		view.sprite.play(animation)


## 收蛋时在蛋上方冒一个「+1」；蛋按钮在木地板上，要先换回场景局部坐标
func _float_text(anchor: Control, text_value: String, color: Color) -> void:
	if _arena == null:
		return
	var center := anchor.get_global_rect().get_center()
	var local := _arena.get_global_transform().affine_inverse() * center
	var label := UI.label(text_value, 20, color)
	label.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.02, 1.0))
	label.add_theme_constant_override("outline_size", 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 9
	label.position = local - Vector2(48.0, 34.0)
	label.size = Vector2(96.0, 28.0)
	_arena.add_child(label)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 32.0, 0.7)
	tween.tween_property(label, "modulate:a", 0.0, 0.45).set_delay(0.25)
	tween.chain().tween_callback(label.queue_free)


# ---------------- 生命周期 ----------------

func _on_open() -> void:
	# 窗口打开时由界面接管进食：鸡要「走到食槽」才吃到，数据层就不再自动喂。
	CoopState.ui_active = true
	_refresh()
	_ensure_chickens_ready.call_deferred()


func _on_close() -> void:
	# 关窗后整个鸡舍暂停（含产蛋计时），避免不在场时凭空多蛋；
	# 正在去下蛋的鸡回到待机，下次打开再重新走。
	CoopState.ui_active = false
	if _laying_chicken >= 0 and _laying_chicken < _chickens.size():
		var laying_view: ChickenView = _chickens[_laying_chicken]
		laying_view.mode = MODE_IDLE
		laying_view.timer = 0.4
	_laying_chicken = -1
	_laying_slot = -1


func _on_inventory_changed() -> void:
	_refresh()


func _on_day_started() -> void:
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		# 建筑层可能被侧栏整体隐藏（此时窗口自身还是 visible=true）。
		# 用 is_visible_in_tree() 把控制权交还数据层，避免 ui_active 卡在 true
		# 导致关掉界面后鸡再也不自动进食。
		if not _chickens.is_empty():
			CoopState.ui_active = is_visible_in_tree()