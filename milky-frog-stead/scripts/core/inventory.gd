extends Node
## 全局库存与物品容器（Autoload，唯一真实数据源）。
##
## 数据模型：
##   containers = {
##     "warehouse": {
##       "id", "label", "max_stack", "allowed_tags",
##       "slots": [ {"item_id": "wheat", "amount": 12}, {"item_id": "", "amount": 0}, ... ]
##     },
##     "shelf": {...},
##     "staff_3": {...},   # 员工装备栏，只允许 seed 标签的物品
##   }
##
## 规则：
##   - UI 只读 get_slot()/get_container()，所有修改必须走 add_item / remove_item / move_item；
##   - 每次数据变化发 inventory_changed，视图自己刷新；
##   - 拖拽模块只调用 can_move() / move_item()，不直接改 UI 或容器数组。
##
## 存档：get_save_data() 导出完整 containers；旧版扁平的
##       {"wheat": 12, "apple": 3} 会在 restore_data() 里自动迁移进仓库。

signal inventory_changed()

const MAX_STACK: int = 64
const WAREHOUSE_ID: String = "warehouse"
const BACKPACK_ID: String = "backpack"
const SHELF_ID: String = "shelf"
const STAFF_PREFIX: String = "staff_"
const DEFAULT_WAREHOUSE_SLOTS: int = 40
const DEFAULT_BACKPACK_SLOTS: int = 5
const DEFAULT_SHELF_SLOTS: int = 5

## 上游 master 的存档迁移 / 新游戏初始物资；并入后保留料理与喂食功能可直接体验。
const LEGACY_ITEM_IDS: Dictionary = {"fruit_salad": "veggie_salad", "milk_pudding": "egg_pudding"}
const REMOVED_ITEM_IDS: Array[String] = ["fish", "milk_fruit", "fish_bun"]
const STARTING_ITEMS: Dictionary = {
	"wheat": 12,
	"egg": 6,
	"tomato": 8,
	"turnip_seed": 4,
	"wheat_seed": 4,
}

## 物品定义：id -> 显示名 / 图标路径 / 标签。
## seed 标签决定员工装备栏能不能接收；warehouse / shelf 不限制。
const ITEM_DEFS: Dictionary = {
	"apple": {"name": "苹果", "icon": "res://assets/icons/items/apple.png", "tags": ["crop"]},
	"tomato": {"name": "番茄", "icon": "res://assets/icons/items/tomato.png", "tags": ["crop"]},
	"pumpkin": {"name": "南瓜", "icon": "res://assets/icons/items/pumpkin.png", "tags": ["crop"]},
	"wheat": {"name": "小麦", "icon": "res://assets/icons/items/wheat.png", "tags": ["crop", "seed"]},
}

## container_id -> 容器字典（唯一真实数据源）
var containers: Dictionary = {}

## 上游仓库/料理界面使用的仓库布局视图，直接指向真实仓库格子
var warehouse_slots: Array:
	get:
		return _slots_of(WAREHOUSE_ID)

var _icon_cache: Dictionary = {}


func _ready() -> void:
	_create_default_containers()


# ---------------- 容器查询 ----------------

func has_container(container_id: String) -> bool:
	return containers.has(container_id)


func get_container_ids() -> Array:
	var ids: Array = containers.keys()
	ids.sort()
	return ids


func get_container_label(container_id: String) -> String:
	var container: Dictionary = containers.get(container_id, {})
	return String(container.get("label", container_id))


func get_container_slot_count(container_id: String) -> int:
	var container: Dictionary = containers.get(container_id, {})
	var slots: Variant = container.get("slots", [])
	return (slots as Array).size() if slots is Array else 0


## 返回格子数据副本，UI 不应该直接修改内部数组
func get_slot(container_id: String, slot_index: int) -> Dictionary:
	if not _is_valid_slot(container_id, slot_index):
		return {"item_id": "", "amount": 0}
	var container: Dictionary = containers[container_id]
	var slots: Array = container["slots"]
	var slot: Dictionary = slots[slot_index]
	return slot.duplicate(true)


