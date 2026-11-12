extends Control
## Modal cooking screen. Staging is a preview, inventory changes only on atomic craft.
const Book := preload("res://scripts/core/recipe_book.gd")
const InputSlot := preload("res://scripts/ui/craft_input_slot.gd")
const WAREHOUSE := preload("res://scenes/ui/menus/menu_warehouse.tscn")
var selected: RecipeData
var staged: Dictionary = {}
var warehouse: Control
var input_slots: Array[Control] = []
var _recipe_buttons: Dictionary = {}
var _inputs: HBoxContainer
var _dish_icon: TextureRect
var _dish_title: Label
var _dish_description: Label
var _requirements: Label
var _status: Label
var _craft_button: Button
var _feedback: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	EventBus.inventory_changed.connect(_inventory_changed)
	EventBus.inventory_reloaded.connect(_refresh)
	select_recipe(Book.all()[0])
	hide()

func open() -> void:
	staged.clear()
	_feedback.text = ""
	_refresh()
	show()

func close() -> void:
	staged.clear()
	hide()

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	# Prevent clicks and scrolling from reaching the farm camera under the modal.
	if event is InputEventMouse:
		accept_event()

func _label(text_value: String, font_size: int = 18) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("473b28"))
	return label

func _button(text_value: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size.y = 42
	button.pressed.connect(action)
	return button

func _column(parent: Node, width: float) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = width
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 14)
	parent.add_child(column)
	return column

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.05, 0.03, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1320, 780)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("d7cfac")
	style.border_color = Color("8f865f")
	style.set_border_width_all(3)
	style.set_corner_radius_all(20)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	panel.add_theme_color_override("font_color", Color("473b28"))
	center.add_child(panel)
	var content := _column(panel, 0)
	var header := HBoxContainer.new()
	content.add_child(header)
	var title := _label("奶娃料理台", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_button("关闭  ×", close))
	content.add_child(HSeparator.new())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 30)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)
	var left := _column(body, 280)
	warehouse = WAREHOUSE.instantiate()
	left.add_child(warehouse)
	warehouse.get_node("Title").text = "随身仓库"
	warehouse.get_node("Hint").hide()
	left.add_child(_label("整堆 / Shift 半堆 / 右键一个", 14))
	left.add_child(_label("拖到右侧所需材料格", 14))
	body.add_child(VSeparator.new())
	var middle := _column(body, 390)
	middle.add_child(_label("工作台", 24))
	_dish_icon = TextureRect.new()
	_dish_icon.custom_minimum_size = Vector2(128, 128)
	_dish_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_dish_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_dish_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	middle.add_child(_dish_icon)
	_dish_title = _label("", 24)
	middle.add_child(_dish_title)
	_dish_description = _label("", 15)
	_dish_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	middle.add_child(_dish_description)
	_requirements = _label("", 15)
	middle.add_child(_requirements)
	_inputs = HBoxContainer.new()
	_inputs.add_theme_constant_override("separation", 12)
	middle.add_child(_inputs)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	middle.add_child(actions)
	actions.add_child(_button("按菜谱备料", auto_fill))
	actions.add_child(_button("清空投料", clear_staged))
	_craft_button = _button("开始合成", craft_selected)
	middle.add_child(_craft_button)
	_status = _label("", 15)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	middle.add_child(_status)
	middle.add_child(_label("投料仅预览，合成时才扣库存", 14))
	body.add_child(VSeparator.new())
	var right := _column(body, 420)
	right.add_child(_label("菜谱 · 选择一道料理", 24))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	var list := _column(scroll, 390)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for recipe in Book.all():
		var button := _button("", select_recipe.bind(recipe))
		button.custom_minimum_size = Vector2(390, 92)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.icon = ItemDB.icon(recipe.output_id)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 52)
		button.text = "%s ×%d\n%s" % [recipe.display_name, recipe.output_amount, ingredients_text(recipe)]
		button.add_theme_font_size_override("font_size", 16)
		button.tooltip_text = recipe.description
		list.add_child(button)
		_recipe_buttons[recipe.id] = button
	content.add_child(HSeparator.new())
	_feedback = _label("", 17)
	content.add_child(_feedback)

