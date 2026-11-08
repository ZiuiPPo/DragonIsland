extends Node
## 所有物品库存的唯一入口。key 用 String，方便 JSON 存档。

## 主线暂未接生产系统：新游戏赠送食物供拖拽喂食，同时保留种子。
## 想改初始库存只改这里，别散落在场景脚本里。
# Save migration preserves renamed dishes and drops explicitly retired test items.
const LEGACY_ITEM_IDS := {"fruit_salad": "veggie_salad", "milk_pudding": "egg_pudding"}
const REMOVED_ITEM_IDS := ["fish", "milk_fruit", "fish_bun"]
const STARTING_ITEMS := {
	"wheat": 12,
	"egg": 6,
	"tomato": 8,
	"turnip_seed": 4,
	"wheat_seed": 4,
}

var warehouse_slots: Array[Dictionary] = []
var _items: Dictionary = {}

func _ready() -> void:
	for item_id in STARTING_ITEMS:
		_items[item_id] = int(_items.get(item_id, 0)) + int(STARTING_ITEMS[item_id])


func add(item_id: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	_items[item_id] = get_amount(item_id) + amount
	EventBus.inventory_changed.emit(item_id, int(_items[item_id]))

func consume(item_id: String, amount: int = 1) -> bool:
	if amount <= 0:
		return true
	if not has(item_id, amount):
		return false
	_items[item_id] = get_amount(item_id) - amount
	EventBus.inventory_changed.emit(item_id, int(_items[item_id]))
	return true

func has(item_id: String, amount: int = 1) -> bool:
	return get_amount(item_id) >= amount

func get_amount(item_id: String) -> int:
	return int(_items.get(item_id, 0))

func to_dict() -> Dictionary:
	return _items.duplicate()

func from_dict(data: Dictionary) -> void:
	warehouse_slots.clear()
	# JSON numbers load as floats; inventory quantities always remain integers.
	_items.clear()
	for item_id in data:
		if REMOVED_ITEM_IDS.has(String(item_id)):
			continue
		var canonical := String(LEGACY_ITEM_IDS.get(String(item_id), String(item_id)))
		_items[canonical] = int(_items.get(canonical, 0)) + maxi(0, int(data[item_id]))
	EventBus.inventory_reloaded.emit()

func clear() -> void:
	warehouse_slots.clear()
	_items.clear()
	EventBus.inventory_reloaded.emit()


## 新游戏用：清空后回到开局赠送（SaveManager.start_new_game 调）
func reset_to_starting() -> void:
	warehouse_slots.clear()
	_items.clear()
	for item_id in STARTING_ITEMS:
		_items[item_id] = int(STARTING_ITEMS[item_id])
	EventBus.inventory_reloaded.emit()

## Atomic recipe transaction: validate the whole exchange, then notify once.
func can_exchange(costs: Dictionary, outputs: Dictionary) -> bool:
	if costs.is_empty() or outputs.is_empty():
		return false
	var next := _items.duplicate()
	for id in costs:
		if not ItemDB.has_item(id) or int(costs[id]) <= 0 or get_amount(id) < int(costs[id]):
			return false
		next[id] = int(next.get(id, 0)) - int(costs[id])
	for id in outputs:
		if not ItemDB.has_item(id) or int(outputs[id]) <= 0:
			return false
		next[id] = int(next.get(id, 0)) + int(outputs[id])
	var food_slots := 0
	var material_slots := 0
	for id in next:
		var amount := int(next[id])
		if amount <= 0:
			continue
		var stacks := ceili(float(amount) / mini(64, maxi(1, ItemDB.stack_max(id))))
		if ItemDB.is_edible(id):
			food_slots += stacks
		else:
			material_slots += stacks
	return food_slots <= 20 and material_slots <= 20

func exchange(costs: Dictionary, outputs: Dictionary) -> bool:
	if not can_exchange(costs, outputs):
		return false
	for id in costs:
		_items[id] = get_amount(id) - int(costs[id])
	for id in outputs:
		_items[id] = get_amount(id) + int(outputs[id])
	EventBus.inventory_reloaded.emit()
	SaveManager.request_autosave()
	return true