## 返回容器数据副本（调试/存档用；修改它不会影响库存）
func get_container(container_id: String) -> Dictionary:
	var container: Dictionary = containers.get(container_id, {})
	return container.duplicate(true)


func get_amount(item_id: String, container_id: String = "") -> int:
	var total := 0
	var ids: Array = [container_id] if not container_id.is_empty() else get_container_ids()
	for cid in ids:
		var container: Dictionary = containers.get(cid, {})
		var slots: Variant = container.get("slots", [])
		if not (slots is Array):
			continue
		for slot in slots:
			if String(slot.get("item_id", "")) == item_id:
				total += int(slot.get("amount", 0))
	return total


func is_empty(container_id: String = "") -> bool:
	var ids: Array = [container_id] if not container_id.is_empty() else get_container_ids()
	for cid in ids:
		var container: Dictionary = containers.get(cid, {})
		var slots: Variant = container.get("slots", [])
		if not (slots is Array):
			continue
		for slot in slots:
			if int(slot.get("amount", 0)) > 0:
				return false
	return true


func get_display_name(item_id: String) -> String:
	if ItemDB.has_item(item_id):
		return ItemDB.display_name(item_id)
	var def: Dictionary = ITEM_DEFS.get(item_id, {})
	return String(def.get("name", item_id))


func get_icon(item_id: String) -> Texture2D:
	if _icon_cache.has(item_id):
		return _icon_cache[item_id]
	var texture: Texture2D = ItemDB.icon(item_id)
	if texture == null:
		var def: Dictionary = ITEM_DEFS.get(item_id, {})
		var path := String(def.get("icon", ""))
		if path.is_empty() or not ResourceLoader.exists(path):
			return null
		texture = load(path) as Texture2D
	_icon_cache[item_id] = texture
	return texture


func get_item_tags(item_id: String) -> Array:
	var tags: Array = []
	var item: ItemData = ItemDB.get_item(item_id)
	if item != null:
		if item.is_seed:
			tags.append("seed")
		if item.is_edible:
			tags.append("food")
		if item.is_ingredient:
			tags.append("ingredient")
		if item.category == ItemData.Category.SEED and not tags.has("seed"):
			tags.append("seed")
		if item.category == ItemData.Category.DISH and not tags.has("food"):
			tags.append("food")
	var def: Dictionary = ITEM_DEFS.get(item_id, {})
	var fallback: Variant = def.get("tags", [])
	if fallback is Array:
		for tag in fallback:
			if not tags.has(tag):
				tags.append(tag)
	return tags


## 目标容器是否允许这个物品
func container_allows(container_id: String, item_id: String) -> bool:
	var container: Dictionary = containers.get(container_id, {})
	var allowed: Variant = container.get("allowed_tags", [])
	if not (allowed is Array) or (allowed as Array).is_empty():
		return true
	var tags := get_item_tags(item_id)
	for tag in allowed:
		if tags.has(tag):
			return true
	return false


## 兼容旧 UI：按 item_id 汇总所有容器的数量
func get_entries() -> Array:
	var totals: Dictionary = {}
	for cid in get_container_ids():
		var container: Dictionary = containers[cid]
		var slots: Array = container["slots"]
		for slot in slots:
			var item_id := String(slot.get("item_id", ""))
			var amount := int(slot.get("amount", 0))
			if item_id.is_empty() or amount <= 0:
				continue
			totals[item_id] = int(totals.get(item_id, 0)) + amount

	var ids: Array = totals.keys()
	ids.sort()
	var out: Array = []
	for item_id in ids:
		out.append({
			"id": String(item_id),
			"name": get_display_name(String(item_id)),
			"amount": int(totals[item_id]),
			"icon": get_icon(String(item_id)),
		})
	return out


# ---------------- 容器创建 / 重置 ----------------

