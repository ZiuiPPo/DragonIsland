extends "res://scripts/ui/building_window_base.gd"
## 农田建筑独立页面。
##
## 画面目标（参考星露谷/经营游戏的田地读法）：
##   · 一整片连续的土地，而不是几块大瓷砖浮在草上；
##   · 作物按生长阶段换帧、水平垂直都居中、占满格子的可视区域；
##   · 成长进度用一条很短的自绘圆角细条，成熟收成金色「可收」小徽章 + 轻微呼吸；
##   · 未成熟/成熟的状态靠画面本身就能读出来，不需要一直盯着难看的灰色进度条。
##
## 数据仍在 FarmState autoload，收获统一走 FarmOutput → Inventory。

const PLOT_COLUMNS: int = 6
const PLOT_ROWS: int = 3
const PLOT_COUNT: int = PLOT_COLUMNS * PLOT_ROWS
const PLOT_SIZE := Vector2(112, 112)
const PLOT_GAP := 10.0
const GRID_WIDTH: float = PLOT_COLUMNS * PLOT_SIZE.x + (PLOT_COLUMNS - 1) * PLOT_GAP
const GRID_HEIGHT: float = PLOT_ROWS * PLOT_SIZE.y + (PLOT_ROWS - 1) * PLOT_GAP
const GRASS_TEXTURE := preload("res://assets/tilesets/grass.png")
const SOIL_TEXTURE := preload("res://assets/tilesets/soil.png")
const PLANT_HEIGHT_RATIO: float = 0.68
const UI_REFRESH_INTERVAL: float = 0.12
const GRID_MARGIN: float = 12.0

var _field_view: Control
var _grid_root: Control
var _hover_panel: Panel
var _plot_buttons: Array[Button] = []
var _plot_floors: Array[TextureRect] = []
var _plant_sprites: Array = []
var _growth_bars: Array[Control] = []
var _ripe_badges: Array[Panel] = []
var _seed_rows: Dictionary = {}
var _seed_icon: TextureRect
var _seed_preview_label: Label
var _plot_info: Label
var _harvest_all_button: Button
var _stat_labels: Dictionary = {}
var _today_label: Label
var _inventory_label: Label
var _hover_plot: int = -1
var _live_accum: float = 0.0
var _anim_time: float = 0.0
var _grass_atlas: AtlasTexture
var _soil_atlas: AtlasTexture
var _frame_bbox_cache: Dictionary = {}
var _crop_scale_cache: Dictionary = {}


# ---------------- 基类接口 ----------------

func page_title() -> String:
	return "农田"


func page_hint() -> String:
	return "点空地翻土 · 选好种子点土播种 · 跨天成熟 · 点成熟作物收获 · Esc 返回建筑"


func _build_body(parent: VBoxContainer) -> void:
	if FarmState.PLOT_COUNT != PLOT_COUNT:
		push_warning("[农田页] 页面按 %d 块地绘制，但 FarmState 是 %d 块" % [PLOT_COUNT, FarmState.PLOT_COUNT])
	_grass_atlas = UI.tile_texture(GRASS_TEXTURE, 44)
	_soil_atlas = UI.tile_texture(SOIL_TEXTURE, 44)
	_plant_sprites.resize(PLOT_COUNT)

	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 16)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(main)

	_build_field_area(main)
	_build_side_panel(main)

	FarmState.changed.connect(_refresh)


# ---------------- 左边：田地 ----------------

