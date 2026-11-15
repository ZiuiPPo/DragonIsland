extends Control
## 建筑中心页（侧边栏「建筑」按钮打开）。
##
## 像一张"农场地图上的建筑入口"：两张立绘卡片，下面写清楚建筑里能做什么、
## 当前状态，点绿色按钮进入对应独立页面。

signal closed

const UI := preload("res://scripts/ui/building_ui.gd")
const FARM_WINDOW := preload("res://scripts/ui/building_farm_window.gd")
const COOP_WINDOW := preload("res://scripts/ui/building_coop_window.gd")
const SHOP_WINDOW := preload("res://scripts/ui/shop_window.gd")
const WHEAT_TEXTURE := preload("res://assets/plants/wheat.png")
const COOP_HOUSE_TEXTURE := preload("res://assets/sprites/decorations/farmland_set_20261105/house_egg.png")
const SHOP_ART := preload("res://assets/icons/gameplay_character/shop.png")

var _window_layer: Node
var _farm_window: Control = null
var _coop_window: Control = null
var _shop_window: Control = null
var _farm_status: Label = null
var _coop_status: Label = null
var _shop_status: Label = null
var _day_label: Label = null
var _coin_label: Label = null
var _active_kind: String = ""
var _coin_counter: Node = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_window_layer = get_parent()
	_build()
	EventBus.inventory_reloaded.connect(_refresh)
	FarmState.changed.connect(_refresh)
	CoopState.changed.connect(_refresh)
	GameClock.day_started.connect(_on_day_changed)
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
	panel.custom_minimum_size = Vector2(1180, 660)
	panel.add_theme_stylebox_override("panel", UI.page_style())
	center.add_child(panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	panel.add_child(content)

	# 标题栏
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	content.add_child(header)
	var title := UI.title_label("建筑", 36)
	header.add_child(title)
	var subtitle := UI.label("选择一座建筑，进入它的独立管理页面", 15, UI.INK_SOFT)
	subtitle.size_flags_vertical = Control.SIZE_SHRINK_END
	header.add_child(subtitle)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_day_label = UI.label("第 1 天", 15, UI.INK_SOFT)
	header.add_child(_day_label)
	_coin_label = UI.label("蛙币 0", 15, UI.GOLD_DARK)
	header.add_child(_coin_label)
	var exit_button := UI.button("关闭 ×", 14, 38)
	exit_button.pressed.connect(close)
	header.add_child(exit_button)
	content.add_child(UI.divider())

	# 三张建筑卡片
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 22)
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(cards)
	_farm_status = _make_building_card(
		cards, "farm", "农田",
		"翻土、播种、等作物按天长大，再把它们收进仓库；种子可在商店买，也能在农田页补货。",
		WHEAT_TEXTURE, 4, 3, Color("2f3d1f"),
		"进入农田", UI.GREEN
	)
	_coop_status = _make_building_card(
		cards, "coop", "鸡舍",
		"给食槽添小麦，看小鸡自己过来吃；吃饱的鸡会下蛋，蛋落在木地板上，点一下收进仓库。",
		COOP_HOUSE_TEXTURE, 1, 0, Color("3a2c1a"),
		"进入鸡舍", Color("a97c23")
	)
	_shop_status = _make_building_card(
		cards, "shop", "商店",
		"买种子、买小鸡、买鸡饲料；付完款立刻进仓库或鸡舍。",
		SHOP_ART, 1, 0, Color("2a2118"),
		"进入商店", Color("b07a32")
	)

	content.add_child(UI.divider())
	content.add_child(UI.wrapped_label(
		"建筑的产出一律进仓库；商店付款用蛙币；按 Esc 关闭建筑界面。钓鱼台、果园后续开放。", 12))


func _make_building_card(parent: Container, kind: String, title: String, description: String,
		art: Texture2D, art_hframes: int, art_frame: int, art_bg: Color,
		button_text: String, button_color: Color) -> Label:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UI.card_style())
	parent.add_child(card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	card.add_child(column)

	var art_panel := PanelContainer.new()
	art_panel.custom_minimum_size = Vector2(0, 190)
	art_panel.add_theme_stylebox_override("panel", UI.inner_style(art_bg, Color("2a1c0e")))
	column.add_child(art_panel)
	var art_rect := TextureRect.new()
	art_rect.texture = art
	art_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if art_hframes > 1:
		# 用 TextureRect 显示 4 帧素材的最后一帧：裁一张成熟植株当立绘
		var atlas := AtlasTexture.new()
		atlas.atlas = art
		var frame_width := art.get_width() / art_hframes
		atlas.region = Rect2(frame_width * art_frame, 0, frame_width, art.get_height())
		art_rect.texture = atlas
	art_panel.add_child(art_rect)

	var title_label := UI.title_label(title, 28)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title_label)

	var desc_label := UI.wrapped_label(description, 14, UI.INK_SOFT)
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(desc_label)

	var status_chip := UI.chip("", button_color, 13)
	status_chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(status_chip)
	var status_label := status_chip.get_child(0) as Label

	var enter_button := UI.colored_button(button_text, button_color, 17, 48)
	enter_button.pressed.connect(open_building.bind(kind))
	column.add_child(enter_button)
	return status_label


func _refresh() -> void:
	if _day_label != null:
		_day_label.text = "第 %d 天 · %s" % [GameClock.day, GameClock.phase_name()]
	var counter := get_tree().get_first_node_in_group("coin_counter")
	if counter != _coin_counter:
		_coin_counter = counter
		if counter != null and counter.has_signal("gold_changed") 				and not counter.gold_changed.is_connected(_on_gold_changed):
			counter.gold_changed.connect(_on_gold_changed)
	if _coin_label != null:
		_coin_label.text = "蛙币 %d" % int(_coin_counter.call("get_gold")) if _coin_counter != null 			else "蛙币 -"
	if _farm_status != null:
		_farm_status.text = "可收 %d · 生长中 %d · 共 %d 块地" % [
			FarmState.ripe_count(), FarmState.growing_count(), FarmState.PLOT_COUNT]
	if _coop_status != null:
		_coop_status.text = "小鸡 %d/%d · 饲料 %d · 地板蛋 %d" % [
			CoopState.chickens.size(), CoopState.MAX_CHICKENS,
			CoopState.trough_stock, CoopState.eggs_on_ground]
	if _shop_status != null:
		_shop_status.text = "小鸡 %d/%d · 饲料 %d · 累计收蛋 %d" % [
			CoopState.chickens.size(), CoopState.MAX_CHICKENS,
			CoopState.trough_stock, CoopState.total_collected]


func _on_day_changed(_day: int) -> void:
	_refresh()


func _on_gold_changed(_value: int) -> void:
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
	if kind == "shop":
		if not is_instance_valid(_shop_window):
			_shop_window = SHOP_WINDOW.new()
			_window_layer.add_child(_shop_window)
			_shop_window.back_requested.connect(_on_window_back)
			_shop_window.exit_requested.connect(_on_window_exit)
		return _shop_window
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
	if is_instance_valid(_shop_window):
		_shop_window.close()


func _close_windows() -> void:
	_hide_windows()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()