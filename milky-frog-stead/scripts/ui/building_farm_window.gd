extends "res://scripts/ui/building_window_base.gd"
## 农田建筑独立页面。
##
## 页面结构：
##   左边是 8 块地（4×2）的田地，右边是种子商店 / 产出统计 / 操作说明。
##   玩家点空地锄地，选好种子后点已锄地播种，跨天后成熟，点成熟地块收获。
##
## 数据都在 FarmState autoload 里，本页只负责「画出来 + 把点击转成数据操作」。
## 收获统一走 FarmOutput → Inventory，所以仓库/合成/存档都能直接认到产物。

const PLOT_COLUMNS: int = 4
const PLOT_ROWS: int = 2
const PLOT_COUNT: int = PLOT_COLUMNS * PLOT_ROWS
const PLOT_SIZE := Vector2(168, 168)
const PLOT_GAP: float = 20.0
const GRASS_TEXTURE := preload("res://assets/tilesets/grass.png")
const SOIL_TEXTURE := preload("res://assets/tilesets/soil.png")
const PLANT_FRAME_HEIGHT: float = 64.0

var _field_view: Control
var _field_plot_root: Control
var _plot_buttons: Array[Button] = []
var _plot_floors: Array[TextureRect] = []
var _plant_sprites: Array[Sprite2D] = []
var _progress_bars: Array[ProgressBar] = []
var _ripe_labels: Array[Label] = []
var _seed_rows: Dictionary = {}
var _plot_info: Label
var _status_label: Label
var _inventory_label: Label
var _today_label: Label
var _harvest_all_button: Button
var _hover_plot: int = -1
var _live_accum: float = 0.0
var _pulse_time: float = 0.0
var _grass_atlas: AtlasTexture
var _soil_atlas: AtlasTexture


# ---------------- 基类接口 ----------------

func page_title() -> String:
	return "农田"


func page_hint() -> String:
	return "点空地锄地 · 选种子播种 · 跨天成熟 · 点成熟地块收获 · Esc 返回建筑"


