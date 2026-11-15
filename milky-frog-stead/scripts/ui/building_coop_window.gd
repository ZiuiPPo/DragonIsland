extends "res://scripts/ui/building_window_base.gd"
## 鸡舍建筑独立页面。
##
## 页面结构：
##   左边是深色鸡舍围栏：草地、鸡窝、3 只自己走动的小鸡、底部食盆；
##   右边是鸡舍状态：3 只鸡的饥饿条与状态、食盆存量、地上 / 累计鸡蛋、操作按钮。
##
## 数值全在 CoopState autoload 里，本页只负责「画出来 + 把点击转成数据操作」。
## 窗口打开时把 CoopState.ui_active 置 true，由本页 _process 驱动鸡走到食盆进食；
## 窗口关闭后数据层自己进食，保证关掉建筑界面时蛋也在慢慢产出。

const CHICKEN_SCENE := preload("res://scenes/chicken/chicken.tscn")
const GRASS_TEXTURE := preload("res://assets/tilesets/grass.png")
const HOUSE_TEXTURE := preload(
	"res://assets/sprites/decorations/farmland_set_20261105/house_egg.png")

## 鸡舍里固定养 3 只鸡（与 CoopState.CHICKEN_NAMES 的数量一致）
const CHICKEN_COUNT: int = 3
const EGG_BUTTON_COUNT: int = 6
const EGG_BUTTON_SIZE := Vector2(44.0, 44.0)
## 6 枚蛋固定摆在鸡窝（草垫）上的 6 个锚点，相对围栏宽高的比例，避免窗口缩放时跑偏
const EGG_SPOTS := [
	Vector2(0.55, 0.60), Vector2(0.66, 0.605), Vector2(0.77, 0.595),
	Vector2(0.60, 0.685), Vector2(0.71, 0.69), Vector2(0.82, 0.675),
]
const CHICKEN_SCALE: float = 0.68
const CHICKEN_SPEED_MIN: float = 40.0
const CHICKEN_SPEED_MAX: float = 58.0
## 吃到饲料后播 eat 动画的时长
const EAT_SECONDS: float = 2.0
const ARRIVE_DISTANCE: float = 26.0
## 小鸡只在围栏中段的这个比例区间里活动，避开上面的鸡窝和下面的食盆
const WALK_TOP_RATIO: float = 0.46
const WALK_BOTTOM_RATIO: float = 0.78
const WALK_SIDE_MARGIN: float = 56.0
const ARENA_MIN_HEIGHT: float = 470.0
const SIDE_PANEL_WIDTH: float = 340.0
const HUNGER_BAR_HEIGHT: float = 10.0

## 底部提示条上的成功 / 警告配色（浅色木纹面板上用深一点的颜色才看得清）
const FEEDBACK_OK := Color(0.15, 0.42, 0.18)
const FEEDBACK_WARN := Color(0.62, 0.33, 0.10)

# 鸡的行走模式。只影响画面，饥饿 / 产蛋数值由 CoopState 决定。
const MODE_WANDER: int = 0
const MODE_SEEK: int = 1
const MODE_EAT: int = 2
const MODE_IDLE: int = 3


## 一只鸡的界面状态：位置、随机落脚点、朝向和当前动作。
## 单独存一份是为了把「画面上怎么走」和 CoopState 里的数值解耦，
## 换场景 / 重开窗口时只需要重新摆位置，不用碰数据层。
class ChickenView:
	var sprite: AnimatedSprite2D = null
	var pos: Vector2 = Vector2.ZERO
	var target: Vector2 = Vector2.ZERO
	var speed: float = 48.0
	var facing: int = 1
	var mode: int = 0
	var timer: float = 0.0


var _arena: Control = null
var _trough_button: Button = null
var _egg_buttons: Array[Button] = []
var _chicken_frames: SpriteFrames = null
var _chickens: Array = []
var _chickens_initialized: bool = false

# 右侧状态面板的控件
var _chicken_name_labels: Array[Label] = []
var _chicken_bars: Array[ProgressBar] = []
var _chicken_states: Array[Label] = []
var _chicken_fill_styles: Array[StyleBoxFlat] = []
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
	return "点食盆投喂 · 鸡饿了自己来吃 · 点地上的蛋收进仓库 · Esc 返回建筑"


