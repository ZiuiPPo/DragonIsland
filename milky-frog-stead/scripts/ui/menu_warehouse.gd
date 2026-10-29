extends VBoxContainer
## 仓库菜单：5 列 × 8 行 = 40 格，每格最多 64 个同种物品（堆叠上限在 item_slot.gd 的 MAX_STACK）。
## 格子是运行时按 COLUMNS / ROWS 生成的，改这两个常量就能加格子，不用手摆节点。
## 现在填的是占位数据（_fill_demo），接真实仓库时把 _fill_demo 换成读 Inventory 即可。

const COLUMNS: int = 5
const ROWS: int = 8

const SLOT_SCENE: PackedScene = preload("res://scenes/ui/item_slot.tscn")

const ICON_APPLE: Texture2D = preload("res://assets/icons/items/apple.png")
const ICON_TOMATO: Texture2D = preload("res://assets/icons/items/pumpkin.png")
const ICON_PUMPKIN: Texture2D = preload("res://assets/icons/items/tomato.png")
const ICON_WHEAT: Texture2D = preload("res://assets/icons/items/wheat.png")

@onready var _grid: GridContainer = %Grid

var _slots: Array[PanelContainer] = []


func _ready() -> void:
	_grid.columns = COLUMNS
	_build_slots()
	_fill_demo()


# ---------------- 对外接口（以后接 Inventory 用这两个） ----------------

## 第 index 格放什么。texture 传 null 就是空格子。
func set_slot(index: int, texture: Texture2D, amount: int) -> void:
	if index < 0 or index >= _slots.size():
		return
	_slots[index].setup(texture, amount)


func clear_all() -> void:
	for slot in _slots:
		slot.clear()


func slot_count() -> int:
	return _slots.size()


# ---------------- 内部 ----------------

func _build_slots() -> void:
	for i in COLUMNS * ROWS:
		var slot := SLOT_SCENE.instantiate() as PanelContainer
		_grid.add_child(slot)
		_slots.append(slot)


## 占位数据：展示堆叠数量，后续替换成真实库存
func _fill_demo() -> void:
	clear_all()
	var demo := [
		[ICON_APPLE, 64],
		[ICON_TOMATO, 48],
		[ICON_PUMPKIN, 12],
		[ICON_WHEAT, 64],
		[ICON_APPLE, 32],
		[ICON_WHEAT, 7],
		[ICON_TOMATO, 64],
		[ICON_PUMPKIN, 3],
		[ICON_WHEAT, 21],
		[ICON_APPLE, 5],
	]
	for i in demo.size():
		set_slot(i, demo[i][0], demo[i][1])
