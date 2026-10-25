extends Control
## 侧边栏控制器。
##
## 结构约定（见 sidebar.tscn）：
##   Layout(HBoxContainer, 右对齐)
##     ├─ MenuArea(Control, 固定 300 宽, clip_contents = true)   —— 抽屉的"窗口"
##     │    └─ MenuPanel(Control, 整块面板)                       —— 被左右平移的就是它
##     │         ├─ MenuBackground(Panel)                         —— 底板
##     │         └─ MenuHolder(MarginContainer)                   —— 菜单实例挂这里，一次只显示一个
##     └─ IconColumn(VBoxContainer)                               —— 图标按钮列，贴屏幕右边
##
## 开合方式：抽屉整块从右边滑出来。
##   MenuPanel 平时停在 x = +MENU_WIDTH（正好被 MenuArea 裁掉，看不见），
##   展开时补间到 x = 0，看起来就是从图标列背后 / 屏幕右边快速抽出来。
##   所以改宽度请改 MENU_WIDTH 和 MenuArea 的 custom_minimum_size.x 两处（MenuPanel 跟着 MenuArea 宽）。
##
## 高度不用手动同步：MenuArea 在 HBoxContainer 里是 SIZE_FILL，
## HBoxContainer 的高度 = 图标列的最小高度，所以往 IconColumn 里加按钮菜单会自己变高；
## 只有"菜单内容比图标列还高"的情况，才会把 MenuArea 撑高（避免文字被裁掉）。

const MENU_WIDTH: float = 300.0     ## 抽屉宽度，必须与 MenuArea.custom_minimum_size.x 一致
const MENU_PADDING_Y: float = 40.0  ## MenuHolder 上下外边距之和（20 + 20）
const ANIM_TIME: float = 0.18       ## 要"快速弹出"就调小这个值

@onready var _menu_area: Control = %MenuArea
@onready var _menu_panel: Control = %MenuPanel
@onready var _menu_holder: MarginContainer = %MenuHolder
@onready var _icon_column: VBoxContainer = %IconColumn

var _menus: Dictionary = {}                  ## SidebarIconButton -> Control（懒加载缓存）
var _open_button: SidebarIconButton = null
var _slide_tween: Tween = null
var _height_tween: Tween = null
var _fade_tween: Tween = null


func _ready() -> void:
	_collapse_immediately()
	for child in _icon_column.get_children():
		if child is SidebarIconButton:
			child.toggled.connect(_on_icon_toggled.bind(child))


func _unhandled_input(event: InputEvent) -> void:
	if _open_button != null and event.is_action_pressed("ui_cancel"):
		_open_button.button_pressed = false   # 触发 toggled(false) → _close_menu()
		get_viewport().set_input_as_handled()


# ---------------- 对外接口 ----------------

func is_open() -> bool:
	return _open_button != null


func close() -> void:
	if _open_button != null:
		_open_button.button_pressed = false


# ---------------- 按钮与菜单的对应关系 ----------------

func _on_icon_toggled(toggled_on: bool, button: SidebarIconButton) -> void:
	if toggled_on:
		_open_menu(button)
	elif _open_button == button:
		_close_menu()