func _build_body(parent: VBoxContainer) -> void:
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 18)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(main)

	_build_arena(main)
	_build_side_panel(main)

	# 数据层任何变化（投喂 / 吃食 / 产蛋 / 收蛋）都刷新右侧数字和地上的蛋
	CoopState.changed.connect(_refresh)
	_refresh()


# ---------------- 左边：鸡舍围栏 ----------------

func _build_arena(main: HBoxContainer) -> void:
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	main.add_child(left)

	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UI.dark_style(Color(0.16, 0.22, 0.12, 1.0)))
	left.add_child(panel)

	_arena = Control.new()
	_arena.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_arena.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_arena.custom_minimum_size = Vector2(0.0, ARENA_MIN_HEIGHT)
	_arena.clip_contents = true
	panel.add_child(_arena)

	# 用图集里的「全填充」草格（第 4 行第 0 列，索引 44），平铺才没有网格线
	_arena.add_child(UI.tiled_rect(GRASS_TEXTURE, 44))
	_build_house()

	_chicken_frames = _load_chicken_frames()
	for index in range(CHICKEN_COUNT):
		_build_chicken(index)

	_build_nest()
	_build_eggs()
	_build_trough()

	left.add_child(UI.wrapped_label(
		"小鸡饿了会自己走到食盆边；食盆空了就先投喂。窗口关掉后它们也会自己吃。", 14))


func _build_house() -> void:
	var house := TextureRect.new()
	house.texture = HOUSE_TEXTURE
	house.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	house.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	house.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	house.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arena.add_child(house)
	# 贴右上角；不挡点击，纯装饰
	house.anchor_left = 1.0
	house.anchor_right = 1.0
	house.anchor_top = 0.0
	house.anchor_bottom = 0.0
	house.offset_left = -186.0
	house.offset_right = -16.0
	house.offset_top = 8.0
	house.offset_bottom = 196.0


## 直接从 chicken.tscn 里取调好的 SpriteFrames：动画名和帧布局已经能复用。
## 临时实例化只为了拿资源，取完立刻 free，不进场景树也不会跑小鸡自己的脚本逻辑。
func _load_chicken_frames() -> SpriteFrames:
	var temp := CHICKEN_SCENE.instantiate()
	var animated := temp.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	var frames: SpriteFrames = null
	if animated != null:
		frames = animated.sprite_frames
	temp.free()
	return frames


func _build_chicken(index: int) -> void:
	var sprite := AnimatedSprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(CHICKEN_SCALE, CHICKEN_SCALE)
	# 小鸡美术的脚底在 128px 格子里偏下，往上抬一点，让节点原点接近脚底
	sprite.offset = Vector2(0, -22)
	sprite.z_index = 3
	# 先藏起来：等围栏完成排版、_ensure_chickens_ready 摆好位置再显示，
	# 否则打开窗口的第一帧会看到 3 只鸡挤在左上角
	sprite.visible = false
	if _chicken_frames != null:
		sprite.sprite_frames = _chicken_frames
		sprite.play("idle_left")
	_arena.add_child(sprite)

	var view := ChickenView.new()
	view.sprite = sprite
	view.speed = randf_range(CHICKEN_SPEED_MIN, CHICKEN_SPEED_MAX)
	view.facing = -1 if index % 2 == 0 else 1
	_chickens.append(view)


## 鸡窝草垫：纯装饰，托住地上的蛋，让蛋看起来是落在地上而不是浮在半空
func _build_nest() -> void:
	var nest := Panel.new()
	nest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nest.anchor_left = 0.50
	nest.anchor_right = 0.92
	nest.anchor_top = 0.55
	nest.anchor_bottom = 0.74
	nest.offset_left = 0.0
	nest.offset_right = 0.0
	nest.offset_top = 0.0
	nest.offset_bottom = 0.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.56, 0.43, 0.21, 1.0)
	style.border_color = Color(0.33, 0.24, 0.11, 1.0)
	style.set_border_width_all(3)
	style.set_corner_radius_all(48)
	nest.add_theme_stylebox_override("panel", style)
	# 草垫在最下面：小鸡站在草垫上，蛋在草垫上方
	nest.z_index = 1
	_arena.add_child(nest)


