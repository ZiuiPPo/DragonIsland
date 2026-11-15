extends Control
## 建筑中心页（侧边栏「建筑」按钮打开）。
##
## 这里列出可以进入的建筑：
##   农田 —— 锄地 / 播种 / 按天生长 / 收获入库
##   鸡舍 —— 投喂小麦 / 鸡下蛋 / 点击收蛋入库
##
## 点「进入」后本页隐藏，打开对应的独立建筑页面；建筑页里点「← 建筑」再回来。
## 建筑页点「关闭 ×」或者本页按 Esc 时发出 closed，侧边栏负责把整个建筑层收起来。

signal closed

const UI := preload("res://scripts/ui/building_ui.gd")
const FARM_WINDOW := preload("res://scripts/ui/building_farm_window.gd")
const COOP_WINDOW := preload("res://scripts/ui/building_coop_window.gd")

var _window_layer: Node
var _farm_window: Control = null
var _coop_window: Control = null
var _farm_status: Label = null
var _coop_status: Label = null
var _active_kind: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_window_layer = get_parent()
	_build()
	EventBus.inventory_reloaded.connect(_refresh)
	FarmState.changed.connect(_refresh)
	CoopState.changed.connect(_refresh)
	GameClock.day_started.connect(_on_day_started)
	hide()


# ---------------- 对外开关 ----------------

func open() -> void:
	show()
	_refresh()


func close() -> void:
	_close_windows()
	_active_kind = ""
	hide()
	closed.emit()


func is_open() -> bool:
	return visible


func open_building(kind: String) -> void:
	var window := _ensure_window(kind)
	if window == null:
		return
	_active_kind = kind
	hide()
	window.open()


func active_building() -> String:
	return _active_kind


# ---------------- 界面 ----------------

func _build() -> void:
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
	panel.custom_minimum_size = Vector2(1000, 620)
	panel.add_theme_stylebox_override("panel", UI.page_style())
	center.add_child(panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	panel.add_child(content)

	# 标题栏
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	content.add_child(header)
	header.add_child(UI.title_label("建筑", 34))
	var subtitle := UI.label("选择一座建筑，进入独立的管理页面", 16, UI.TEXT_SOFT)
	subtitle.size_flags_vertical = Control.SIZE_SHRINK_END
	header.add_child(subtitle)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var exit_button := UI.button("关闭 ×", 15, 38)
	exit_button.pressed.connect(close)
	header.add_child(exit_button)
	content.add_child(HSeparator.new())

	# 两张建筑卡片
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 24)
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(cards)
	_farm_status = _make_building_card(
		cards, "farm", "农田",
		"锄地、播种、按游戏日生长、收获入库。\n4 种作物 · 8 块地 · 窗口内可买种子",
		"wheat"
	)
	_coop_status = _make_building_card(
		cards, "coop", "鸡舍",
		"投喂小麦、看小鸡吃食、捡地上的鸡蛋。\n3 只小鸡 · 鸡蛋自动入库",
		"egg"
	)

	content.add_child(HSeparator.new())
	var footer := UI.wrapped_label(
		"农田和鸡舍的产出都会自动进仓库；按 Esc 关闭建筑界面。", 13, UI.TEXT_SOFT)
	content.add_child(footer)


## 返回：这张卡片上的状态文字 Label（由 _refresh 更新）。
func _make_building_card(parent: Container, kind: String, title: String,
		description: String, icon_item_id: String) -> Label:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UI.card_style())

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	card.add_child(column)

	var icon := TextureRect.new()
	icon.texture = ItemDB.icon(icon_item_id)
	icon.custom_minimum_size = Vector2(0, 132)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(icon)

	var title_label := UI.title_label(title, 28)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title_label)

	var desc_label := UI.wrapped_label(description, 15, UI.TEXT_SOFT)
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(desc_label)

	var status_label := UI.label("", 15, UI.TEXT_DARK)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(status_label)

	column.add_child(_spacer())

	var enter_button := UI.button("进入 " + title, 18, 48)
	enter_button.pressed.connect(open_building.bind(kind))
	column.add_child(enter_button)

	parent.add_child(card)
	return status_label


func _spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return spacer


func _refresh() -> void:
	if _farm_status != null:
		_farm_status.text = "可收获 %d 块 · 生长中 %d 块 · 共 %d 块地" % [
			FarmState.ripe_count(), FarmState.growing_count(), FarmState.PLOT_COUNT,
		]
	if _coop_status != null:
		_coop_status.text = "饲料 %d 份 · 地上鸡蛋 %d 枚 · 累计收蛋 %d" % [
			CoopState.trough_stock, CoopState.eggs_on_ground, CoopState.total_collected,
		]


func _on_day_started(_day: int) -> void:
	_refresh()


# ---------------- 建筑页生命周期 ----------------

func _ensure_window(kind: String) -> Control:
	if kind == "farm":
		if not is_instance_valid(_farm_window):
			_farm_window = FARM_WINDOW.new()
			_window_layer.add_child(_farm_window)
			_farm_window.back_requested.connect(_on_window_back)
			_farm_window.exit_requested.connect(_on_window_exit)
		return _farm_window
	if kind == "coop":
		if not is_instance_valid(_coop_window):
			_coop_window = COOP_WINDOW.new()
			_window_layer.add_child(_coop_window)
			_coop_window.back_requested.connect(_on_window_back)
			_coop_window.exit_requested.connect(_on_window_exit)
		return _coop_window
	return null


func _on_window_back() -> void:
	_hide_windows()
	_active_kind = ""
	show()
	_refresh()


func _on_window_exit() -> void:
	close()


func _hide_windows() -> void:
	if is_instance_valid(_farm_window):
		_farm_window.close()
	if is_instance_valid(_coop_window):
		_coop_window.close()


func _close_windows() -> void:
	_hide_windows()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
