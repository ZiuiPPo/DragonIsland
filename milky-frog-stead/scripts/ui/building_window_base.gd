extends Control
## 建筑独立页面基类。
##
## 农田页 / 鸡舍页都继承它，共用同一套外壳：
##   遮罩 → 居中大面板 → 标题栏（标题 / 天数 / 蛙币 / 返回建筑 / 关闭）→ 内容区 → 底部提示。
##
## 子类只需要实现：
##   page_title()  page_hint()  _build_body(parent)
## 需要的话再覆盖 _on_open() / _on_close() / _on_day_started() / _on_inventory_changed()。
##
## 信号：
##   back_requested  点「← 建筑」或按 Esc —— 由建筑中心页收回本页；
##   exit_requested  点「关闭 ×」 —— 退出整个建筑界面。

signal back_requested
signal exit_requested

const UI := preload("res://scripts/ui/building_ui.gd")
const WINDOW_SIZE := Vector2(1320, 780)

## 子类往这里挂内容
var body: VBoxContainer
var day_label: Label
var coin_label: Label

var _feedback_label: Label
var _feedback_tween: Tween = null
var _coin_counter: Node = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_shell()
	_build_body(body)
	_connect_bus_signals()
	_refresh_header()
	hide()


# ---------------- 给子类的接口 ----------------

func page_title() -> String:
	return "建筑"


## 返回按钮文字；商店等非建筑页可以覆盖
func back_button_text() -> String:
	return "← 建筑"


func page_hint() -> String:
	return "Esc / ← 建筑 返回建筑列表"


func _build_body(_parent: VBoxContainer) -> void:
	pass


func _on_open() -> void:
	pass


func _on_close() -> void:
	pass


func _on_day_started() -> void:
	pass


func _on_inventory_changed() -> void:
	pass


# ---------------- 对外开关 ----------------

func open() -> void:
	show()
	_refresh_header()
	_on_open()


func close() -> void:
	if not visible:
		return
	hide()
	_on_close()


func is_open() -> bool:
	return visible


## 底部提示条：操作反馈用（例如"买了 1 颗玉米种子"）
func show_feedback(text_value: String, color: Color = UI.TEXT_SOFT) -> void:
	if _feedback_label == null:
		return
	_feedback_label.text = text_value
	_feedback_label.add_theme_color_override("font_color", color)
	_feedback_label.modulate.a = 1.0
	if _feedback_tween != null and _feedback_tween.is_valid():
		_feedback_tween.kill()
	_feedback_tween = create_tween()
	_feedback_tween.tween_interval(2.2)
	_feedback_tween.tween_property(_feedback_label, "modulate:a", 0.0, 0.6)


# ---------------- 外壳 ----------------

func _build_shell() -> void:
	var dim := ColorRect.new()
	dim.color = UI.DIM_COLOR
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = WINDOW_SIZE
	panel.add_theme_stylebox_override("panel", UI.page_style())
	center.add_child(panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	panel.add_child(content)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	content.add_child(header)
	header.add_child(UI.title_label(String(page_title()), 32))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	day_label = UI.label("第 1 天", 16)
	header.add_child(day_label)
	coin_label = UI.label("蛙币 0", 16)
	header.add_child(coin_label)
	var back_button := UI.button(String(back_button_text()), 15, 38)
	back_button.pressed.connect(_on_back_button_pressed)
	header.add_child(back_button)
	var exit_button := UI.button("关闭 ×", 15, 38)
	exit_button.pressed.connect(_on_exit_button_pressed)
	header.add_child(exit_button)

	content.add_child(UI.divider())

	body = VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	content.add_child(body)

	content.add_child(UI.divider())
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	content.add_child(footer)
	_feedback_label = UI.label("", 15, UI.TEXT_SOFT)
	_feedback_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_feedback_label)
	var hint := UI.label(String(page_hint()), 13, UI.TEXT_SOFT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.add_child(hint)


func _connect_bus_signals() -> void:
	EventBus.inventory_changed.connect(_on_inventory_changed_signal)
	EventBus.inventory_reloaded.connect(_on_inventory_reloaded_signal)
	GameClock.day_started.connect(_on_day_started_signal)


func _refresh_header() -> void:
	if day_label != null:
		day_label.text = "第 %d 天 · %s" % [GameClock.day, GameClock.phase_name()]
	var counter := get_tree().get_first_node_in_group("coin_counter")
	if counter != _coin_counter:
		_coin_counter = counter
		if counter != null and counter.has_signal("gold_changed") 				and not counter.gold_changed.is_connected(_on_gold_changed_signal):
			counter.gold_changed.connect(_on_gold_changed_signal)
	if coin_label != null:
		if _coin_counter != null and _coin_counter.has_method("get_gold"):
			coin_label.text = "蛙币 %d" % int(_coin_counter.call("get_gold"))
		else:
			coin_label.text = "蛙币 -"


# ---------------- 信号转发 ----------------

func _on_back_button_pressed() -> void:
	back_requested.emit()


func _on_exit_button_pressed() -> void:
	exit_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()


func _on_inventory_changed_signal(_item_id: String, _amount: int) -> void:
	_refresh_header()
	_on_inventory_changed()


func _on_inventory_reloaded_signal() -> void:
	_refresh_header()
	_on_inventory_changed()


func _on_day_started_signal(_day: int) -> void:
	_refresh_header()
	_on_day_started()


func _on_gold_changed_signal(_value: int) -> void:
	_refresh_header()