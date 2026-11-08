extends Node
## 奶蛙喂食与饱腹度（Autoload）。
##
## 数据：饱腹度存在 StaffMember.satiety（随名册一起存档）；
##       食物能不能喂、能恢复多少看 ItemData.satiety_restore（种子为 0 = 不能喂）。
## 消耗：只走 Inventory，保证和仓库/存档同一份账。
## 交互：拖拽切片可以直接调 feed(member_id, item_id)；员工状态面板的「喂食」按钮用 feed_with_available()。

signal changed
signal fed(member_id: int, item_id: String, satiety: float)

## 闲置大笑每秒消耗的体力
const LAUGH_ENERGY_PER_SECOND: float = 2.0


var _decay_timer: float = 0.0

func _process(delta: float) -> void:
	if get_tree().get_first_node_in_group("day_night_cycle") == null:
		return
	_decay_timer += delta
	if _decay_timer < 0.25:
		return
	_decay_timer = 0.0
	changed.emit()


## 只按实际大笑时长扣体力，走动和普通待机不扣这部分体力。
func consume_laugh_energy(member: StaffMember, seconds: float) -> void:
	if member == null or member.is_working or not member.is_laughing:
		return
	if get_tree().get_first_node_in_group("day_night_cycle") == null:
		return
	member.satiety = maxf(0.0, member.satiety - LAUGH_ENERGY_PER_SECOND * maxf(0.0, seconds))


## 喂一个指定食物给某只奶蛙；返回 true = 真的吃掉了。
func feed(member_id: int, item_id: String, source_slot: int = -1) -> bool:
	var member := _find_member(member_id)
	if member == null:
		return false
	var item: ItemData = ItemDB.get_item(item_id)
	if item == null or item.satiety_restore <= 0.0:
		EventBus.toast.emit("「%s」不能喂给奶蛙" % ItemDB.display_name(item_id))
		return false
	if member.satiety >= StaffMember.MAX_SATIETY - 0.01:
		EventBus.toast.emit("%s 已经吃饱了" % member.display_name)
		return false
	if not Inventory.has(item_id, 1):
		return false
	# Debit the dragged stack before inventory_changed reconciles the layout.
	if source_slot >= 0 and source_slot < Inventory.warehouse_slots.size():
		var entry := Inventory.warehouse_slots[source_slot]
		if entry.get("item_id") != item_id or int(entry.get("amount", 0)) <= 0:
			return false
		entry.amount -= 1
		if int(entry.amount) == 0:
			Inventory.warehouse_slots[source_slot] = {}
	if not Inventory.consume(item_id, 1):
		EventBus.toast.emit("仓库里没有「%s」了" % item.display_name)
		return false

	member.satiety = minf(StaffMember.MAX_SATIETY, member.satiety + item.satiety_restore)
	fed.emit(member_id, item_id, member.satiety)
	changed.emit()
	SaveManager.request_autosave()
	EventBus.toast.emit("%s 吃了「%s」，饱腹度 %.0f" % [member.display_name, item.display_name, member.satiety])
	return true


## 从仓库里挑一份能喂的食物喂过去（面板/调试入口）
func feed_with_available(member_id: int) -> bool:
	var item_id := best_food()
	if item_id.is_empty():
		EventBus.toast.emit("仓库里没有能喂给奶蛙的食物")
		return false
	return feed(member_id, item_id)


## 仓库里恢复量最高的一份可喂食物；没有返回空字符串
func best_food() -> String:
	var best := ""
	var best_score := -1.0
	for raw_id in ItemDB.all_ids():
		var id := String(raw_id)
		var item: ItemData = ItemDB.get_item(id)
		if item == null or item.satiety_restore <= 0.0:
			continue
		if Inventory.get_amount(id) <= 0:
			continue
		if item.satiety_restore > best_score:
			best_score = item.satiety_restore
			best = id
	return best


## 当前仓库里能喂的食物列表（UI 下拉/拖拽提示用）
func available_foods() -> Array:
	var out: Array = []
	for raw_id in ItemDB.all_ids():
		var id := String(raw_id)
		var item: ItemData = ItemDB.get_item(id)
		if item != null and item.satiety_restore > 0.0 and Inventory.get_amount(id) > 0:
			out.append(id)
	return out


func _find_member(member_id: int) -> StaffMember:
	if member_id <= 0:
		return null
	for member in StaffRegistry.members:
		if member.id == member_id:
			return member
	return null
