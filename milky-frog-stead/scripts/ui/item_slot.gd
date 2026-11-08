extends PanelContainer
## 一个库存格子（仓库 / 货架 / 员工装备栏通用）。
##
## 视图约定：
##   - 格子只绑定 container_id + slot_index；
##   - 显示内容永远从 Inventory 读取，不直接改图标/数量来做拖拽；
##   - 左键按下交给 DragManager 生成预览，真正移动由 Inventory.move_* 完成；
##   - Inventory.inventory_changed 后统一刷新自己。

const MAX_STACK: int = 64

@onready var _icon: TextureRect = $Icon
@onready var _count: Label = $Icon/Count

## 绑定的容器与格子索引；未绑定时只显示空格
var container_id: String = ""
var slot_index: int = -1
## 格子为空时显示的上下文提示（例如“阿青的装备”）；不存物品数据
var default_tooltip: String = ""


func _ready() -> void:
	Inventory.inventory_changed.connect(_on_inventory_changed)
	SaveManager.game_loaded.connect(_on_game_loaded)
	if not container_id.is_empty():
		refresh_from_data()


## 由菜单在生成格子时调用。允许在入树前绑定，真正的刷新等 _ready。
func bind(p_container_id: String, p_slot_index: int) -> void:
	container_id = p_container_id
	slot_index = p_slot_index
	if is_node_ready():
		refresh_from_data()


## 给空格显示上下文提示；有物品时会在物品信息前加上这行
func set_default_tooltip(text: String) -> void:
	default_tooltip = text
	if is_node_ready():
		refresh_from_data()


## 从真实库存数据刷新显示（唯一允许改图标/数量的入口）
func refresh_from_data() -> void:
	if container_id.is_empty() or slot_index < 0:
		_icon.texture = null
		_count.text = ""
		tooltip_text = default_tooltip
		return

	var slot := Inventory.get_slot(container_id, slot_index)
	var item_id := String(slot.get("item_id", ""))
	var amount := int(slot.get("amount", 0))
	if item_id.is_empty() or amount <= 0:
		_icon.texture = null
		_count.text = ""
		tooltip_text = default_tooltip
		return

	_icon.texture = Inventory.get_icon(item_id)
	_count.text = str(clampi(amount, 0, MAX_STACK))
	var item_tooltip := "%s × %d" % [Inventory.get_display_name(item_id), amount]
	tooltip_text = item_tooltip if default_tooltip.is_empty() else "%s\n%s" % [default_tooltip, item_tooltip]


func _on_inventory_changed() -> void:
	# 读档时等 SaveManager.game_loaded 统一刷新，避免读到半套数据
	if SaveManager.is_restoring():
		return
	refresh_from_data()


func _on_game_loaded(_slot: int) -> void:
	refresh_from_data()


# ---------------- 拖拽源 / 放置目标 ----------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			var slot := Inventory.get_slot(container_id, slot_index)
			if int(slot.get("amount", 0)) <= 0:
				return
			DragManager.begin_drag(self)
			accept_event()


## DragManager 用：只记录来源，不改库存
func get_drag_data() -> Dictionary:
	var slot := Inventory.get_slot(container_id, slot_index)
	return {
		"from_container": container_id,
		"from_slot": slot_index,
		"item_id": String(slot.get("item_id", "")),
		"amount": int(slot.get("amount", 0)),
	}


## 目标格能否接收。只查规则，不改数据。
func can_accept_drop(data: Dictionary) -> bool:
	if container_id.is_empty() or slot_index < 0:
		return false
	return bool(Inventory.can_move_data(data, container_id, slot_index).get("ok", false))


## 真正放置：走 Inventory，UI 由 inventory_changed 刷新。
func accept_drop(data: Dictionary) -> bool:
	if container_id.is_empty() or slot_index < 0:
		return false
	var result := Inventory.move_data(data, container_id, slot_index)
	return bool(result.get("ok", false))