func _build_body(parent: VBoxContainer) -> void:
	# 草/土地贴图都是 11x5 的自动地形图集，第 0 块是带描边的转角。
	# 做整片底色要用「全填充」那格（第 4 行第 0 列，索引 44），平铺才没有网格线。
	_grass_atlas = UI.tile_texture(GRASS_TEXTURE, 44)
	_soil_atlas = UI.tile_texture(SOIL_TEXTURE, 44)

	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 18)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(main)

	# ---------- 左边：田地 ----------
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	main.add_child(left)

	var field_panel := PanelContainer.new()
	field_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	field_panel.add_theme_stylebox_override("panel", UI.dark_style(Color(0.13, 0.19, 0.10, 1.0)))
	left.add_child(field_panel)

	_field_view = Control.new()
	_field_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_field_view.clip_contents = true
	_field_view.custom_minimum_size = Vector2(0, 470)
	_field_view.resized.connect(_layout_plots)
	field_panel.add_child(_field_view)

	var grass_rect := UI.tiled_rect(GRASS_TEXTURE, 44)
	_field_view.add_child(grass_rect)

	_field_plot_root = Control.new()
	_field_plot_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field_plot_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_field_view.add_child(_field_plot_root)

	_plant_sprites.resize(PLOT_COUNT)
	for i in range(PLOT_COUNT):
		_build_plot(i)

	var info_row := HBoxContainer.new()
	info_row.add_theme_constant_override("separation", 12)
	left.add_child(info_row)
	_plot_info = UI.wrapped_label(
		"把鼠标移到地块上查看状态；点空地锄地，选好种子后点击已锄地播种，成熟后点击收获。", 14)
	_plot_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_row.add_child(_plot_info)
	_harvest_all_button = UI.button("一键收获", 15, 40)
	_harvest_all_button.custom_minimum_size.x = 120
	_harvest_all_button.pressed.connect(harvest_all)
	info_row.add_child(_harvest_all_button)

	# ---------- 右边：种子商店 + 统计 ----------
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 350
	right.add_theme_constant_override("separation", 8)
	main.add_child(right)

	right.add_child(UI.title_label("种子商店", 22))
	var seed_hint := UI.wrapped_label("点一行选种；买种子花蛙币，播种会从仓库扣 1 颗。", 13)
	right.add_child(seed_hint)
	for crop in FarmState.crops():
		_build_seed_row(right, crop)

	right.add_child(HSeparator.new())
	_status_label = UI.label("", 15, UI.TEXT_DARK)
	right.add_child(_status_label)

	right.add_child(UI.title_label("本页产出（今天）", 18))
	_today_label = UI.wrapped_label("今天还没有产出", 14)
	right.add_child(_today_label)

	right.add_child(UI.title_label("仓库里的作物", 18))
	_inventory_label = UI.wrapped_label("还没有收获过作物", 14)
	right.add_child(_inventory_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	right.add_child(UI.wrapped_label(
		"作物按游戏日生长：萝卜/生菜 1 天，小麦/番茄 2 天。可以在侧栏「时间」菜单里推进时段来跨天。", 13))

	FarmState.changed.connect(_refresh)


# ---------------- 构建 ----------------

func _build_plot(index: int) -> void:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.custom_minimum_size = PLOT_SIZE
	button.size = PLOT_SIZE
	var empty := StyleBoxEmpty.new()
	var hover := UI.card_style(true)
	hover.bg_color = Color(1.0, 0.95, 0.55, 0.10)
	button.add_theme_stylebox_override("normal", empty)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", empty)
	button.tooltip_text = "空地：点击锄地"
	button.pressed.connect(_on_plot_pressed.bind(index))
	button.mouse_entered.connect(_on_plot_hovered.bind(index, true))
	button.mouse_exited.connect(_on_plot_hovered.bind(index, false))
	_field_plot_root.add_child(button)
	_plot_buttons.append(button)

	var floor_rect := TextureRect.new()
	floor_rect.texture = _grass_atlas
	floor_rect.stretch_mode = TextureRect.STRETCH_TILE
	floor_rect.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	floor_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	floor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floor_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_child(floor_rect)
	_plot_floors.append(floor_rect)

	# 地块描边画在地板上面：不锄地也能看出这里有 8 块地，而不是一片糊在一起的草
	var frame := Panel.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	frame_style.border_color = Color(0.38, 0.28, 0.15, 0.95)
	frame_style.set_border_width_all(3)
	frame_style.set_corner_radius_all(10)
	frame.add_theme_stylebox_override("panel", frame_style)
	button.add_child(frame)

	var bar := UI.progress_bar(Color(0.55, 0.85, 0.35), 14.0)
	bar.position = Vector2(16, PLOT_SIZE.y - 30)
	bar.size = Vector2(PLOT_SIZE.x - 32, 14)
	bar.visible = false
	button.add_child(bar)
	_progress_bars.append(bar)

	var ripe_label := UI.label("可收", 15, Color(1.0, 0.88, 0.32, 1.0))
	ripe_label.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.02, 1.0))
	ripe_label.add_theme_constant_override("outline_size", 4)
	ripe_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ripe_label.position = Vector2(PLOT_SIZE.x * 0.5 - 32, 6)
	ripe_label.size = Vector2(64, 24)
	ripe_label.visible = false
	ripe_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(ripe_label)
	_ripe_labels.append(ripe_label)


func _build_seed_row(parent: VBoxContainer, crop: CropData) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.card_style(false))
	parent.add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	var select_button := UI.button("", 15, 54)
	select_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	select_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select_button.icon = ItemDB.icon(String(crop.seed_item_id))
	select_button.expand_icon = true
	select_button.add_theme_constant_override("icon_max_width", 34)
	select_button.pressed.connect(select_seed.bind(String(crop.id)))
	row.add_child(select_button)

	var buy_button := UI.button("买 1", 13, 54)
	buy_button.custom_minimum_size.x = 86
	buy_button.pressed.connect(buy_seed.bind(String(crop.id)))
	row.add_child(buy_button)

	_seed_rows[String(crop.id)] = {
		"panel": panel,
		"select": select_button,
		"buy": buy_button,
		"name": String(crop.display_name),
	}


# ---------------- 布局 ----------------