func ensure_container(container_id: String, slot_count: int, label: String, allowed_tags: Array = []) -> Dictionary:
	if containers.has(container_id):
		var existing: Dictionary = containers[container_id]
		var slots: Variant = existing.get("slots", [])
		if not (slots is Array):
			existing["slots"] = []
			slots = existing["slots"]
		while (slots as Array).size() < slot_count:
			(slots as Array).append(_empty_slot())
		return existing

	var container := {
		"id": container_id,
		"label": label,
		"max_stack": MAX_STACK,
		"allowed_tags": allowed_tags.duplicate(),
		"slots": [],
	}
	for i in range(slot_count):
		container["slots"].append(_empty_slot())
	containers[container_id] = container
	return container


## 员工装备栏：只有 seed 标签的物品能放进来（小麦带 seed 标签）
func ensure_staff_container(staff_id: int) -> Dictionary:
	return ensure_container("%s%d" % [STAFF_PREFIX, staff_id], 1, "员工装备", ["seed"])


func _create_default_containers() -> void:
	containers.clear()
	ensure_container(WAREHOUSE_ID, DEFAULT_WAREHOUSE_SLOTS, "仓库")
	ensure_container(BACKPACK_ID, DEFAULT_BACKPACK_SLOTS, "背包")
	ensure_container(SHELF_ID, DEFAULT_SHELF_SLOTS, "货架")


func clear() -> void:
	_create_default_containers()
	_notify_reloaded()


## 新游戏初始物资：沿用 master 的开局库存，让料理 / 喂食功能可直接体验。
func reset_to_starting() -> void:
	_create_default_containers()
	for item_id in STARTING_ITEMS:
		var amount := int(STARTING_ITEMS[item_id])
		if amount <= 0:
			continue
		var remaining := _fill_existing_stacks(WAREHOUSE_ID, String(item_id), amount)
		_fill_empty_slots(WAREHOUSE_ID, String(item_id), remaining)
	_notify_reloaded()


# ---------------- 上游 master 兼容接口 ----------------

func add(item_id: String, amount: int = 1) -> void:
	add_item(item_id, amount, WAREHOUSE_ID)


func consume(item_id: String, amount: int = 1) -> bool:
	if amount <= 0:
		return true
	return remove_item_any(item_id, amount)


func has(item_id: String, amount: int = 1) -> bool:
	return get_amount(item_id) >= amount


## 从所有容器按仓库 → 背包 → 货架 → 员工装备顺序扣除
func remove_item_any(item_id: String, amount: int = 1) -> bool:
	if amount <= 0:
		return true
	if get_amount(item_id) < amount:
		return false
	var remaining := amount
	var order: Array[String] = [WAREHOUSE_ID, BACKPACK_ID, SHELF_ID]
	for cid in get_container_ids():
		if String(cid).begins_with(STAFF_PREFIX):
			order.append(String(cid))
	for cid in order:
		if remaining <= 0:
			break
		remaining -= _remove_item_partial(cid, item_id, remaining)
	if remaining > 0:
		return false
	_notify_changed(item_id)
	return true


func _remove_item_partial(container_id: String, item_id: String, amount: int) -> int:
	var removed := 0
	var slots := _slots_of(container_id)
	for i in range(slots.size() - 1, -1, -1):
		if removed >= amount:
			break
		var slot: Dictionary = slots[i]
		if String(slot.get("item_id", "")) != item_id:
			continue
		var take := mini(amount - removed, int(slot.get("amount", 0)))
		slot["amount"] = int(slot.get("amount", 0)) - take
		removed += take
		if int(slot["amount"]) <= 0:
			slot["item_id"] = ""
			slot["amount"] = 0
	return removed


