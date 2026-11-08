extends VBoxContainer
## 仓库 / 货架菜单：所有格子都绑定到 Inventory 的真实容器。
##
## 5 列 × 8 行 = 40 个仓库格，下面一行 5 个货架格，再下面是员工装备格。
## 仓库与货架都接受任意物品；员工装备栏的规则在 menu_npc_status 里。
##
## 视图不保存物品数据：格子显示由 ItemSlot 监听 Inventory.inventory_changed 刷新，
## 拖拽由 DragManager + ItemSlot 的放置接口驱动。

const COLUMNS: int = 5
const ROWS: int = 8
const BACKPACK_SLOTS: int = 5
const SHELF_SLOTS: int = 5

const SLOT_SCENE: PackedScene = preload("res://scenes/ui/item_slot.tscn")

@onready var _grid: GridContainer = %Grid
@onready var _backpack_row: HBoxContainer = %BackpackRow
@onready var _shelf_row: HBoxContainer = %ShelfRow
@onready var _equip_flow: HFlowContainer = %EquipFlow
@onready var _hint: Label = $Hint

var _warehouse_slots: Array[PanelContainer] = []
var _backpack_slots: Array[PanelContainer] = []
var _shelf_slots: Array[PanelContainer] = []


func _ready() -> void:
	_grid.columns = COLUMNS
	Inventory.ensure_container(Inventory.WAREHOUSE_ID, COLUMNS * ROWS, "仓库")
	Inventory.ensure_container(Inventory.BACKPACK_ID, BACKPACK_SLOTS, "背包")
	Inventory.ensure_container(Inventory.SHELF_ID, SHELF_SLOTS, "货架")
	_build_warehouse_slots()
	_build_backpack_slots()
	_build_shelf_slots()
	_rebuild_equipment_slots()

	Inventory.inventory_changed.connect(_on_inventory_changed)
	StaffRegistry.staff_changed.connect(_on_staff_changed)
	SaveManager.game_loaded.connect(_on_game_loaded)
	_update_hint()


# ---------------- 构建 ----------------

func _build_warehouse_slots() -> void:
	for i in range(COLUMNS * ROWS):
		var slot := SLOT_SCENE.instantiate() as PanelContainer
		_grid.add_child(slot)
		slot.call("bind", Inventory.WAREHOUSE_ID, i)
		_warehouse_slots.append(slot)


func _build_shelf_slots() -> void:
	for i in range(SHELF_SLOTS):
		var slot := SLOT_SCENE.instantiate() as PanelContainer
		_shelf_row.add_child(slot)
		slot.call("bind", Inventory.SHELF_ID, i)
		_shelf_slots.append(slot)


func _build_backpack_slots() -> void:
	for i in range(BACKPACK_SLOTS):
		var slot := SLOT_SCENE.instantiate() as PanelContainer
		_backpack_row.add_child(slot)
		slot.call("bind", Inventory.BACKPACK_ID, i)
		_backpack_slots.append(slot)


## 员工装备也放在仓库菜单里，保证仓库物品和员工装备栏同屏，可以直接拖。
## 员工状态菜单里也有一份视图，绑定的是同一个容器。
func _rebuild_equipment_slots() -> void:
	for child in _equip_flow.get_children():
		_equip_flow.remove_child(child)
		child.queue_free()

	if StaffRegistry.members.is_empty():
		var empty_label := Label.new()
		empty_label.text = "暂无员工"
		empty_label.add_theme_font_size_override("font_size", 12)
		empty_label.add_theme_color_override("font_color", Color(0.25, 0.2, 0.12, 0.5))
		_equip_flow.add_child(empty_label)
		return

	for member in StaffRegistry.members:
		Inventory.ensure_staff_container(member.id)
		var slot := SLOT_SCENE.instantiate() as PanelContainer
		slot.name = "StaffEquip_%d" % member.id
		_equip_flow.add_child(slot)
		slot.call("bind", "%s%d" % [Inventory.STAFF_PREFIX, member.id], 0)
		slot.call("set_default_tooltip", "%s 的装备（只能放种子）" % member.display_name)


# ---------------- 刷新提示 ----------------

func _on_inventory_changed() -> void:
	if SaveManager.is_restoring():
		return
	_update_hint()


func _on_staff_changed() -> void:
	if SaveManager.is_restoring():
		return
	_rebuild_equipment_slots()


func _on_game_loaded(_slot: int) -> void:
	_rebuild_equipment_slots()
	_update_hint()


func _update_hint() -> void:
	var used_warehouse := _count_occupied(Inventory.WAREHOUSE_ID)
	var used_backpack := _count_occupied(Inventory.BACKPACK_ID)
	var used_shelf := _count_occupied(Inventory.SHELF_ID)
	_hint.text = "仓库 %d/%d · 背包 %d/%d · 货架 %d/%d" % [
		used_warehouse, COLUMNS * ROWS,
		used_backpack, BACKPACK_SLOTS,
		used_shelf, SHELF_SLOTS,
	]


func _count_occupied(container_id: String) -> int:
	var count := 0
	for i in range(Inventory.get_container_slot_count(container_id)):
		var slot := Inventory.get_slot(container_id, i)
		if not String(slot.get("item_id", "")).is_empty() and int(slot.get("amount", 0)) > 0:
			count += 1
	return count