func _build_field_area(main: HBoxContainer) -> void:
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	main.add_child(left)

	var field_panel := PanelContainer.new()
	field_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	field_panel.add_theme_stylebox_override("panel", UI.dark_style(Color("2f3d1f")))
	left.add_child(field_panel)

	_field_view = Control.new()
	_field_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_field_view.custom_minimum_size = Vector2(0, 470)
	_field_view.clip_contents = true
	_field_view.resized.connect(_layout_field)
	field_panel.add_child(_field_view)

	_field_view.add_child(UI.tiled_rect(GRASS_TEXTURE, 44))

	_grid_root = Control.new()
	_grid_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field_view.add_child(_grid_root)

	_field_view.add_child(UI.vignette(0.26))

	for i in range(PLOT_COUNT):
		_build_plot(i)

	_hover_panel = Panel.new()
	_hover_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(1.0, 0.94, 0.62, 0.10)
	hover_style.border_color = Color(1.0, 0.88, 0.42, 0.95)
	hover_style.set_border_width_all(3)
	hover_style.set_corner_radius_all(12)
	_hover_panel.add_theme_stylebox_override("panel", hover_style)
	_hover_panel.visible = false
	_grid_root.add_child(_hover_panel)

	# 田地下面一条信息栏：当前种子 + 地块说明 + 一键收获
	var info_bar := HBoxContainer.new()
	info_bar.add_theme_constant_override("separation", 12)
	left.add_child(info_bar)

	var seed_card := PanelContainer.new()
	seed_card.add_theme_stylebox_override("panel", UI.card_style())
	info_bar.add_child(seed_card)
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	seed_card.add_child(seed_row)
	var seed_slot := PanelContainer.new()
	seed_slot.custom_minimum_size = Vector2(38, 38)
	seed_slot.add_theme_stylebox_override("panel", UI.icon_slot_style())
	seed_row.add_child(seed_slot)
	_seed_icon = TextureRect.new()
	_seed_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_seed_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_seed_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_seed_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seed_slot.add_child(_seed_icon)
	_seed_preview_label = UI.label("当前种子", 14, UI.INK)
	seed_row.add_child(_seed_preview_label)

	_plot_info = UI.wrapped_label("把鼠标移到地块上查看状态。", 13, UI.INK_SOFT)
	_plot_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_bar.add_child(_plot_info)

	_harvest_all_button = UI.primary_button("一键收获", 14, 42)
	_harvest_all_button.custom_minimum_size.x = 112
	_harvest_all_button.pressed.connect(harvest_all)
	info_bar.add_child(_harvest_all_button)


func _build_plot(index: int) -> void:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.flat = true
	var empty := StyleBoxEmpty.new()
	button.add_theme_stylebox_override("normal", empty)
	button.add_theme_stylebox_override("hover", empty)
	button.add_theme_stylebox_override("pressed", empty)
	button.add_theme_stylebox_override("focus", empty)
	button.pressed.connect(_on_plot_pressed.bind(index))
	button.mouse_entered.connect(_on_plot_hovered.bind(index, true))
	button.mouse_exited.connect(_on_plot_hovered.bind(index, false))
	_grid_root.add_child(button)
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

	# 每块地一圈很淡的描边：未翻土时也能看出有 18 个格子，且不会像深色底板那么重
	var frame := Panel.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0, 0, 0, 0)
	frame_style.border_color = Color(0.18, 0.14, 0.08, 0.30)
	frame_style.set_border_width_all(2)
	frame_style.set_corner_radius_all(10)
	frame.add_theme_stylebox_override("panel", frame_style)
	button.add_child(frame)


	var bar := UI.growth_bar(Color("7ed24f"), 56.0, 5.0)
	bar.call("setup", Color("7ed24f"), Color(0.22, 0.16, 0.09, 0.78))
	bar.position = Vector2(PLOT_SIZE.x * 0.5 - 28.0, PLOT_SIZE.y * 0.85)
	bar.visible = false
	button.add_child(bar)
	_growth_bars.append(bar)

	var badge := Panel.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color("f2cd55")
	badge_style.border_color = Color("8a5a14")
	badge_style.set_border_width_all(2)
	badge_style.set_corner_radius_all(9)
	badge.add_theme_stylebox_override("panel", badge_style)
	badge.size = Vector2(46, 18)
	badge.position = Vector2(PLOT_SIZE.x * 0.5 - 23.0, 5.0)
	badge.pivot_offset = Vector2(23, 9)
	var badge_label := UI.label("可收", 11, Color("3f2b06"))
	badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(badge_label)
	badge.visible = false
	button.add_child(badge)
	_ripe_badges.append(badge)


# ---------------- 右边：商店和统计 ----------------