## 料理：原料/产出都按整份校验；产出空间按仓库剩余格子粗校验。
func can_exchange(costs: Dictionary, outputs: Dictionary) -> bool:
	if costs.is_empty() or outputs.is_empty():
		return false
	for id in costs:
		if not ItemDB.has_item(String(id)) or int(costs[id]) <= 0:
			return false
		if get_amount(String(id)) < int(costs[id]):
			return false
	for id in outputs:
		if not ItemDB.has_item(String(id)) or int(outputs[id]) <= 0:
			return false
	var needed_slots := 0
	for id in outputs:
		needed_slots += ceili(float(outputs[id]) / float(maxi(1, mini(64, ItemDB.stack_max(String(id))))))
	return needed_slots <= _free_warehouse_slots() + _existing_capacity(String(outputs.keys()[0]))


func exchange(costs: Dictionary, outputs: Dictionary) -> bool:
	if not can_exchange(costs, outputs):
		return false
	for id in costs:
		remove_item_any(String(id), int(costs[id]))
	for id in outputs:
		add_item(String(id), int(outputs[id]), WAREHOUSE_ID)
	_notify_reloaded()
	SaveManager.request_autosave()
	return true


func _free_warehouse_slots() -> int:
	var free := 0
	for slot in _slots_of(WAREHOUSE_ID):
		if int(slot.get("amount", 0)) <= 0:
			free += 1
	return free


func _existing_capacity(item_id: String) -> int:
	var capacity := 0
	for slot in _slots_of(WAREHOUSE_ID):
		if String(slot.get("item_id", "")) == item_id:
			capacity += maxi(0, 64 - int(slot.get("amount", 0)))
	return capacity


func _notify_changed(item_id: String = "") -> void:
	inventory_changed.emit()
	if item_id.is_empty():
		EventBus.inventory_reloaded.emit()
	else:
		EventBus.inventory_changed.emit(item_id, get_amount(item_id))


func _notify_reloaded() -> void:
	inventory_changed.emit()
	EventBus.inventory_reloaded.emit()


## 给外部视图（料理台仓库）修改布局后主动通知主 UI
func notify_inventory_changed() -> void:
	_notify_reloaded()


# ---------------- 修改（所有 UI 修改都走这里） ----------------

## 加物品到指定容器。返回没放进去的剩余数量（0 = 全部放入）。
func add_item(item_id: String, amount: int = 1, container_id: String = WAREHOUSE_ID) -> int:
	if item_id.is_empty() or amount <= 0:
		return amount
	if not containers.has(container_id):
		if container_id.begins_with(STAFF_PREFIX):
			ensure_container(container_id, 1, "员工装备", ["seed"])
		else:
			var label := "容器" if container_id != WAREHOUSE_ID else "仓库"
			ensure_container(container_id, DEFAULT_WAREHOUSE_SLOTS, label)
	if not container_allows(container_id, item_id):
		return amount

	var remaining := amount
	remaining = _fill_existing_stacks(container_id, item_id, remaining)
	remaining = _fill_empty_slots(container_id, item_id, remaining)
	if remaining < amount:
		_notify_changed(item_id)
	return remaining


## 从指定容器扣物品。数量不够时返回 false，库存保持不变。
func remove_item(item_id: String, amount: int = 1, container_id: String = WAREHOUSE_ID) -> bool:
	if amount <= 0:
		return true
	if get_amount(item_id, container_id) < amount:
		return false

	var remaining := amount
	var slots := _slots_of(container_id)
	for i in range(slots.size() - 1, -1, -1):
		var slot: Dictionary = slots[i]
		if String(slot.get("item_id", "")) != item_id:
			continue
		var take := mini(remaining, int(slot.get("amount", 0)))
		slot["amount"] = int(slot.get("amount", 0)) - take
		if int(slot["amount"]) <= 0:
			slot["item_id"] = ""
			slot["amount"] = 0
		remaining -= take
		if remaining <= 0:
			break
	if remaining <= 0:
		_notify_changed(item_id)
		return true
	return false


## 兼容接口：把某个物品的总量设为 amount（先清掉所有容器里的该物品，再放回仓库）
func set_item(item_id: String, amount: int) -> void:
	for cid in get_container_ids():
		var slots := _slots_of(cid)
		for slot in slots:
			if String(slot.get("item_id", "")) == item_id:
				slot["item_id"] = ""
				slot["amount"] = 0
	if amount > 0:
		add_item(item_id, amount, WAREHOUSE_ID)
	else:
		_notify_changed(item_id)