func _build_eggs() -> void:
	var egg_icon := ItemDB.icon(CoopState.EGG_ITEM_ID)
	for index in range(EGG_BUTTON_COUNT):
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.flat = true
		button.icon = egg_icon
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", int(EGG_BUTTON_SIZE.x) - 4)
		button.tooltip_text = "点击把这枚鸡蛋收进仓库"
		button.visible = false
		button.z_index = 2
		button.pressed.connect(press_collect_egg_at.bind(index))
		_arena.add_child(button)
		_place_egg_button(button, index)
		_egg_buttons.append(button)


func _place_egg_button(button: Button, index: int) -> void:
	var spot: Vector2 = EGG_SPOTS[index % EGG_SPOTS.size()]
	button.anchor_left = spot.x
	button.anchor_right = spot.x
	button.anchor_top = spot.y
	button.anchor_bottom = spot.y
	button.offset_left = -EGG_BUTTON_SIZE.x * 0.5
	button.offset_right = EGG_BUTTON_SIZE.x * 0.5
	button.offset_top = -EGG_BUTTON_SIZE.y * 0.5
	button.offset_bottom = EGG_BUTTON_SIZE.y * 0.5
	button.pivot_offset = EGG_BUTTON_SIZE * 0.5


func _build_trough() -> void:
	_trough_button = Button.new()
	_trough_button.focus_mode = Control.FOCUS_NONE
	_trough_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_trough_button.icon = ItemDB.icon(CoopState.FEED_ITEM_ID)
	_trough_button.expand_icon = true
	_trough_button.add_theme_constant_override("icon_max_width", 30)
	_trough_button.add_theme_font_size_override("font_size", 16)
	_trough_button.add_theme_color_override("font_color", UI.TEXT_DARK)
	_trough_button.add_theme_stylebox_override("normal", UI.card_style())
	var highlight := UI.card_style(true)
	_trough_button.add_theme_stylebox_override("hover", highlight)
	_trough_button.add_theme_stylebox_override("pressed", highlight)
	_trough_button.tooltip_text = "点一下从仓库倒 3 份小麦饲料进食盆"
	_trough_button.pressed.connect(press_trough)
	_arena.add_child(_trough_button)
	# 贴底部中间偏左，和鸡窝错开
	_trough_button.anchor_left = 0.28
	_trough_button.anchor_right = 0.66
	_trough_button.anchor_top = 1.0
	_trough_button.anchor_bottom = 1.0
	_trough_button.offset_left = 0.0
	_trough_button.offset_right = 0.0
	_trough_button.offset_top = -78.0
	_trough_button.offset_bottom = -14.0


# ---------------- 右边：状态面板 ----------------

func _build_side_panel(main: HBoxContainer) -> void:
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = SIDE_PANEL_WIDTH
	right.add_theme_constant_override("separation", 8)
	main.add_child(right)

	right.add_child(UI.title_label("鸡舍状态", 22))

	# 3 只鸡的饥饿条 + 状态文字
	var chicken_card := _make_card(right)
	for index in range(CHICKEN_COUNT):
		_build_chicken_row(chicken_card, index)

	# 食盆
	var trough_card := _make_card(right)
	var trough_header := HBoxContainer.new()
	trough_header.add_theme_constant_override("separation", 8)
	trough_card.add_child(trough_header)
	trough_header.add_child(UI.label("食盆", 18, UI.TEXT_DARK))
	var trough_spacer := Control.new()
	trough_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trough_header.add_child(trough_spacer)
	_trough_stock_label = UI.label("", 15, UI.TEXT_DARK)
	trough_header.add_child(_trough_stock_label)
	_wheat_label = UI.wrapped_label("", 13)
	trough_card.add_child(_wheat_label)
	_fill_button = UI.button("投喂 3 份", 15, 40)
	_fill_button.pressed.connect(press_trough)
	trough_card.add_child(_fill_button)

	# 鸡蛋
	var egg_card := _make_card(right)
	var egg_header := HBoxContainer.new()
	egg_header.add_theme_constant_override("separation", 8)
	egg_card.add_child(egg_header)
	egg_header.add_child(UI.label("鸡蛋", 18, UI.TEXT_DARK))
	var egg_spacer := Control.new()
	egg_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	egg_header.add_child(egg_spacer)
	_ground_eggs_label = UI.label("", 15, UI.TEXT_DARK)
	egg_header.add_child(_ground_eggs_label)
	_collected_label = UI.wrapped_label("", 13)
	egg_card.add_child(_collected_label)
	_collect_button = UI.button("一键收蛋", 15, 40)
	_collect_button.pressed.connect(press_collect_all)
	egg_card.add_child(_collect_button)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	right.add_child(UI.wrapped_label(
		"鸡蛋要点一下才进仓库；食盆一次最多 9 份。仓库小麦不够时先去农田收小麦。", 13))