func _layout_plots() -> void:
	if _field_view == null or _plot_buttons.is_empty():
		return
	var view_size := _field_view.size
	# 窗口刚打开、还没排版时 size 可能是 0，等 resized 再摆
	if view_size.x < 50.0 or view_size.y < 50.0:
		return
	var field_size := Vector2(
		PLOT_COLUMNS * PLOT_SIZE.x + (PLOT_COLUMNS - 1) * PLOT_GAP,
		PLOT_ROWS * PLOT_SIZE.y + (PLOT_ROWS - 1) * PLOT_GAP)
	var origin := Vector2(
		maxf(16.0, (view_size.x - field_size.x) * 0.5),
		maxf(16.0, (view_size.y - field_size.y) * 0.5))
	for i in range(_plot_buttons.size()):
		var column := i % PLOT_COLUMNS
		var row := floori(float(i) / float(PLOT_COLUMNS))
		var button: Button = _plot_buttons[i]
		button.position = origin + Vector2(
			column * (PLOT_SIZE.x + PLOT_GAP),
			row * (PLOT_SIZE.y + PLOT_GAP))
		button.size = PLOT_SIZE


# ---------------- 交互 ----------------

func _on_plot_pressed(index: int) -> void:
	if index < 0 or index >= PLOT_COUNT:
		return
	var state := FarmState.plot_state(index)
	match state:
		FarmState.State.UNTILLED:
			if FarmState.till(index):
				_float_text(index, "锄地", Color(0.95, 0.9, 0.7))
				show_feedback("第 %d 块地锄好了，选好种子再点一下就能播种。" % (index + 1))
		FarmState.State.TILLED:
			_plant_selected(index)
		FarmState.State.GROWING:
			var crop := FarmState.crop_by_id(FarmState.plot_crop_id(index))
			show_feedback("「%s」还在生长（%d%%）。" % [
				_crop_name(crop), int(FarmState.growth_progress(index) * 100.0)])
		FarmState.State.RIPE:
			harvest(index)
	_refresh()


func _plant_selected(index: int) -> void:
	var crop := FarmState.crop_by_id(FarmState.selected_crop_id)
	if crop == null:
		return
	if not Inventory.has(String(crop.seed_item_id), 1):
		show_feedback("仓库里没有「%s」种子了，先在右边买 1 颗。" % crop.display_name)
		return
	if FarmState.plant(index, String(crop.id)):
		_float_text(index, "播种", Color(0.8, 0.95, 0.6))
		show_feedback("第 %d 块地种下了「%s」，%d 天后成熟。" % [index + 1, crop.display_name, crop.grow_days])


func select_seed(crop_id: String) -> void:
	if FarmState.set_selected_crop(crop_id):
		var crop := FarmState.crop_by_id(crop_id)
		show_feedback("已选中「%s」种子。" % _crop_name(crop))
		_refresh()


func buy_seed(crop_id: String) -> bool:
	var crop := FarmState.crop_by_id(crop_id)
	if crop == null:
		return false
	var price := int(crop.buy_price)
	var counter := get_tree().get_first_node_in_group("coin_counter")
	if counter == null or not counter.has_method("spend_gold"):
		show_feedback("现在买不了：找不到蛙币计数器。")
		return false
	if not bool(counter.call("spend_gold", price)):
		show_feedback("蛙币不够：买 1 颗「%s」种子需要 %d 蛙币。" % [crop.display_name, price])
		return false
	Inventory.add(String(crop.seed_item_id), 1)
	show_feedback("买了 1 颗「%s」种子（-%d 蛙币）。" % [crop.display_name, price])
	_refresh()
	return true


func harvest(index: int) -> void:
	var result := FarmState.harvest(index)
	if result.is_empty():
		show_feedback("这块地现在没有可收获的作物。")
		return
	var amount := int(result["amount"])
	var display_name := String(result["display_name"])
	_float_text(index, "+%d" % amount, Color(1.0, 0.86, 0.3))
	show_feedback("收获「%s」×%d，已自动进仓库。" % [display_name, amount])
	_refresh()


func harvest_all() -> Dictionary:
	var totals := FarmState.harvest_all()
	if totals.is_empty():
		show_feedback("现在没有成熟的作物。")
		return totals
	var parts: Array[String] = []
	for item_id in totals.keys():
		parts.append("%s×%d" % [ItemDB.display_name(String(item_id)), int(totals[item_id])])
	show_feedback("一键收获：" + "  ".join(parts))
	_refresh()
	return totals


func click_plot(index: int) -> void:
	_on_plot_pressed(index)


func plot_count() -> int:
	return _plot_buttons.size()


func visible_ripe_marker_count() -> int:
	var count := 0
	for label in _ripe_labels:
		if label.visible:
			count += 1
	return count