func _open_menu(button: SidebarIconButton) -> void:
	var menu := _get_or_create_menu(button)
	if menu == null:
		# 拿不到菜单就把按钮弹回去，避免出现"按下了但什么都没发生"的状态
		button.set_pressed_no_signal(false)
		return
	for other in _menus.values():
		(other as Control).visible = other == menu
	_open_button = button
	_menu_panel.visible = true
	# 高度取 max(图标列高度, 菜单内容高度)：
	#   - 内容比图标列矮时，容器会把 MenuArea 拉到图标列高度（默认行为）；
	#   - 内容更高时，用 custom_minimum_size.y 把 HBoxContainer 撑高，避免内容被裁掉。
	# ⚠️ 菜单里的 Label 不要开 autowrap：自动换行时 Label 的最小高度取决于当前宽度，
	#    在没有排过版的瞬间会被算成"一行一个字"，把面板撑到几百像素高。
	#    需要多行就用固定短文本，或用两个 Label 手动分行。
	_animate_height(menu.get_combined_minimum_size().y + MENU_PADDING_Y)

	# 无条件滑入：
	# 从 A 菜单点到 B 菜单时，ButtonGroup 会先弹起 A、再按下 B，A 的 toggled(false) 已经
	# 启动了"滑出"补间。这里如果再判断"已经展开了就不动"，那个滑出补间不会被取消，
	# 会一路跑完并把面板藏起来（表现就是：切换菜单 = 直接把侧边栏关了）。
	# _animate_slide 内部会 kill 掉旧补间，从当前位置接着往 0 走，所以重复调用没有副作用。
	_animate_slide(0.0)

	# 内容淡入：切菜单时不会"啪"地一下换掉
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	menu.modulate.a = 0.0
	_fade_tween = create_tween()
	_fade_tween.tween_property(menu, "modulate:a", 1.0, 0.12)


func _close_menu() -> void:
	_open_button = null
	_animate_height(0.0)
	_animate_slide(MENU_WIDTH)


func _get_or_create_menu(button: SidebarIconButton) -> Control:
	if _menus.has(button):
		return _menus[button]
	if button.menu_scene == null:
		push_error("侧边栏按钮「%s」没有设置 menu_scene" % button.name)
		return null
	var menu := button.menu_scene.instantiate() as Control
	if menu == null:
		push_error("菜单场景根节点必须是 Control 类型：%s" % button.menu_scene.resource_path)
		return null
	menu.visible = false
	_menu_holder.add_child(menu)
	_menus[button] = menu
	# 菜单内容在打开期间变高/变矮时（例如招聘抽到角色后多出一块立绘区），重新量高度
	if not menu.minimum_size_changed.is_connected(_on_menu_min_size_changed):
		menu.minimum_size_changed.connect(_on_menu_min_size_changed)
	return menu


## 当前显示的菜单最小尺寸变了 —— 让抽屉高度跟着它走
func _on_menu_min_size_changed() -> void:
	if _open_button == null:
		return
	var menu: Control = _menus.get(_open_button)
	if menu == null or not menu.visible:
		return
	_animate_height(menu.get_combined_minimum_size().y + MENU_PADDING_Y)


# ---------------- 开合动画 ----------------

## 横向滑入 / 滑出：0 = 完全展开，MENU_WIDTH = 完全藏在右边
func _animate_slide(target: float) -> void:
	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()
	_slide_tween = create_tween()
	_slide_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_slide_tween.tween_method(_set_panel_x, _menu_panel.position.x, target, ANIM_TIME)
	if is_equal_approx(target, MENU_WIDTH):
		_slide_tween.tween_callback(_on_collapsed)


func _set_panel_x(value: float) -> void:
	_menu_panel.position.x = value


func _animate_height(target: float) -> void:
	if _height_tween != null and _height_tween.is_valid():
		_height_tween.kill()
	# 目标值比图标列矮时这个值不起作用（容器会把 MenuArea 拉伸到图标列高度），
	# 所以不用在这里特判，直接补间到 content + padding 即可。
	_height_tween = create_tween()
	_height_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_height_tween.tween_method(_set_menu_height, _menu_area.custom_minimum_size.y, target, ANIM_TIME)


func _set_menu_height(value: float) -> void:
	_menu_area.custom_minimum_size.y = value


func _on_collapsed() -> void:
	# 收完之后整块面板连同底板一起藏起来。
	# clip_contents 只裁剪绘制、不裁剪鼠标事件，不隐藏的话收起的菜单仍然会挡住下面的点击。
	_menu_panel.visible = false


func _collapse_immediately() -> void:
	_set_panel_x(MENU_WIDTH)
	_set_menu_height(0.0)
	_menu_panel.visible = false