func ingredients_text(recipe: RecipeData) -> String:
	var parts: PackedStringArray = []
	for id in recipe.ingredients:
		parts.append("%s×%d" % [ItemDB.display_name(id), int(recipe.ingredients[id])])
	return " + ".join(parts)

func select_recipe(recipe: RecipeData) -> void:
	selected = recipe
	staged.clear()
	for child in _inputs.get_children():
		_inputs.remove_child(child)
		child.queue_free()
	input_slots.clear()
	for id in selected.ingredients:
		var slot := InputSlot.new()
		slot.workbench = self
		slot.item_id = id
		_inputs.add_child(slot)
		input_slots.append(slot)
	for id in _recipe_buttons:
		_recipe_buttons[id].modulate = Color.WHITE if id == recipe.id else Color(0.78, 0.78, 0.78)
	var only_food := true
	for id in selected.ingredients:
		only_food = only_food and ItemDB.is_edible(id)
	if only_food:
		warehouse.show_food()
	else:
		warehouse.show_materials()
	_feedback.text = ""
	_refresh()

func can_stage(payload: Variant) -> bool:
	if selected == null or not payload is Dictionary or payload.get("kind") != "warehouse_item":
		return false
	var source: Variant = payload.get("source")
	if not is_instance_valid(source) or not source.valid_payload(payload):
		return false
	var id := String(payload.get("item_id", ""))
	var needed := int(selected.ingredients.get(id, 0))
	return needed > int(staged.get(id, 0)) and Inventory.get_amount(id) > int(staged.get(id, 0))

func stage(payload: Dictionary) -> void:
	if not can_stage(payload):
		return
	var id := String(payload.item_id)
	var current := int(staged.get(id, 0))
	var take := mini(int(payload.amount), mini(int(selected.ingredients[id]), Inventory.get_amount(id)) - current)
	staged[id] = current + take
	_feedback.text = ""
	_refresh()

func unstage(id: String) -> void:
	staged[id] = maxi(0, int(staged.get(id, 0)) - 1)
	_refresh()

func clear_staged() -> void:
	staged.clear()
	_refresh()

func auto_fill() -> void:
	staged.clear()
	for id in selected.ingredients:
		staged[id] = mini(int(selected.ingredients[id]), Inventory.get_amount(id))
	_feedback.text = ""
	_refresh()

func ready_to_craft() -> bool:
	if selected == null or not Book.can_make(selected):
		return false
	for id in selected.ingredients:
		if int(staged.get(id, 0)) != int(selected.ingredients[id]):
			return false
	return true

func craft_selected() -> void:
	if not ready_to_craft():
		_refresh()
		return
	if not Book.craft(selected):
		_refresh()
		return
	staged.clear()
	_feedback.text = "已合成 %s ×%d，自动放入食物仓库！" % [selected.display_name, selected.output_amount]
	warehouse.show_food()
	_refresh()

func _inventory_changed(_id: String, _amount: int) -> void:
	_refresh()

func _refresh() -> void:
	if selected == null:
		return
	for id in staged.keys():
		staged[id] = mini(int(staged[id]), Inventory.get_amount(id))
	_dish_icon.texture = ItemDB.icon(selected.output_id)
	_dish_title.text = "%s ×%d" % [selected.display_name, selected.output_amount]
	_dish_description.text = selected.description
	_requirements.text = "每份恢复饱腹值 %d" % roundi(ItemDB.get_item(selected.output_id).satiety_restore)
	for slot in input_slots:
		slot.refresh()
	_craft_button.disabled = not ready_to_craft()
	var shortage := Book.missing(selected)
	if not shortage.is_empty():
		_status.text = "还缺：" + shortage
	elif not Book.can_make(selected):
		_status.text = "食物仓库空间不足，请先整理或喂食"
	elif ready_to_craft():
		_status.text = "材料已备齐，可以合成"
	else:
		_status.text = "拖入所需材料，或点击按菜谱备料"