func _make_card(parent: VBoxContainer) -> VBoxContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UI.card_style())
	parent.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	card.add_child(column)
	return column


func _build_chicken_row(parent: VBoxContainer, index: int) -> void:
	if index > 0:
		parent.add_child(HSeparator.new())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var name_label := UI.label(_chicken_display_name(index), 16, UI.TEXT_DARK)
	name_label.custom_minimum_size.x = 44.0
	row.add_child(name_label)
	_chicken_name_labels.append(name_label)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 2)
	row.add_child(column)

	var bar := UI.progress_bar(Color(0.42, 0.72, 0.32), HUNGER_BAR_HEIGHT)
	column.add_child(bar)
	_chicken_bars.append(bar)
	# 颜色在 _refresh_chicken_status 里按饥饿值换，先占个位
	_chicken_fill_styles.append(null)

	var state_label := UI.label("", 12, UI.TEXT_SOFT)
	column.add_child(state_label)
	_chicken_states.append(state_label)


# ---------------- 刷新 ----------------

func _refresh() -> void:
	if _trough_button == null:
		return

	# 食盆
	var stock := CoopState.trough_stock
	var stock_text := "饲料 %d/%d" % [stock, CoopState.TROUGH_MAX]
	_trough_button.text = stock_text
	_trough_stock_label.text = stock_text
	var wheat := Inventory.get_amount(CoopState.FEED_ITEM_ID)
	_wheat_label.text = "仓库小麦：%d 份" % wheat
	_fill_button.disabled = stock >= CoopState.TROUGH_MAX or wheat <= 0

	# 鸡蛋
	_ground_eggs_label.text = "%d/%d 枚" % [
		CoopState.eggs_on_ground, CoopState.MAX_EGGS_ON_GROUND]
	_collected_label.text = "累计收蛋：%d 枚" % CoopState.total_collected
	_collect_button.disabled = CoopState.eggs_on_ground <= 0
	_sync_egg_buttons()

	# 鸡只状态
	for index in range(_chicken_name_labels.size()):
		_chicken_name_labels[index].text = _chicken_display_name(index)
	_refresh_chicken_status()


func _refresh_chicken_status() -> void:
	for index in range(_chicken_bars.size()):
		var hunger := _hunger_of(index)
		_chicken_bars[index].value = hunger
		var color := _hunger_color(hunger)
		var fill_style := _chicken_fill_styles[index]
		if fill_style == null or fill_style.bg_color != color:
			# 直接换一份 StyleBoxFlat 再挂回主题，比改旧样式更稳：
			# 进度条在 headless/窗口下都会立刻重绘成新颜色。
			var new_style := StyleBoxFlat.new()
			new_style.bg_color = color
			new_style.set_corner_radius_all(4)
			_chicken_bars[index].add_theme_stylebox_override("fill", new_style)
			_chicken_fill_styles[index] = new_style
		var state_text := _chicken_state_text(index)
		var state_label := _chicken_states[index]
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


