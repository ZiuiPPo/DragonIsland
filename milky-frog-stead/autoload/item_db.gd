extends Node
## 全部物品的统一注册表：扫描 data/items/*.tres，按 id 索引。
##
## 规则：任何系统要「产出 / 消耗 / 显示」物品时都先过 ItemDB，禁止在代码里散落字符串 ID。
## 启动时会把重复 ID / 空 ID / 目录异常 print 出来，无头 import 也能在日志里看到。

const ITEM_DIR := "res://data/items/"

## id: String -> ItemData
var _items: Dictionary = {}
## Category -> Array[String]
var _ids_by_category: Dictionary = {}


func _ready() -> void:
	reload()


## 重新扫描 data/items 目录（加物品资源后不用重启）
func reload() -> void:
	_items.clear()
	_ids_by_category.clear()
	var dir := DirAccess.open(ITEM_DIR)
	if dir == null:
		print("[ItemDB] 打不开目录：", ITEM_DIR)
		return
	var files := dir.get_files()
	files.sort()
	for file in files:
		if file.ends_with(".import"):
			continue
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var res: Variant = load(ITEM_DIR + file)
		if not (res is ItemData):
			print("[ItemDB] %s 不是 ItemData，已跳过" % file)
			continue
		var item: ItemData = res
		if item.id.is_empty():
			print("[ItemDB] %s 没有 id，已跳过" % file)
			continue
		if _items.has(item.id):
			print("[ItemDB] 物品 id 重复：%s（%s）" % [item.id, file])
			continue
		_items[item.id] = item
		if not _ids_by_category.has(item.category):
			_ids_by_category[item.category] = []
		_ids_by_category[item.category].append(item.id)


func has_item(id: String) -> bool:
	return _items.has(id)


func get_item(id: String) -> ItemData:
	return _items.get(id, null)


func icon(id: String) -> Texture2D:
	var item: ItemData = _items.get(id, null)
	return item.icon if item != null else null


func display_name(id: String) -> String:
	var item: ItemData = _items.get(id, null)
	return item.display_name if item != null else id


func stack_max(id: String) -> int:
	var item: ItemData = _items.get(id, null)
	return item.stack_max if item != null else 64


func all_ids() -> Array:
	var ids: Array = _items.keys()
	ids.sort()
	return ids


func ids_by_category(category: int) -> Array:
	var ids: Array = _ids_by_category.get(category, [])
	return ids.duplicate()


func count() -> int:
	return _items.size()
