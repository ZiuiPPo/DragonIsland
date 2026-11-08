extends Node
## 全局拖拽管理器（Autoload）。
##
## 负责：
##   1. 鼠标按下时生成拖拽预览图标（不改库存、不改源格子显示）；
##   2. 预览跟随鼠标；
##   3. 鼠标抬起时找鼠标下的 ItemSlot，调用它的 can_accept_drop / accept_drop；
##   4. 放置成功由 Inventory.move_* 修改真实数据并发出 inventory_changed，UI 自己刷新；
##      放置失败 / 取消时只销毁预览，库存和 UI 原样不动。
##
## 拖拽数据只包含：
##   { from_container, from_slot, item_id, amount }
## 不包含 Node / Texture 引用。

var _dragging: bool = false
var _drag_data: Dictionary = {}

var _layer: CanvasLayer
var _root: Control
var _preview_icon: TextureRect
var _preview_count: Label


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "DragPreviewLayer"
	_layer.layer = 200
	add_child(_layer)

	_root = Control.new()
	_root.name = "DragPreviewRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_root)

	_preview_icon = TextureRect.new()
	_preview_icon.name = "PreviewIcon"
	_preview_icon.custom_minimum_size = Vector2(48, 48)
	_preview_icon.size = Vector2(48, 48)
	_preview_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_icon.visible = false
	_root.add_child(_preview_icon)

	_preview_count = Label.new()
	_preview_count.name = "PreviewCount"
	_preview_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_count.visible = false
	_preview_count.add_theme_font_size_override("font_size", 14)
	_preview_count.add_theme_color_override("font_color", Color(1, 0.98, 0.9, 1))
	_preview_count.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.03, 1))
	_preview_count.add_theme_constant_override("outline_size", 4)
	_root.add_child(_preview_count)

	set_process(false)


# ---------------- 对外 ----------------

func is_dragging() -> bool:
	return _dragging


## ItemSlot 左键按下时调用。source 只需要实现 get_drag_data()。
func begin_drag(source: Control) -> void:
	if _dragging:
		cancel_drag()
	if source == null or not source.has_method("get_drag_data"):
		return

	var data: Variant = source.call("get_drag_data")
	if not (data is Dictionary):
		return
	var drag_data: Dictionary = data
	var item_id := String(drag_data.get("item_id", ""))
	var amount := int(drag_data.get("amount", 0))
	if item_id.is_empty() or amount <= 0:
		return

	_drag_data = drag_data
	_dragging = true
	_preview_icon.texture = Inventory.get_icon(item_id)
	_preview_count.text = "×%d" % amount
	_preview_icon.visible = true
	_preview_count.visible = true
	_update_preview()
	set_process(true)


func cancel_drag() -> void:
	_clear_drag()


# ---------------- 输入 ----------------

func _process(_delta: float) -> void:
	if _dragging:
		_update_preview()


func _input(event: InputEvent) -> void:
	if not _dragging:
		return

	if event is InputEventMouseMotion:
		_update_preview()
		return

	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and not mouse.pressed:
			_finish_drag()
			get_viewport().set_input_as_handled()
		elif mouse.button_index == MOUSE_BUTTON_RIGHT and mouse.pressed:
			cancel_drag()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and key.keycode == KEY_ESCAPE:
			cancel_drag()
			get_viewport().set_input_as_handled()


# ---------------- 内部 ----------------

func _finish_drag() -> void:
	var target := _find_drop_target()
	if target != null:
		try_drop_on(target)
	# 无论成功还是非法/取消，预览都清掉；数据由 Inventory 决定是否变化
	_clear_drag()


## 对指定目标执行一次放置。鼠标路径会先用 _find_drop_target() 找到目标再调用这里；
## 也可以给键盘/脚本操作复用。返回是否真正发生了库存移动。
func try_drop_on(target: Control) -> bool:
	if not _dragging or target == null:
		return false
	if not target.has_method("can_accept_drop") or not target.has_method("accept_drop"):
		return false
	if not bool(target.call("can_accept_drop", _drag_data)):
		return false
	return bool(target.call("accept_drop", _drag_data))


func _find_drop_target() -> Control:
	var hovered := get_viewport().gui_get_hovered_control()
	while hovered != null:
		if hovered.has_method("can_accept_drop") and hovered.has_method("accept_drop"):
			return hovered
		var parent := hovered.get_parent()
		hovered = parent as Control
	return null


func _update_preview() -> void:
	var mouse := get_viewport().get_mouse_position()
	_preview_icon.position = mouse - _preview_icon.size * 0.5
	_preview_count.position = _preview_icon.position + Vector2(30, 26)


func _clear_drag() -> void:
	_dragging = false
	_drag_data = {}
	_preview_icon.visible = false
	_preview_icon.texture = null
	_preview_count.visible = false
	_preview_count.text = ""
	set_process(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and _dragging:
		cancel_drag()