## 新蛋落地时做一个小弹跳，避免数字变了但画面没变化
func _pop_egg(button: Button) -> void:
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
	if index < _chickens.size() and int(_chickens[index].mode) == MODE_EAT:
		return "正在吃"
	if CoopState.lay_blocked(index):
		return "太饿停产"
	if CoopState.hungry(index):
		return "饿了"
	return "下蛋中 %d%%" % roundi(CoopState.lay_progress(index) * 100.0)


func _chicken_state_color(index: int) -> Color:
	if index < _chickens.size() and int(_chickens[index].mode) == MODE_EAT:
		return FEEDBACK_OK
	if CoopState.lay_blocked(index) or CoopState.hungry(index):
		return FEEDBACK_WARN
	return UI.TEXT_SOFT


func _hunger_color(hunger: float) -> Color:
	if hunger >= CoopState.LAY_HUNGER_LIMIT:
		return Color(0.80, 0.25, 0.18)
	if hunger >= CoopState.HUNGRY_AT:
		return Color(0.88, 0.52, 0.18)
	return Color(0.42, 0.72, 0.32)


# ---------------- 操作 ----------------

## 点食盆 / 点「投喂 3 份」：从仓库扣小麦倒进食盆。
## 返回实际倒进去的份数（0 = 仓库没小麦或食盆已满）。
func press_trough() -> int:
	var filled := CoopState.fill_trough(3)
	if filled > 0:
		show_feedback("倒进 %d 份小麦饲料，食盆现在 %d/%d。" % [
			filled, CoopState.trough_stock, CoopState.TROUGH_MAX], FEEDBACK_OK)
	elif CoopState.trough_stock >= CoopState.TROUGH_MAX:
		show_feedback("食盆已经装满了（%d/%d），等小鸡吃一些再倒。" % [
			CoopState.trough_stock, CoopState.TROUGH_MAX], FEEDBACK_WARN)
	else:
		show_feedback("仓库里没有小麦了，先去农田收小麦再回仓库拿。", FEEDBACK_WARN)
	_refresh()
	return filled


## 点「一键收蛋」：把地上的蛋全部入库，返回入库数量。
func press_collect_all() -> int:
	var collected := CoopState.collect_all()
	if collected > 0:
		show_feedback("一键收蛋：%d 枚鸡蛋已入库。" % collected, FEEDBACK_OK)
	else:
		show_feedback("地上暂时没有鸡蛋。", FEEDBACK_WARN)
	_refresh()
	return collected


## 点第 index 枚蛋：成功入库返回 1，否则返回 0。
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
			_float_text(_egg_buttons[index], "+1", Color(1.0, 0.86, 0.3))
		show_feedback("收了一枚鸡蛋，已入库（+1）", FEEDBACK_OK)
	_refresh()
	return collected


# ---------------- 调试 / 测试接口 ----------------

## 画面里有几只鸡（固定 3 只）
func chicken_visual_count() -> int:
	if _chickens.is_empty():
		return CHICKEN_COUNT
	return _chickens.size()


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
	# 饥饿值每帧都在涨，进度条必须每帧刷新
	_refresh_chicken_status()


func _ensure_chickens_ready() -> void:
	if _chickens_initialized or _arena == null:
		return
	if _arena.size.x < 80.0 or _arena.size.y < 80.0:
		return
	_chickens_initialized = true
	var bounds := _walk_bounds()
	for index in range(_chickens.size()):
		var view: ChickenView = _chickens[index]
		var t := 0.25 + 0.25 * float(index)
		view.pos = Vector2(
			lerpf(bounds.position.x + 48.0, bounds.end.x - 48.0, t),
			lerpf(bounds.position.y + 20.0, bounds.end.y - 20.0, 0.5 + 0.2 * float(index % 2)))
		view.target = view.pos
		view.mode = MODE_IDLE
		view.timer = 0.6 + 0.4 * float(index)
		view.facing = 1 if index % 2 == 0 else -1
		view.sprite.visible = true
		view.sprite.position = view.pos
		_play_anim(view, "idle")


func _update_chickens(delta: float) -> void:
	if _arena == null or _arena.size.x < 80.0:
		return
	var bounds := _walk_bounds()
	for index in range(_chickens.size()):
		var view: ChickenView = _chickens[index]
		_update_chicken(index, view, bounds, delta)


