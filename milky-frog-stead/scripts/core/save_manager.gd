extends Node
## 多槽位存档管理器（Autoload）。
##
## 存档目录：user://saves/slot_1.json … slot_3.json
## 槽位数量：SLOT_COUNT（默认 3）
##
## 只存纯数据：金币、员工名册、库存、仓库格子布局、天数/时刻、存档时间。
## 农场里的自动存档 / 手动保存 / 回主菜单前保存都写入当前 active_slot。
##
## 旧版单存档 user://save.json 会在启动时自动迁移到 1 号槽。

const SAVE_DIR: String = "user://saves"
const LEGACY_SAVE_PATH: String = "user://save.json"
const SLOT_COUNT: int = 3

## 测试隔离：--test-save 时所有槽位操作都落到这个文件，不碰正式存档
var _test_save_path: String = ""
const SAVE_VERSION: int = 1
const MIN_COMPATIBLE_VERSION: int = 1

const DEFAULT_GOLD: int = 500
## 老存档一次性演示补给：读档时补 10 小麦，方便直接进鸡舍喂鸡/演示
const DEMO_SUPPLY_WHEAT: int = 10
const SAVE_VERSION_LABEL: String = "v1"

const GAME_SCENE: String = "res://scenes/farm.tscn"
const MENU_SCENE: String = "res://scenes/main/scene_handler.tscn"

const AUTOSAVE_DELAY: float = 1.5

signal save_changed()
signal save_failed(message: String)
## 读档完成、数据全部恢复后发出
signal game_loaded(slot: int)

## 当前正在玩的槽位，0 = 尚未选择
var active_slot: int = 0

var _pending_gold: int = -1
var _session_active: bool = false
var _last_gold: int = DEFAULT_GOLD
var _autosave_timer: Timer
var _pending_clock: Dictionary = {}


func _ready() -> void:
	_apply_test_save_path()
	_ensure_save_dir()
	_migrate_legacy_save()
	_autosave_timer = Timer.new()
	_autosave_timer.name = "AutosaveDelay"
	_autosave_timer.one_shot = true
	_autosave_timer.wait_time = AUTOSAVE_DELAY
	_autosave_timer.timeout.connect(save_game)
	add_child(_autosave_timer)

	if not StaffRegistry.staff_changed.is_connected(request_autosave):
		StaffRegistry.staff_changed.connect(request_autosave)
	if not EventBus.inventory_changed.is_connected(_on_inventory_changed):
		EventBus.inventory_changed.connect(_on_inventory_changed)


# ---------------- 槽位基础 ----------------

func is_valid_slot(slot: int) -> bool:
	return slot >= 1 and slot <= SLOT_COUNT


func slot_file_name(slot: int) -> String:
	return "slot_%d.json" % slot


func slot_path(slot: int) -> String:
	if not _test_save_path.is_empty():
		return _test_save_path
	return "%s/%s" % [SAVE_DIR, slot_file_name(slot)]


func has_slot(slot: int) -> bool:
	return is_valid_slot(slot) and FileAccess.file_exists(slot_path(slot))


func has_any_save() -> bool:
	for slot in range(1, SLOT_COUNT + 1):
		if has_slot(slot):
			return true
	return false


## 兼容旧调用
func has_save() -> bool:
	return has_any_save()


func get_used_slot_count() -> int:
	var count := 0
	for slot in range(1, SLOT_COUNT + 1):
		if has_slot(slot):
			count += 1
	return count


func first_empty_slot() -> int:
	for slot in range(1, SLOT_COUNT + 1):
		if not has_slot(slot):
			return slot
	return 0


func first_loadable_slot() -> int:
	for slot in range(1, SLOT_COUNT + 1):
		if bool(get_slot_summary(slot).get("can_load", false)):
			return slot
	return 0


# ---------------- 摘要 / 校验 ----------------

