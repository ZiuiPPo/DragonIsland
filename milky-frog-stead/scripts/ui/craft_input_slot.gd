extends PanelContainer
var workbench: Control
var item_id: String = ""
var _count: Label

func _ready() -> void:
	custom_minimum_size = Vector2(104, 136)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color("eee3c7")
	style.border_color = Color("a9a17a")
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(10)
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	var icon := TextureRect.new()
	icon.texture = ItemDB.icon(item_id)
	icon.custom_minimum_size = Vector2(64, 64)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(icon)
	var title := Label.new()
	title.text = ItemDB.display_name(item_id)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("473b28"))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)
	_count = Label.new()
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_count)
	tooltip_text = "从左侧拖入；右键撤回一个投料预览"
	refresh()

func refresh() -> void:
	if _count == null or workbench == null:
		return
	var have := int(workbench.staged.get(item_id, 0))
	var need := int(workbench.selected.ingredients.get(item_id, 0))
	_count.text = "%d / %d" % [have, need]
	_count.add_theme_color_override("font_color", Color("477847") if have == need else Color("a45b37"))

func _can_drop_data(_pos: Vector2, payload: Variant) -> bool:
	return workbench != null and payload is Dictionary and payload.get("item_id") == item_id and workbench.can_stage(payload)

func _drop_data(_pos: Vector2, payload: Variant) -> void:
	if _can_drop_data(_pos, payload):
		workbench.stage(payload)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		workbench.unstage(item_id)
		accept_event()