# ---------------- 拖拽核心：校验 + 移动 ----------------

## 能否把 from 槽的物品移到 to 槽。
## 返回 {"ok": bool, "mode": "move"/"merge"/"swap", "amount": int, "reason": String}
func can_move(from_container: String, from_slot: int, to_container: String, to_slot: int, amount: int = 0) -> Dictionary:
	if not _is_valid_slot(from_container, from_slot):
		return {"ok": false, "reason": "来源格子不存在"}
	if not _is_valid_slot(to_container, to_slot):
		return {"ok": false, "reason": "目标格子不存在"}
	if from_container == to_container and from_slot == to_slot:
		return {"ok": false, "reason": "已经在原位置"}

	var source := get_slot(from_container, from_slot)
	var source_item := String(source.get("item_id", ""))
	var source_amount := int(source.get("amount", 0))
	if source_item.is_empty() or source_amount <= 0:
		return {"ok": false, "reason": "来源格子是空的"}

	var move_amount := source_amount if amount <= 0 else mini(amount, source_amount)
	var target := get_slot(to_container, to_slot)
	var target_item := String(target.get("item_id", ""))
	var target_amount := int(target.get("amount", 0))

	if not container_allows(to_container, source_item):
		return {"ok": false, "reason": "目标容器不接受「%s」" % get_display_name(source_item)}

	var target_max := _max_stack(to_container)
	if target_item.is_empty():
		var movable := mini(move_amount, target_max)
		if movable <= 0:
			return {"ok": false, "reason": "目标容器已满"}
		return {"ok": true, "mode": "move", "amount": movable}

	if target_item == source_item:
		var free := target_max - target_amount
		var movable := mini(move_amount, free)
		if movable <= 0:
			return {"ok": false, "reason": "目标格子已堆满"}
		return {"ok": true, "mode": "merge", "amount": movable}

	# 不同物品：交换两格。交换后两边都必须能接受对方物品。
	if not container_allows(from_container, target_item):
		return {"ok": false, "reason": "来源容器不接受「%s」" % get_display_name(target_item)}
	var source_max := _max_stack(from_container)
	if target_amount > source_max or source_amount > target_max:
		return {"ok": false, "reason": "交换后超过堆叠上限"}
	return {"ok": true, "mode": "swap", "amount": source_amount}


func move_item(from_container: String, from_slot: int, to_container: String, to_slot: int, amount: int = 0) -> Dictionary:
	var check := can_move(from_container, from_slot, to_container, to_slot, amount)
	if not bool(check.get("ok", false)):
		return check

	var source: Dictionary = _slots_of(from_container)[from_slot]
	var target: Dictionary = _slots_of(to_container)[to_slot]
	var mode := String(check.get("mode", "move"))
	var item_id := String(source.get("item_id", ""))

	if mode == "swap":
		var source_copy: Dictionary = source.duplicate(true)
		source["item_id"] = target.get("item_id", "")
		source["amount"] = int(target.get("amount", 0))
		target["item_id"] = source_copy.get("item_id", "")
		target["amount"] = int(source_copy.get("amount", 0))
	else:
		var moved := int(check.get("amount", 0))
		source["amount"] = int(source.get("amount", 0)) - moved
		if int(source["amount"]) <= 0:
			source["item_id"] = ""
			source["amount"] = 0
		if String(target.get("item_id", "")).is_empty():
			target["item_id"] = item_id
			target["amount"] = 0
		target["amount"] = int(target.get("amount", 0)) + moved

	_notify_changed(item_id if not item_id.is_empty() else "")
	return {"ok": true, "mode": mode, "moved": int(check.get("amount", 0))}