func get_slot_summary(slot: int) -> Dictionary:
	var summary := {
		"slot": slot,
		"exists": false,
		"status": "empty",
		"status_text": "空槽位",
		"can_load": false,
		"gold": 0,
		"staff_count": 0,
		"day": 0,
		"saved_at": "",
		"scene": "",
		"version": 0,
	}
	if not has_slot(slot):
		return summary

	var inspect := _inspect_slot(slot)
	var data: Dictionary = inspect.get("data", {})
	var status := String(inspect.get("status", "corrupt"))
	var version := int(inspect.get("version", 0))
	summary["exists"] = true
	summary["status"] = status
	summary["can_load"] = status == "ok"
	summary["version"] = version
	summary["saved_at"] = String(data.get("saved_at", ""))
	summary["gold"] = int(data.get("gold", 0))
	summary["scene"] = String(data.get("scene", GAME_SCENE))

	var staff: Variant = data.get("staff", [])
	if staff is Array:
		summary["staff_count"] = (staff as Array).size()
	var clock: Variant = data.get("clock", {})
	if clock is Dictionary:
		summary["day"] = int((clock as Dictionary).get("day", 0))

	match status:
		"ok":
			summary["status_text"] = ""
		"future":
			summary["status_text"] = "存档来自更高版本 v%d" % version
		"unsupported":
			summary["status_text"] = "存档版本过旧 v%d" % version
		_:
			summary["status_text"] = "存档损坏，无法读取"
	return summary


func get_all_slot_summaries() -> Array:
	var out: Array = []
	for slot in range(1, SLOT_COUNT + 1):
		out.append(get_slot_summary(slot))
	return out


## 最近一份可读存档（主菜单显示用）
func get_latest_summary() -> Dictionary:
	var best: Dictionary = {"exists": false}
	var best_time := ""
	var found := false
	for summary in get_all_slot_summaries():
		if not bool(summary.get("can_load", false)):
			continue
		var saved_at := String(summary.get("saved_at", ""))
		if not found or saved_at > best_time:
			best = summary.duplicate(true)
			best_time = saved_at
			found = true
	if not found:
		return {"exists": false}
	return best


## 兼容旧调用：主菜单/旧存档界面取最近存档摘要
func get_save_summary() -> Dictionary:
	return get_latest_summary()


func get_save_summary_for_slot(slot: int) -> Dictionary:
	return get_slot_summary(slot)


func read_save(slot: int = -1) -> Dictionary:
	if slot <= 0:
		slot = active_slot if is_valid_slot(active_slot) else first_loadable_slot()
	if not has_slot(slot):
		return {}
	var inspect := _inspect_slot(slot)
	if String(inspect.get("status", "")) != "ok":
		return {}
	return (inspect.get("data", {}) as Dictionary).duplicate(true)


func _inspect_slot(slot: int) -> Dictionary:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return {"status": "empty", "version": 0, "data": {}}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("存档读取失败：%s" % error_string(FileAccess.get_open_error()))
		return {"status": "corrupt", "version": 0, "data": {}}
	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("存档损坏（JSON 解析失败）：%s" % path)
		return {"status": "corrupt", "version": 0, "data": {}}
	var data: Dictionary = parsed
	var raw_version: Variant = data.get("version", null)
	if raw_version == null or (typeof(raw_version) != TYPE_INT and typeof(raw_version) != TYPE_FLOAT):
		push_warning("存档损坏（缺少 version）：%s" % path)
		return {"status": "corrupt", "version": 0, "data": data}
	var version := int(raw_version)
	if version > SAVE_VERSION:
		return {"status": "future", "version": version, "data": data}
	if version < MIN_COMPATIBLE_VERSION:
		return {"status": "unsupported", "version": version, "data": data}
	if not _validate_payload(data):
		push_warning("存档损坏（字段不完整）：%s" % path)
		return {"status": "corrupt", "version": version, "data": data}
	return {"status": "ok", "version": version, "data": data}


func _validate_payload(data: Dictionary) -> bool:
	if not data.has("saved_at") or not (data.get("saved_at") is String):
		return false
	if not data.has("gold") or typeof(data.get("gold")) != TYPE_INT and typeof(data.get("gold")) != TYPE_FLOAT:
		return false
	if not data.has("staff") or not (data.get("staff") is Array):
		return false
	if not data.has("clock") or not (data.get("clock") is Dictionary):
		return false
	if data.has("inventory") and not (data.get("inventory") is Dictionary):
		return false
	if data.has("warehouse_slots") and not (data.get("warehouse_slots") is Array):
		return false
	return true


# ---------------- 新游戏 / 读档 / 删除 ----------------

