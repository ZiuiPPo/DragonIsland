extends Node
## 统一产出入库口（Autoload）。
##
## 种地、养鸡（以及以后可能加的钓鱼 / 果树）产出的物品都走这里：
##   · 统一校验物品 id（没在 data/items 注册的 id 不会污染仓库）；
##   · 统一写 Inventory，仓库界面和存档只认 Inventory；
##   · 顺手记录「今天 / 累计」产出，给建筑界面显示统计。
##
## 注意：一次 produce 调用只入一次库；「重复点击不能重复产出」由调用方
## （地块的 RIPE 状态、鸡蛋的待收数量等）保证。

signal delivered(item_id: String, amount: int)

var _total: Dictionary = {}
var _today: Dictionary = {}


func _ready() -> void:
	GameClock.day_started.connect(_on_day_started)


func produce(item_id: String, amount: int = 1) -> int:
	if amount <= 0:
		return 0
	if not ItemDB.has_item(item_id):
		push_warning("[FarmOutput] 未知物品 id「%s」，本次产出已丢弃" % item_id)
		return 0
	Inventory.add(item_id, amount)
	_total[item_id] = int(_total.get(item_id, 0)) + amount
	_today[item_id] = int(_today.get(item_id, 0)) + amount
	delivered.emit(item_id, amount)
	return amount


func today_snapshot() -> Dictionary:
	return _today.duplicate()


func totals_snapshot() -> Dictionary:
	return _total.duplicate()


func total_of(item_id: String) -> int:
	return int(_total.get(item_id, 0))


func reset() -> void:
	_total.clear()
	_today.clear()


func _on_day_started(_day: int) -> void:
	_today.clear()