# ---------------- 刷新 ----------------

func _refresh() -> void:
	if _plot_buttons.is_empty():
		return
	for i in range(PLOT_COUNT):
		_refresh_plot(i)
	_refresh_seed_rows()
	_refresh_stats()
	_refresh_plot_info()
	_harvest_all_button.disabled = FarmState.ripe_count() == 0


func _refresh_plot(index: int) -> void:
	if index < 0 or index >= _plot_buttons.size():
		return
	var state := FarmState.plot_state(index)
	var crop_id := FarmState.plot_crop_id(index)
	var crop := FarmState.crop_by_id(crop_id)

	_plot_floors[index].texture = _grass_atlas if state == FarmState.State.UNTILLED else _soil_atlas

	var sprite: Sprite2D = _plant_sprites[index] if index < _plant_sprites.size() else null
	if (state == FarmState.State.GROWING or state == FarmState.State.RIPE) and crop != null:
		if sprite == null:
			sprite = Sprite2D.new()
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.z_index = 2
			_plot_buttons[index].add_child(sprite)
			_plant_sprites[index] = sprite
		sprite.visible = true
		sprite.texture = crop.plant_texture
		sprite.hframes = maxi(1, int(crop.plant_frames))
		sprite.modulate = crop.plant_tint
		var progress := 1.0 if state == FarmState.State.RIPE else FarmState.growth_progress(index)
		sprite.frame = clampi(roundi(progress * float(sprite.hframes - 1)), 0, sprite.hframes - 1)
		var frame_height := PLANT_FRAME_HEIGHT
		if crop.plant_texture != null:
			frame_height = maxf(float(crop.plant_texture.get_height()), 1.0)
		var scale_factor := (PLOT_SIZE.y * 0.62) / frame_height
		sprite.scale = Vector2(scale_factor, scale_factor)
		sprite.position = Vector2(PLOT_SIZE.x * 0.5, PLOT_SIZE.y * 0.68)
	else:
		if sprite != null:
			sprite.visible = false

	var bar: ProgressBar = _progress_bars[index]
	bar.visible = state == FarmState.State.GROWING
	bar.value = FarmState.growth_progress(index) * 100.0

	var ripe_label: Label = _ripe_labels[index]
	ripe_label.visible = state == FarmState.State.RIPE

	var button: Button = _plot_buttons[index]
	button.tooltip_text = _describe_plot(index)


func _refresh_seed_rows() -> void:
	var counter := get_tree().get_first_node_in_group("coin_counter")
	var gold := 0
	if counter != null and counter.has_method("get_gold"):
		gold = int(counter.call("get_gold"))
	for crop in FarmState.crops():
		var row: Dictionary = _seed_rows.get(String(crop.id), {})
		if row.is_empty():
			continue
		var selected := String(crop.id) == FarmState.selected_crop_id
		var panel: PanelContainer = row["panel"]
		panel.add_theme_stylebox_override("panel", UI.card_style(selected))
		var select_button: Button = row["select"]
		select_button.text = "%s种子
成熟 %d 天 · 库存 %d" % [
			crop.display_name, int(crop.grow_days), Inventory.get_amount(String(crop.seed_item_id))]
		var price := int(crop.buy_price)
		var buy_button: Button = row["buy"]
		buy_button.text = "买 1\n%d 蛙币" % price
		buy_button.disabled = gold < price


func _refresh_stats() -> void:
	var tilled := 0
	for plot in FarmState.plots:
		if int(plot["state"]) == FarmState.State.TILLED:
			tilled += 1
	_status_label.text = "地块：已锄 %d · 生长 %d · 可收 %d（共 %d 块）" % [
		tilled, FarmState.growing_count(), FarmState.ripe_count(), PLOT_COUNT]

	var today := FarmOutput.today_snapshot()
	var today_parts: Array[String] = []
	var ids: Array = today.keys()
	ids.sort()
	for item_id in ids:
		today_parts.append("%s +%d" % [ItemDB.display_name(String(item_id)), int(today[item_id])])
	_today_label.text = "今天还没有产出" if today_parts.is_empty() else "  ".join(today_parts)

	var inventory_parts: Array[String] = []
	for crop in FarmState.crops():
		var amount := Inventory.get_amount(String(crop.yield_item_id))
		if amount > 0:
			inventory_parts.append("%s ×%d" % [crop.display_name, amount])
	_inventory_label.text = "还没有收获过作物" if inventory_parts.is_empty() else "  ".join(inventory_parts)