## 初始化一个新游戏到指定槽位。slot<=0 时自动选第一个空槽。
func start_new_game(slot: int = -1) -> bool:
	if slot <= 0:
		slot = first_empty_slot()
		if slot == 0:
			slot = 1
	if not is_valid_slot(slot):
		return false

	active_slot = slot
	_session_active = false
	if _autosave_timer != null:
		_autosave_timer.stop()
	_pending_clock = {}
	StaffRegistry.clear()
	Inventory.reset_to_starting()
	FarmState.reset()
	CoopState.reset()
	FarmOutput.reset()
	_pending_gold = DEFAULT_GOLD
	_last_gold = DEFAULT_GOLD
	delete_slot(slot, false)
	return true


## 读取指定槽位；slot<=0 时读取第一个可读槽位。
func load_game(slot: int = -1) -> bool:
	if slot <= 0:
		slot = first_loadable_slot()
	if not is_valid_slot(slot):
		return false
	var inspect := _inspect_slot(slot)
	if String(inspect.get("status", "")) != "ok":
		return false

	var data: Dictionary = inspect.get("data", {})
	active_slot = slot
	_session_active = false
	if _autosave_timer != null:
		_autosave_timer.stop()

	_pending_clock = data.get("clock", {}) if data.get("clock") is Dictionary else {}
	StaffRegistry.from_dict(data.get("staff", []))
	StaffRegistry.recruit_count = maxi(StaffRegistry.count(), int(data.get("recruit_count", StaffRegistry.count())))
	_restore_inventory(data)
	_restore_buildings(data)
	_apply_demo_supply(data)
	_pending_gold = int(data.get("gold", DEFAULT_GOLD))
	_last_gold = _pending_gold
	game_loaded.emit(slot)
	return true


## 兼容旧调用
func load_save() -> bool:
	return load_game(-1)


func load_slot(slot: int) -> bool:
	return load_game(slot)


func delete_slot(slot: int, notify: bool = true) -> bool:
	if not is_valid_slot(slot):
		return false
	var path := slot_path(slot)
	if FileAccess.file_exists(path):
		var err := DirAccess.remove_absolute(path)
		if err != OK:
			push_warning("删除存档失败：%s" % error_string(err))
			return false
	if notify:
		save_changed.emit()
	return true


## 兼容旧调用：删除当前槽位（没有 active 时删第一个存档）
func delete_save() -> void:
	var slot := active_slot if is_valid_slot(active_slot) else first_loadable_slot()
	if slot > 0:
		delete_slot(slot)


# ---------------- 农场会话 / 自动保存 ----------------

func consume_pending_gold() -> int:
	var gold := _pending_gold
	_pending_gold = -1
	return gold


func note_gold(value: int) -> void:
	_last_gold = maxi(value, 0)
	request_autosave()


func request_autosave(_value: int = 0) -> void:
	if not _session_active:
		return
	if _autosave_timer != null:
		_autosave_timer.start()


func begin_session() -> void:
	if not is_valid_slot(active_slot):
		push_warning("没有选择存档位，自动存档已关闭")
	_session_active = is_valid_slot(active_slot)
	_last_gold = _read_gold_from_scene()
	if _autosave_timer != null:
		_autosave_timer.stop()
	if _session_active:
		save_game()


func end_session() -> void:
	if _session_active:
		save_game()
	_session_active = false
	_pending_gold = -1
	if _autosave_timer != null:
		_autosave_timer.stop()


func save_game() -> bool:
	if not _session_active or not is_valid_slot(active_slot):
		return false
	_ensure_save_dir()
	var payload := {
		"version": SAVE_VERSION,
		"slot": active_slot,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"scene": GAME_SCENE,
		"gold": _read_gold_from_scene(),
		"staff": StaffRegistry.to_dict(),
		"recruit_count": StaffRegistry.recruit_count,
		"clock": _read_clock_from_scene(),
		"inventory": Inventory.to_dict(),
		"warehouse_slots": Inventory.warehouse_slots.duplicate(true),
		"buildings": {
			"farm": FarmState.to_dict(),
			"coop": CoopState.to_dict(),
		},
		# 读档补给只发一次；写进存档后就标记为已发过
		"demo_wheat_supply": true,
	}
	var file := FileAccess.open(slot_path(active_slot), FileAccess.WRITE)
	if file == null:
		var message := "存档写入失败：%s" % error_string(FileAccess.get_open_error())
		push_warning(message)
		save_failed.emit(message)
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	_last_gold = int(payload["gold"])
	save_changed.emit()
	return true


func consume_pending_clock() -> Dictionary:
	var clock := _pending_clock
	_pending_clock = {}
	return clock


