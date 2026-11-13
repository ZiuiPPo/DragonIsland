extends VBoxContainer
## 仓库菜单：原料与食物分页，各 20 格，共 40 格，每格最多 64 个同种物品（item_slot.MAX_STACK）。
##
## 数据来源只有两份：Inventory（真实库存）与 ItemDB（物品元数据/图标/堆叠上限）。
## 任何产出、消耗、读档后自动刷新（监听 EventBus.inventory_changed / inventory_reloaded）。
## 格子是运行时按 COLUMNS / ROWS 生成的，改这两个常量就能加格子。

const COLUMNS: int = 5
const ROWS: int = 8
const MATERIAL_SLOT_COUNT: int = 20
## 单格堆叠上限（和 item_slot.MAX_STACK 保持一致）
const STACK_PER_SLOT: int = 64

const SLOT_SCENE: PackedScene = preload("res://scenes/ui/craft_item_slot.tscn")

@onready var _material_grid: GridContainer = %MaterialGrid
@onready var _food_grid: GridContainer = %FoodGrid

var _showing_food: bool = false

var _slots: Array[PanelContainer] = []
## 每个格子当前显示的物品：{ item_id: String, amount: int }；空格子是 {}
var _display: Array = []


func _ready() -> void:
	_material_grid.columns = COLUMNS
	_food_grid.columns = COLUMNS
	_build_slots()
	%MaterialButton.pressed.connect(show_materials)
	%FoodButton.pressed.connect(show_food)
	show_materials()
	EventBus.inventory_changed.connect(_on_inventory_changed)
	EventBus.inventory_reloaded.connect(_refresh)
	_refresh()


## Switching changes visibility only; both pages use the same authoritative inventory.
func show_materials() -> void:
	_showing_food = false
	_update_page()

func show_food() -> void:
	_showing_food = true
	_update_page()

func _update_page() -> void:
	_material_grid.visible = not _showing_food
	_food_grid.visible = _showing_food
	%MaterialButton.set_pressed_no_signal(not _showing_food)
	%FoodButton.set_pressed_no_signal(_showing_food)

# ---------------- 对外接口 ----------------

## 第 index 格放什么。texture 传 null 就是空格子。
func set_slot(index: int, texture: Texture2D, amount: int, item_name: String = "") -> void:
	if index < 0 or index >= _slots.size():
		return
	_slots[index].setup(texture, amount, item_name)


func clear_all() -> void:
	for slot in _slots:
		slot.clear()
	for i in range(_display.size()):
		_display[i] = {}


func slot_count() -> int:
	return _slots.size()


## 当前每格显示的内容（测试/调试用，不暴露节点）
func display_slots() -> Array:
	return _display.duplicate(true)


# ---------------- 内部 ----------------

func _on_inventory_changed(_item_id: String, _amount: int) -> void:
	_refresh()


func _build_slots() -> void:
	for i in COLUMNS * ROWS:
		var slot := SLOT_SCENE.instantiate() as PanelContainer
		var grid := _material_grid if i < MATERIAL_SLOT_COUNT else _food_grid
		grid.add_child(slot)
		slot.warehouse = self
		slot.slot_index = i
		_slots.append(slot)



## Fixed category ranges also migrate legacy mixed layouts without changing inventory totals.
func _accepts_item(index: int, item_id: String) -> bool:
	var item: ItemData = ItemDB.get_item(item_id)
	if item == null:
		return false
	return ItemDB.is_edible(item_id) == (index >= MATERIAL_SLOT_COUNT)

## Preserve player stack layout; reconcile changes against the authoritative totals.
func _refresh() -> void:
	var layout := Inventory.warehouse_slots
	layout.resize(_slots.size())
	var remaining := Inventory.to_dict()
	for i in range(layout.size()):
		var entry: Dictionary = layout[i]
		var id := String(entry.get("item_id", ""))
		var take := maxi(0, mini(int(entry.get("amount", 0)), int(remaining.get(id, 0))))
		if not _accepts_item(i, id):
			take = 0
		take = mini(take, mini(STACK_PER_SLOT, maxi(1, ItemDB.stack_max(id))))
		layout[i] = {"item_id": id, "amount": take} if take > 0 else {}
		remaining[id] = int(remaining.get(id, 0)) - take
	var ids := remaining.keys()
	ids.sort()
	for raw_id in ids:
		var id := String(raw_id)
		var left := int(remaining[id])
		for i in range(layout.size()):
			if left <= 0:
				break
			if not _accepts_item(i, id):
				continue
			var entry: Dictionary = layout[i]
			if not entry.is_empty() and entry.item_id != id:
				continue
			var current := int(entry.get("amount", 0))
			var take := mini(left, mini(STACK_PER_SLOT, maxi(1, ItemDB.stack_max(id))) - current)
			if take > 0:
				layout[i] = {"item_id": id, "amount": current + take}
				left -= take
	_display = layout.duplicate(true)
	for i in range(_slots.size()):
		var entry: Dictionary = _display[i]
		var id := String(entry.get("item_id", ""))
		set_slot(i, ItemDB.icon(id) if not id.is_empty() else null, int(entry.get("amount", 0)), ItemDB.display_name(id) if not id.is_empty() else "")

func drag_payload(index: int, single: bool, half: bool) -> Variant:
	if index < 0 or index >= _display.size() or _display[index].is_empty():
		return null
	var entry: Dictionary = _display[index]
	var amount := int(entry.amount)
	if single:
		amount = 1
	elif half:
		amount = ceili(amount / 2.0)
	return {"kind": "warehouse_item", "source": self, "index": index, "item_id": entry.item_id, "amount": amount}

func valid_payload(payload: Variant) -> bool:
	if not payload is Dictionary or payload.get("kind") != "warehouse_item" or payload.get("source") != self:
		return false
	var index := int(payload.get("index", -1))
	if index < 0 or index >= _display.size():
		return false
	var entry: Dictionary = _display[index]
	return entry.get("item_id") == payload.get("item_id") and int(payload.get("amount", 0)) > 0 and int(entry.get("amount", 0)) >= int(payload.amount)

func can_transfer(payload: Variant, target: int) -> bool:
	if not valid_payload(payload) or target < 0 or target >= _display.size() or target == int(payload.index):
		return false
	if not _accepts_item(target, String(payload.item_id)):
		return false
	var entry: Dictionary = _display[target]
	return entry.is_empty() or (entry.item_id == payload.item_id and int(entry.amount) < mini(STACK_PER_SLOT, ItemDB.stack_max(payload.item_id)))

func transfer(payload: Dictionary, target: int) -> void:
	if not can_transfer(payload, target):
		return
	var layout := Inventory.warehouse_slots
	var entry: Dictionary = layout[target]
	var current := int(entry.get("amount", 0))
	var take := mini(int(payload.amount), mini(STACK_PER_SLOT, ItemDB.stack_max(payload.item_id)) - current)
	layout[target] = {"item_id": payload.item_id, "amount": current + take}
	var source := int(payload.index)
	layout[source].amount -= take
	if int(layout[source].amount) <= 0:
		layout[source] = {}
	_refresh()
	Inventory.notify_inventory_changed()
	SaveManager.request_autosave()