## 拖拽数据 -> 目标格。DragManager 只调用这两个接口，不直接碰容器数组。
func can_move_data(data: Dictionary, to_container: String, to_slot: int) -> Dictionary:
	return can_move(
		String(data.get("from_container", "")),
		int(data.get("from_slot", -1)),
		to_container,
		to_slot,
		int(data.get("amount", 0))
	)


func move_data(data: Dictionary, to_container: String, to_slot: int) -> Dictionary:
	return move_item(
		String(data.get("from_container", "")),
		int(data.get("from_slot", -1)),
		to_container,
		to_slot,
		int(data.get("amount", 0))
	)


## 把某个容器里的物品尽量转回仓库（解雇员工时回收携带物）。放不下的部分留在原容器。
func return_container_to_warehouse(container_id: String) -> void:
	if container_id == WAREHOUSE_ID or not containers.has(container_id):
		return
	var slots := _slots_of(container_id)
	var changed := false
	for slot in slots:
		var item_id := String(slot.get("item_id", ""))
		var amount := int(slot.get("amount", 0))
		if item_id.is_empty() or amount <= 0:
			continue
		var remaining := _fill_existing_stacks(WAREHOUSE_ID, item_id, amount)
		remaining = _fill_empty_slots(WAREHOUSE_ID, item_id, remaining)
		var moved := amount - remaining
		if moved <= 0:
			continue
		changed = true
		slot["amount"] = amount - moved
		if int(slot["amount"]) <= 0:
			slot["item_id"] = ""
			slot["amount"] = 0
	if changed:
		_notify_reloaded()


# ---------------- 存档 ----------------

func get_save_data() -> Dictionary:
	return {
		"format": 2,
		"containers": containers.duplicate(true),
	}


func restore_data(data: Variant) -> void:
	containers.clear()
	var source: Dictionary = {}
	if data is Dictionary:
		source = data

	var payload: Variant = source.get("containers", null)
	if payload is Dictionary:
		var saved_containers: Dictionary = payload
		for cid in saved_containers.keys():
			var value: Variant = saved_containers[cid]
			if value is Dictionary:
				var container: Dictionary = value
				containers[String(cid)] = _normalize_container(String(cid), container)
	else:
		# 旧版扁平库存：{"wheat": 12, "apple": 3}
		_create_default_containers()
		for item_id in source.keys():
			var amount := int(source[item_id])
			if amount <= 0:
				continue
			var remaining := _fill_existing_stacks(WAREHOUSE_ID, String(item_id), amount)
			_fill_empty_slots(WAREHOUSE_ID, String(item_id), remaining)

	# 保证基础容器一定存在，并补齐格子
	ensure_container(WAREHOUSE_ID, DEFAULT_WAREHOUSE_SLOTS, "仓库")
	ensure_container(BACKPACK_ID, DEFAULT_BACKPACK_SLOTS, "背包")
	ensure_container(SHELF_ID, DEFAULT_SHELF_SLOTS, "货架")
	_migrate_legacy_item_ids()
	_notify_reloaded()


## 上游仓库/料理界面要的是「仓库这一页」的扁平总量；完整容器数据由 get_save_data() 输出。
func to_dict() -> Dictionary:
	var totals: Dictionary = {}
	for slot in _slots_of(WAREHOUSE_ID):
		var item_id := String(slot.get("item_id", ""))
		var amount := int(slot.get("amount", 0))
		if item_id.is_empty() or amount <= 0:
			continue
		totals[item_id] = int(totals.get(item_id, 0)) + amount
	return totals


func from_dict(data: Variant) -> void:
	restore_data(data)


func _migrate_legacy_item_ids() -> void:
	for container_id in get_container_ids():
		for slot in _slots_of(container_id):
			var item_id := String(slot.get("item_id", ""))
			if item_id.is_empty():
				continue
			var canonical := String(LEGACY_ITEM_IDS.get(item_id, item_id))
			if REMOVED_ITEM_IDS.has(canonical):
				slot["item_id"] = ""
				slot["amount"] = 0
			elif canonical != item_id:
				slot["item_id"] = canonical