func _update_chicken(index: int, view: ChickenView, bounds: Rect2, delta: float) -> void:
	match view.mode:
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
			elif view.timer <= 0.0:
				_pick_wander_target(view, bounds)
		_:
			# MODE_WANDER：朝随机点走过去，到了就站着歇一会儿
			if _should_seek(index):
				view.mode = MODE_SEEK
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
		# 走到时食盆已经被别的鸡吃空了：重新溜达，等玩家再投喂
		_pick_wander_target(view, _walk_bounds())
		return
	view.facing = 1 if eat_point.x >= view.pos.x else -1
	view.mode = MODE_EAT
	view.timer = EAT_SECONDS
	_play_anim(view, "eat")
	show_feedback("%s 吃了一份饲料，食盆还剩 %d 份。" % [
		_chicken_display_name(index), CoopState.trough_stock], FEEDBACK_OK)


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


func _pick_wander_target(view: ChickenView, bounds: Rect2) -> void:
	view.target = Vector2(
		randf_range(bounds.position.x + 24.0, bounds.end.x - 24.0),
		randf_range(bounds.position.y + 18.0, bounds.end.y - 18.0))
	if view.target.distance_to(view.pos) < 80.0:
		view.target += Vector2(randf_range(-60.0, 60.0), randf_range(-20.0, 20.0))
	view.mode = MODE_WANDER


func _apply_chicken_position(view: ChickenView, bounds: Rect2) -> void:
	var margin := 28.0
	view.pos.x = clampf(view.pos.x, bounds.position.x + margin, bounds.end.x - margin)
	view.pos.y = clampf(view.pos.y, bounds.position.y + margin, bounds.end.y - margin)
	view.sprite.position = view.pos


func _walk_bounds() -> Rect2:
	var area_size := _arena.size
	var top := area_size.y * WALK_TOP_RATIO
	var bottom := area_size.y * WALK_BOTTOM_RATIO
	return Rect2(
		WALK_SIDE_MARGIN,
		top,
		maxf(area_size.x - WALK_SIDE_MARGIN * 2.0, 120.0),
		maxf(bottom - top, 90.0))


## 鸡吃饭时站的位置：食盆正上方、每只鸡左右错开一点，避免叠在一起
func _trough_eat_point(index: int) -> Vector2:
	var bounds := _walk_bounds()
	var x := bounds.position.x + bounds.size.x * 0.5
	if _trough_button != null and _trough_button.size.x > 1.0:
		x = _trough_button.position.x + _trough_button.size.x * 0.5
	var spread := (float(index) - float(CHICKEN_COUNT - 1) * 0.5) * 56.0
	return Vector2(x + spread, bounds.end.y - 6.0)


func _play_anim(view: ChickenView, kind: String) -> void:
	if view.sprite == null or view.sprite.sprite_frames == null:
		return
	var side := "right" if view.facing > 0 else "left"
	var animation := StringName(kind + "_" + side)
	if view.sprite.animation != animation:
		view.sprite.play(animation)


## 收蛋时在蛋上方冒一个「+1」
func _float_text(anchor: Control, text_value: String, color: Color) -> void:
	if _arena == null:
		return
	var label := UI.label(text_value, 20, color)
	label.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.02, 1.0))
	label.add_theme_constant_override("outline_size", 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = anchor.position - Vector2(40.0, 26.0)
	label.size = Vector2(96.0, 28.0)
	_arena.add_child(label)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 32.0, 0.7)
	tween.tween_property(label, "modulate:a", 0.0, 0.45).set_delay(0.25)
	tween.chain().tween_callback(label.queue_free)


# ---------------- 生命周期 ----------------

func _on_open() -> void:
	# 窗口打开时由界面接管进食：鸡要「走到食盆」才吃到，数据层就不再自动喂。
	CoopState.ui_active = true
	_refresh()
	_ensure_chickens_ready.call_deferred()


func _on_close() -> void:
	# 关窗后交还给数据层自动进食，保证离开鸡舍时鸡也在吃 / 下蛋。
	CoopState.ui_active = false


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