# ---------------- 内部 ----------------

func _ensure_save_dir() -> void:
	if not _test_save_path.is_empty():
		return
	if DirAccess.dir_exists_absolute(SAVE_DIR):
		return
	var err := DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	if err != OK:
		push_warning("创建存档目录失败：%s" % error_string(err))


func _migrate_legacy_save() -> void:
	if not _test_save_path.is_empty():
		return
	if not FileAccess.file_exists(LEGACY_SAVE_PATH) or has_slot(1):
		return
	var file := FileAccess.open(LEGACY_SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	file.close()
	_ensure_save_dir()
	var target := FileAccess.open(slot_path(1), FileAccess.WRITE)
	if target == null:
		return
	target.store_string(text)
	target.close()
	var err := DirAccess.remove_absolute(LEGACY_SAVE_PATH)
	if err != OK:
		push_warning("旧存档已复制到 1 号槽，但旧文件删除失败：%s" % error_string(err))


func _read_gold_from_scene() -> int:
	var node := get_tree().get_first_node_in_group("coin_counter")
	if node != null and node.has_method("get_gold"):
		return int(node.call("get_gold"))
	return _last_gold


func _read_clock_from_scene() -> Dictionary:
	var clock := get_tree().get_first_node_in_group("day_night_cycle")
	if clock != null and clock.has_method("get_clock_state"):
		var state: Variant = clock.call("get_clock_state")
		if state is Dictionary:
			return (state as Dictionary).duplicate(true)
	return {"day": 1, "hour": 9.0}


func _on_inventory_changed(_item_id: String, _amount: int) -> void:
	request_autosave()


func _restore_inventory(data: Dictionary) -> void:
	if data.get("inventory") is Dictionary:
		Inventory.from_dict(data.inventory)
	else:
		Inventory.reset_to_starting()
	Inventory.warehouse_slots.clear()
	var saved: Variant = data.get("warehouse_slots", [])
	if saved is Array:
		for entry in saved.slice(0, 40):
			if not (entry is Dictionary):
				Inventory.warehouse_slots.append({})
				continue
			var copy: Dictionary = (entry as Dictionary).duplicate()
			var item_id := String(copy.get("item_id", ""))
			if not item_id.is_empty():
				if Inventory.REMOVED_ITEM_IDS.has(item_id):
					Inventory.warehouse_slots.append({})
					continue
				if Inventory.LEGACY_ITEM_IDS.has(item_id):
					copy["item_id"] = String(Inventory.LEGACY_ITEM_IDS[item_id])
			Inventory.warehouse_slots.append(copy)
	EventBus.inventory_reloaded.emit()


## 建筑存档：农田地块 + 鸡舍状态。旧存档没有该字段时回到默认状态。
func _restore_buildings(data: Dictionary) -> void:
	var buildings: Variant = data.get("buildings", {})
	if not (buildings is Dictionary):
		FarmState.reset()
		CoopState.reset()
		return
	var farm: Variant = buildings.get("farm", {})
	FarmState.from_dict(farm if farm is Dictionary else {})
	var coop: Variant = buildings.get("coop", {})
	CoopState.from_dict(coop if coop is Dictionary else {})


## 老存档没有小麦/食槽是空的时候，读档一次性补 10 小麦。
## 只对没有该标记的旧存档生效；写进存档后不会重复发；测试存档不参与。
func _apply_demo_supply(data: Dictionary) -> void:
	if OS.get_cmdline_user_args().has("--test-save"):
		return
	if bool(data.get("demo_wheat_supply", false)):
		return
	Inventory.add("wheat", DEMO_SUPPLY_WHEAT)


## 测试存档隔离：
##   --test-save                改用独立的测试文件名，不碰玩家正式存档；
##   --test-save-in-workspace   再把它放到工程内 .tmp/ 下，方便无头验收环境读写。
func _apply_test_save_path() -> void:
	# 测试模式下允许不经过主菜单直接 save_game()/load_save()，并把槽位落到独立文件。
	if not OS.get_cmdline_user_args().has("--test-save"):
		return
	active_slot = 1
	_session_active = true
	if OS.get_cmdline_user_args().has("--test-save-in-workspace"):
		DirAccess.make_dir_recursive_absolute("res://.tmp")
		_test_save_path = "res://.tmp/save.test.json"
	else:
		_test_save_path = "user://save.test.json"
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _session_active:
		save_game()