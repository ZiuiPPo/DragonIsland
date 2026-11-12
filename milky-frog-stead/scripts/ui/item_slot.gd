extends PanelContainer
## 仓库 / 背包里的一个格子：图标 + 右下角数量。
## 一格只放同一种物品，最多 MAX_STACK 个（超出部分应该另开一格）。

## 每格堆叠上限
const MAX_STACK: int = 64

var warehouse: Node
var slot_index: int = -1

@onready var _icon: TextureRect = $Icon
@onready var _count: Label = $Count


## 填入物品。texture 传 null 或 amount <= 0 就是空格子。
## amount 超过 MAX_STACK 会被夹到 64 —— 多出来的部分应该由调用方拆到下一格。
func setup(texture: Texture2D, amount: int, item_name: String = "") -> void:
	_icon.texture = texture
	_count.text = str(clampi(amount, 0, MAX_STACK)) if amount > 0 else ""
	tooltip_text = item_name


## 清空格子
func clear() -> void:
	setup(null, 0)

func _ready() -> void:
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _get_drag_data(_at_position: Vector2) -> Variant:
	return _begin_drag(false)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var payload: Variant = _begin_drag(true)
		if payload != null:
			force_drag(payload, _preview(payload))
		accept_event()

func _begin_drag(single: bool) -> Variant:
	if warehouse == null:
		return null
	var payload: Variant = warehouse.drag_payload(slot_index, single, Input.is_key_pressed(KEY_SHIFT))
	if payload != null and not single:
		set_drag_preview(_preview(payload))
	return payload

func _preview(payload: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.texture = ItemDB.icon(payload.item_id)
	icon.custom_minimum_size = Vector2(44, 44)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(icon)
	var label := Label.new()
	label.text = ItemDB.display_name(payload.item_id)
	box.add_child(label)
	return box

func _can_drop_data(_pos: Vector2, payload: Variant) -> bool:
	return warehouse != null and warehouse.can_transfer(payload, slot_index)

func _drop_data(_pos: Vector2, payload: Variant) -> void:
	warehouse.transfer(payload, slot_index)