func _build_side_panel(main: HBoxContainer) -> void:
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 352
	right.add_theme_constant_override("separation", 8)
	main.add_child(right)

	right.add_child(UI.title_label("种子商店", 22))
	right.add_child(UI.wrapped_label("点一行选种子；播种会从仓库扣 1 颗，缺种子时在这里买。", 12))
	for crop in FarmState.crops():
		_build_seed_card(right, crop)

	right.add_child(UI.divider())
	right.add_child(UI.label("田地概况", 16, UI.INK))
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 6)
	right.add_child(stats)
	_stat_labels["growing"] = _add_stat_chip(stats, "生长中 0", UI.GREEN)
	_stat_labels["ripe"] = _add_stat_chip(stats, "可收 0", UI.GOLD_DARK)
	_stat_labels["idle"] = _add_stat_chip(stats, "空闲 0", Color("7a6a4a"))

	right.add_child(UI.label("今天产出", 16, UI.INK))
	_today_label = UI.wrapped_label("今天还没有产出", 13)
	right.add_child(_today_label)

	right.add_child(UI.label("仓库作物", 16, UI.INK))
	_inventory_label = UI.wrapped_label("还没有收获过作物", 13)
	right.add_child(_inventory_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	right.add_child(UI.wrapped_label(
		"作物按游戏日生长：玉米/南瓜 1 天，小麦/番茄 2 天。可以在侧栏「时间」菜单里推进时段来跨天。", 12))


func _build_seed_card(parent: VBoxContainer, crop: CropData) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.card_style(false))
	parent.add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	var select_button := UI.ghost_button("", 14, 58)
	select_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	select_button.icon = ItemDB.icon(String(crop.seed_item_id))
	select_button.expand_icon = true
	select_button.add_theme_constant_override("icon_max_width", 38)
	select_button.pressed.connect(select_seed.bind(String(crop.id)))
	row.add_child(select_button)

	var right_column := VBoxContainer.new()
	right_column.custom_minimum_size.x = 92
	right_column.add_theme_constant_override("separation", 3)
	row.add_child(right_column)
	var price_label := UI.label("%d 蛙币" % int(crop.buy_price), 12, UI.GOLD_DARK)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_column.add_child(price_label)
	var buy_button := UI.primary_button("买 1", 13, 32)
	buy_button.custom_minimum_size.x = 88
	buy_button.pressed.connect(buy_seed.bind(String(crop.id)))
	right_column.add_child(buy_button)

	_seed_rows[String(crop.id)] = {
		"panel": panel,
		"select": select_button,
		"buy": buy_button,
	}


func _add_stat_chip(parent: HBoxContainer, text_value: String, color: Color) -> Label:
	var chip := UI.chip(text_value, color, 12)
	parent.add_child(chip)
	return chip.get_child(0) as Label


# ---------------- 布局 ----------------