# ---------------- 内部 ----------------

func _empty_slot() -> Dictionary:
	return {"item_id": "", "amount": 0}


func _slots_of(container_id: String) -> Array:
	var container: Dictionary = containers.get(container_id, {})
	var slots: Variant = container.get("slots", [])
	if slots is Array:
		return slots
	return []


func _is_valid_slot(container_id: String, slot_index: int) -> bool:
	if not containers.has(container_id):
		return false
	var slots := _slots_of(container_id)
	return slot_index >= 0 and slot_index < slots.size()


func _max_stack(container_id: String) -> int:
	var container: Dictionary = containers.get(container_id, {})
	return maxi(1, int(container.get("max_stack", MAX_STACK)))


func _fill_existing_stacks(container_id: String, item_id: String, amount: int) -> int:
	var remaining := amount
	var max_stack := _max_stack(container_id)
	var slots := _slots_of(container_id)
	for slot in slots:
		if String(slot.get("item_id", "")) != item_id:
			continue
		var current := int(slot.get("amount", 0))
		if current >= max_stack:
			continue
		var add := mini(remaining, max_stack - current)
		slot["amount"] = current + add
		remaining -= add
		if remaining <= 0:
			break
	return remaining


func _fill_empty_slots(container_id: String, item_id: String, amount: int) -> int:
	var remaining := amount
	var max_stack := _max_stack(container_id)
	var slots := _slots_of(container_id)
	for slot in slots:
		if int(slot.get("amount", 0)) > 0:
			continue
		var add := mini(remaining, max_stack)
		slot["item_id"] = item_id
		slot["amount"] = add
		remaining -= add
		if remaining <= 0:
			break
	return remaining


func _normalize_container(container_id: String, data: Dictionary) -> Dictionary:
	var default_slots := DEFAULT_WAREHOUSE_SLOTS
	var default_label := "容器"
	var default_tags: Array = []
	if container_id == WAREHOUSE_ID:
		default_slots = DEFAULT_WAREHOUSE_SLOTS
		default_label = "仓库"
	elif container_id == BACKPACK_ID:
		default_slots = DEFAULT_BACKPACK_SLOTS
		default_label = "背包"
	elif container_id == SHELF_ID:
		default_slots = DEFAULT_SHELF_SLOTS
		default_label = "货架"
	elif container_id.begins_with(STAFF_PREFIX):
		default_slots = 1
		default_label = "员工装备"
		default_tags = ["seed"]

	var max_stack := maxi(1, int(data.get("max_stack", MAX_STACK)))
	var allowed: Array = []
	var allowed_value: Variant = data.get("allowed_tags", default_tags)
	if allowed_value is Array:
		for tag in allowed_value:
			allowed.append(String(tag))
	elif not default_tags.is_empty():
		allowed = default_tags.duplicate()

	var slots: Array = []
	var raw_slots: Variant = data.get("slots", [])
	if raw_slots is Array:
		for entry in raw_slots:
			if entry is Dictionary:
				var slot: Dictionary = entry
				var item_id := String(slot.get("item_id", ""))
				var amount := clampi(int(slot.get("amount", 0)), 0, max_stack)
				var allowed_item := true
				if container_id.begins_with(STAFF_PREFIX):
					allowed_item = get_item_tags(item_id).has("seed")
				if item_id.is_empty() or amount <= 0 or not allowed_item:
					slots.append(_empty_slot())
				else:
					slots.append({"item_id": item_id, "amount": amount})
			else:
				slots.append(_empty_slot())

	while slots.size() < default_slots:
		slots.append(_empty_slot())

	# 员工装备栏永远是 seed-only，避免旧存档把它恢复成全开放
	if container_id.begins_with(STAFF_PREFIX):
		allowed = ["seed"]

	return {
		"id": container_id,
		"label": String(data.get("label", default_label)),
		"max_stack": max_stack,
		"allowed_tags": allowed,
		"slots": slots,
	}
