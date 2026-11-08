extends Node
## 所有物品库存的唯一入口。key 用 String，方便 JSON 存档。

## 主线暂未接生产系统：新游戏赠送食物供拖拽喂食，同时保留种子。
## 想改初始库存只改这里，别散落在场景脚本里。
const STARTING_ITEMS := {
	"wheat": 12,
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
	_items = data.duplicate()
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