func _refresh_plot_info() -> void:
	_plot_info.text = _describe_plot(_hover_plot) if _hover_plot >= 0 else 		"把鼠标移到地块上查看状态；点空地锄地，选好种子后点击已锄地播种，成熟后点击收获。"


func _describe_plot(index: int) -> String:
	if index < 0 or index >= PLOT_COUNT:
		return ""
	var state := FarmState.plot_state(index)
	var crop := FarmState.crop_by_id(FarmState.plot_crop_id(index))
	match state:
		FarmState.State.UNTILLED:
			return "第 %d 块地：空地。点击锄地。" % (index + 1)
		FarmState.State.TILLED:
			var selected := FarmState.crop_by_id(FarmState.selected_crop_id)
			return "第 %d 块地：已锄地。当前选种「%s」，库存 %d 颗；点击播种。" % [
				index + 1, _crop_name(selected),
				Inventory.get_amount(String(selected.seed_item_id)) if selected != null else 0]
		FarmState.State.GROWING:
			if crop == null:
				return "第 %d 块地：生长中。" % (index + 1)
			var planted_day := int(FarmState.plots[index]["planted_day"])
			var left_days := maxi(1, int(crop.grow_days) - (GameClock.day - planted_day))
			return "第 %d 块地：「%s」生长中 %d%%，还需约 %d 天。" % [
				index + 1, crop.display_name, int(FarmState.growth_progress(index) * 100.0), left_days]
		FarmState.State.RIPE:
			if crop == null:
				return "第 %d 块地：已成熟。" % (index + 1)
			return "第 %d 块地：「%s」已成熟，点击收获 %d~%d 个，自动进仓库。" % [
				index + 1, crop.display_name, int(crop.yield_min), int(crop.yield_max)]
	return ""


func _on_plot_hovered(index: int, entered: bool) -> void:
	if entered:
		_hover_plot = index
	else:
		if _hover_plot == index:
			_hover_plot = -1
	_refresh_plot_info()


# ---------------- 动效 ----------------

func _process(delta: float) -> void:
	if not visible:
		return
	_live_accum += delta
	_pulse_time += delta
	if _live_accum < 0.12:
		return
	_live_accum = 0.0
	# 只刷新会随时间变化的部分：生长进度条、可收标记呼吸、田地布局
	for i in range(PLOT_COUNT):
		var state := FarmState.plot_state(i)
		if state == FarmState.State.GROWING:
			_progress_bars[i].value = FarmState.growth_progress(i) * 100.0
			var sprite := _plant_sprites[i] if i < _plant_sprites.size() else null
			var crop := FarmState.crop_by_id(FarmState.plot_crop_id(i))
			if sprite != null and crop != null and sprite.hframes > 1:
				sprite.frame = clampi(roundi(FarmState.growth_progress(i) * float(sprite.hframes - 1)), 0, sprite.hframes - 1)
		elif state == FarmState.State.RIPE:
			_ripe_labels[i].modulate.a = 0.65 + 0.35 * sin(_pulse_time * 4.0)
			_ripe_labels[i].modulate.a = clampf(_ripe_labels[i].modulate.a, 0.4, 1.0)


func _float_text(index: int, text_value: String, color: Color) -> void:
	if index < 0 or index >= _plot_buttons.size():
		return
	var plot: Button = _plot_buttons[index]
	var label := UI.label(text_value, 17, color)
	label.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.02, 1.0))
	label.add_theme_constant_override("outline_size", 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = plot.position + Vector2(PLOT_SIZE.x * 0.5 - 50, 12)
	label.size = Vector2(100, 26)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field_view.add_child(label)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 36.0, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.6).set_delay(0.25)
	tween.chain().tween_callback(label.queue_free)


# ---------------- 生命周期 ----------------

func _on_open() -> void:
	_refresh()
	call_deferred("_layout_plots")


func _on_day_started() -> void:
	_refresh()
	show_feedback("新的一天：成熟的作物可以收获了。")


func _on_inventory_changed() -> void:
	_refresh()


# ---------------- 工具 ----------------

func _crop_name(crop: CropData) -> String:
	return String(crop.display_name) if crop != null else "未知作物"