func _layout_field() -> void:
	if _field_view == null or _plot_buttons.is_empty():
		return
	var view_size := _field_view.size
	if view_size.x < 120.0 or view_size.y < 120.0:
		return
	var origin := Vector2(
		maxf(GRID_MARGIN, (view_size.x - GRID_WIDTH) * 0.5),
		maxf(GRID_MARGIN, (view_size.y - GRID_HEIGHT) * 0.5))
	_grid_root.position = origin
	for i in range(_plot_buttons.size()):
		var column := i % PLOT_COLUMNS
		var row := floori(float(i) / float(PLOT_COLUMNS))
		var button: Button = _plot_buttons[i]
		button.position = Vector2(
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
				_float_text(index, "翻土", Color(0.98, 0.93, 0.72))
				show_feedback("这块地翻好了，选好种子再点一下播种。")
		FarmState.State.TILLED:
			_plant_selected(index)
		FarmState.State.GROWING:
			var crop := FarmState.crop_by_id(FarmState.plot_crop_id(index))
			show_feedback("「%s」还在生长：%d%%，约需 %d 天。" % [
				_crop_name(crop), int(FarmState.growth_progress(index) * 100.0), _days_left(index)])
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
		_float_text(index, "播种", Color(0.75, 0.95, 0.55))
		show_feedback("种下了「%s」，成熟需要 %d 天。" % [crop.display_name, int(crop.grow_days)])


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
	show_feedback("收获「%s」×%d，已经放进仓库。" % [display_name, amount])
	_refresh()


func harvest_all() -> Dictionary:
	var totals := FarmState.harvest_all()
	if totals.is_empty():
		show_feedback("现在还没有成熟的作物。")
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
	for badge in _ripe_badges:
		if badge.visible:
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
	_refresh_seed_preview()
	_refresh_plot_info()
	_harvest_all_button.disabled = FarmState.ripe_count() == 0


func _refresh_plot(index: int) -> void:
	var state := FarmState.plot_state(index)
	var crop := FarmState.crop_by_id(FarmState.plot_crop_id(index))
	_plot_floors[index].texture = _grass_atlas if state == FarmState.State.UNTILLED else _soil_atlas

	var has_plant := crop != null and (state == FarmState.State.GROWING or state == FarmState.State.RIPE)
	var sprite: Sprite2D = _plant_sprites[index]
	if has_plant:
		if sprite == null or not is_instance_valid(sprite):
			sprite = Sprite2D.new()
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.z_index = 2
			_plot_buttons[index].add_child(sprite)
			_plant_sprites[index] = sprite
		sprite.visible = true
		sprite.texture = crop.plant_texture
		sprite.hframes = maxi(1, int(crop.plant_frames))
		sprite.modulate = Color(1, 1, 1, 1)
		_update_plant_visual(index)
	else:
		if sprite != null and is_instance_valid(sprite):
			sprite.visible = false

	var progress := FarmState.growth_progress(index)
	var bar: Control = _growth_bars[index]
	bar.visible = false
	bar.call("set_progress", progress)
	_ripe_badges[index].visible = state == FarmState.State.RIPE
	_ripe_badges[index].modulate.a = 1.0
	_plot_buttons[index].tooltip_text = _describe_plot(index)


func _update_plant_visual(index: int) -> void:
	var sprite: Sprite2D = _plant_sprites[index]
	if sprite == null or not is_instance_valid(sprite):
		return
	var crop := FarmState.crop_by_id(FarmState.plot_crop_id(index))
	if crop == null or crop.plant_texture == null:
		return
	var state := FarmState.plot_state(index)
	var progress := 1.0 if state == FarmState.State.RIPE else FarmState.growth_progress(index)
	var frame_count := maxi(1, int(crop.plant_frames))
	sprite.frame = clampi(roundi(progress * float(frame_count - 1)), 0, frame_count - 1)
	var scale_factor := _crop_scale(crop)
	sprite.scale = Vector2(scale_factor, scale_factor)
	var content_offset := _frame_content_offset(crop, sprite.frame)
	var anchor := Vector2(PLOT_SIZE.x * 0.5, PLOT_SIZE.y * 0.52)
	sprite.position = anchor - content_offset * scale_factor


## 作物贴图每帧的内容包围盒：用来把「植物本体」而不是「空白画布」对准格子中心。
## 结果缓存，第一次打开窗口时算一次即可（4 张图 × 4 帧 × 32×64）。
func _frame_bbox(crop: CropData, frame: int) -> Rect2:
	var key := "%s|%d" % [String(crop.id), frame]
	if _frame_bbox_cache.has(key):
		return _frame_bbox_cache[key]
	var texture := crop.plant_texture
	var hframes := maxi(1, int(crop.plant_frames))
	var frame_width := int(texture.get_width() / hframes) if texture != null else 32
	var frame_height := int(texture.get_height()) if texture != null else 64
	var bbox := Rect2(0, 0, frame_width, frame_height)
	var image: Image = texture.get_image() if texture != null else null
	if image != null:
		image = image.duplicate()
		image.convert(Image.FORMAT_RGBA8)
		var min_x := frame_width
		var min_y := frame_height
		var max_x := -1
		var max_y := -1
		for y in range(frame_height):
			for x in range(frame_width):
				if image.get_pixel(frame * frame_width + x, y).a > 0.06:
					min_x = mini(min_x, x)
					max_x = maxi(max_x, x)
					min_y = mini(min_y, y)
					max_y = maxi(max_y, y)
		if max_x >= 0 and max_y >= 0:
			bbox = Rect2(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
	_frame_bbox_cache[key] = bbox
	return bbox


func _frame_content_offset(crop: CropData, frame: int) -> Vector2:
	var texture := crop.plant_texture
	if texture == null:
		return Vector2.ZERO
	var hframes := maxi(1, int(crop.plant_frames))
	var frame_center := Vector2(
		float(texture.get_width() / hframes) * 0.5,
		float(texture.get_height()) * 0.5)
	return _frame_bbox(crop, frame).get_center() - frame_center


func _crop_scale(crop: CropData) -> float:
	var key := String(crop.id)
	if _crop_scale_cache.has(key):
		return float(_crop_scale_cache[key])
	var frame_count := maxi(1, int(crop.plant_frames))
	var max_height := 0.0
	for frame in range(frame_count):
		max_height = maxf(max_height, _frame_bbox(crop, frame).size.y)
	if max_height <= 0.0:
		max_height = 64.0
	var scale_factor := clampf(PLOT_SIZE.y * PLANT_HEIGHT_RATIO / max_height, 0.8, 4.0)
	# 番茄等成熟期比较宽的作物，再按宽度收一下，避免压到隔壁地块
	var max_width := 0.0
	for frame in range(frame_count):
		max_width = maxf(max_width, _frame_bbox(crop, frame).size.x)
	if max_width > 0.0:
		scale_factor = minf(scale_factor, PLOT_SIZE.x * 0.86 / max_width)
	scale_factor = clampf(scale_factor, 0.6, 4.0)
	_crop_scale_cache[key] = scale_factor
	return scale_factor


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
		var stock := Inventory.get_amount(String(crop.seed_item_id))
		var prefix := "✓ " if selected else ""
		select_button.text = "%s%s种子\n成熟 %d 天 · 库存 %d" % [
			prefix, crop.display_name, int(crop.grow_days), stock]
		select_button.add_theme_color_override("font_color", UI.GOLD_DARK if selected else UI.INK)
		select_button.add_theme_color_override("font_hover_color", UI.GOLD_DARK if selected else UI.INK)
		var buy_button: Button = row["buy"]
		buy_button.disabled = gold < int(crop.buy_price)


func _refresh_stats() -> void:
	var growing := FarmState.growing_count()
	var ripe := FarmState.ripe_count()
	var idle := PLOT_COUNT - growing - ripe
	(_stat_labels["growing"] as Label).text = "生长中 %d" % growing
	(_stat_labels["ripe"] as Label).text = "可收 %d" % ripe
	(_stat_labels["idle"] as Label).text = "空闲 %d" % idle

	var today := FarmOutput.today_snapshot()
	var parts: Array[String] = []
	var ids: Array = today.keys()
	ids.sort()
	for item_id in ids:
		parts.append("%s +%d" % [ItemDB.display_name(String(item_id)), int(today[item_id])])
	_today_label.text = "今天还没有产出" if parts.is_empty() else "  ".join(parts)

	var inventory_parts: Array[String] = []
	for crop in FarmState.crops():
		var amount := Inventory.get_amount(String(crop.yield_item_id))
		if amount > 0:
			inventory_parts.append("%s ×%d" % [crop.display_name, amount])
	_inventory_label.text = "还没有收获过作物" if inventory_parts.is_empty() else "  ".join(inventory_parts)


func _refresh_seed_preview() -> void:
	var crop := FarmState.crop_by_id(FarmState.selected_crop_id)
	if crop == null:
		return
	_seed_icon.texture = ItemDB.icon(String(crop.seed_item_id))
	_seed_preview_label.text = "当前种子：%s ×%d · %d 天成熟" % [
		crop.display_name, Inventory.get_amount(String(crop.seed_item_id)), int(crop.grow_days)]


func _refresh_plot_info() -> void:
	_plot_info.text = _describe_plot(_hover_plot) if _hover_plot >= 0 else 		"点空地翻土，选好种子后点土播种；成熟后点作物收获，进仓库。"


func _describe_plot(index: int) -> String:
	if index < 0 or index >= PLOT_COUNT:
		return ""
	var state := FarmState.plot_state(index)
	var crop := FarmState.crop_by_id(FarmState.plot_crop_id(index))
	match state:
		FarmState.State.UNTILLED:
			return "第 %d 块：空地，点一下翻土。" % (index + 1)
		FarmState.State.TILLED:
			var selected := FarmState.crop_by_id(FarmState.selected_crop_id)
			var stock := Inventory.get_amount(String(selected.seed_item_id)) if selected != null else 0
			return "第 %d 块：已翻土。当前选种「%s」（库存 %d），点一下播种。" % [
				index + 1, _crop_name(selected), stock]
		FarmState.State.GROWING:
			return "第 %d 块：「%s」生长中 %d%%，还需约 %d 天。" % [
				index + 1, _crop_name(crop), int(FarmState.growth_progress(index) * 100.0), _days_left(index)]
		FarmState.State.RIPE:
			return "第 %d 块：「%s」成熟了，点一下收获 %d~%d 个，自动进仓库。" % [
				index + 1, _crop_name(crop), int(crop.yield_min), int(crop.yield_max)]
	return ""


func _days_left(index: int) -> int:
	var crop := FarmState.crop_by_id(FarmState.plot_crop_id(index))
	if crop == null:
		return 0
	var planted_day := int(FarmState.plots[index]["planted_day"])
	return maxi(1, int(crop.grow_days) - (GameClock.day - planted_day))


func _on_plot_hovered(index: int, entered: bool) -> void:
	if entered:
		_hover_plot = index
		_hover_panel.position = _plot_buttons[index].position - Vector2(4, 4)
		_hover_panel.size = PLOT_SIZE + Vector2(8, 8)
		_hover_panel.visible = true
		_refresh_hover_bar()
	elif _hover_plot == index:
		_hover_plot = -1
		_hover_panel.visible = false
	_refresh_hover_bar()
	_refresh_plot_info()


## 生长进度条只在鼠标悬停时出现：平时画面里只留作物本身，画面更干净。
func _refresh_hover_bar() -> void:
	for i in range(_growth_bars.size()):
		var bar: Control = _growth_bars[i]
		bar.visible = i == _hover_plot and FarmState.plot_state(i) == FarmState.State.GROWING


# ---------------- 动效 ----------------

func _process(delta: float) -> void:
	if not visible:
		return
	_live_accum += delta
	_anim_time += delta
	if _live_accum < UI_REFRESH_INTERVAL:
		return
	_live_accum = 0.0
	for i in range(PLOT_COUNT):
		var state := FarmState.plot_state(i)
		var sprite: Sprite2D = _plant_sprites[i]
		if state == FarmState.State.GROWING:
			_update_plant_visual(i)
			var growth_bar: Control = _growth_bars[i]
			if growth_bar.visible:
				growth_bar.call("set_progress", FarmState.growth_progress(i))
			if sprite != null and is_instance_valid(sprite):
				sprite.rotation = sin(_anim_time * 1.8 + float(i) * 1.7) * 0.018
		elif state == FarmState.State.RIPE:
			var badge: Panel = _ripe_badges[i]
			if badge.visible:
				var pulse := 1.0 + 0.06 * sin(_anim_time * 4.0 + float(i))
				badge.scale = Vector2(pulse, pulse)
			if sprite != null and is_instance_valid(sprite):
				sprite.rotation = sin(_anim_time * 1.4 + float(i) * 1.9) * 0.012


func _float_text(index: int, text_value: String, color: Color) -> void:
	if index < 0 or index >= _plot_buttons.size():
		return
	var plot: Button = _plot_buttons[index]
	var label := UI.label(text_value, 17, color)
	label.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.02, 1.0))
	label.add_theme_constant_override("outline_size", 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(plot.position.x + PLOT_SIZE.x * 0.5 - 50.0, plot.position.y + 8.0)
	label.size = Vector2(100, 26)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid_root.add_child(label)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 34.0, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.6).set_delay(0.25)
	tween.chain().tween_callback(label.queue_free)


# ---------------- 生命周期 ----------------

func _on_open() -> void:
	_refresh()
	call_deferred("_layout_field")


func _on_day_started() -> void:
	_refresh()
	show_feedback("新的一天：成熟的作物可以收获了。")


func _on_inventory_changed() -> void:
	_refresh()


# ---------------- 工具 ----------------

func _crop_name(crop: CropData) -> String:
	return String(crop.display_name) if crop != null else "未知作物"