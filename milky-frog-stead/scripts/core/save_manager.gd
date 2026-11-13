extends Node
## 单槽位存档管理器（Autoload）。
##
## 设计约定（见 docs/游戏企划.md 11.9）：
##   - 只存「数据」，不存场景节点：金币、员工名册、存档时间、版本号。
##   - 主菜单的「新游戏」「存档」、农场的自动存档、退出游戏前的保存都走这里。
##   - 存档文件固定为 user://save.json，单槽位；换多槽位时只需要改 SAVE_PATH。
##
## 一次新游戏 / 读档的流程：
##   1. 主菜单调用 start_new_game() 或 load_save()；
##   2. 农场场景 _ready 里调用 consume_pending_gold() 把金币落到 CoinCounter；
##   3. 农场场景调用 begin_session() 启用数据变化时的自动存档；
##   4. 离开农场 / 手动保存 / 关闭窗口时调用 save_game()。

var SAVE_PATH: String = "user://save.drag-care-test.json" if OS.get_cmdline_user_args().has("--test-save") else "user://save.json"
const SAVE_VERSION: int = 1

## 新游戏默认金币，和 scenes/farm.tscn 里 CoinCounter.start_gold 保持一致
const DEFAULT_GOLD: int = 500

## 农场场景与主菜单场景：菜单按钮跳转时统一用这里，避免路径写散
const GAME_SCENE: String = "res://scenes/farm.tscn"
const MENU_SCENE: String = "res://scenes/main/scene_handler.tscn"

## 金币 / 名册变化后延迟多久再写盘，避免连续变化时频繁写文件
const AUTOSAVE_DELAY: float = 1.5

## 存档写入成功（主菜单可以用它刷新「上次存档」提示）
signal save_changed()
## 存档写入失败（比如磁盘只读），参数是给玩家看的错误信息
signal save_failed(message: String)

## 农场场景尚未消费的金币。-1 表示没有待应用的值，用场景里的默认金币。
var _pending_gold: int = -1
## 是否正在一局游戏里。主菜单 / 存档界面时为 false，避免把菜单状态写进存档。
var _session_active: bool = false
## 最近一次已知金币。CoinCounter 被释放后（比如关闭窗口）仍能写进存档。
var _last_gold: int = DEFAULT_GOLD

var _autosave_timer: Timer
var _pending_clock: Dictionary = {}


func _ready() -> void:
	_autosave_timer = Timer.new()
	_autosave_timer.name = "AutosaveDelay"
	_autosave_timer.one_shot = true
	_autosave_timer.wait_time = AUTOSAVE_DELAY
	_autosave_timer.timeout.connect(save_game)
	add_child(_autosave_timer)

	# 招聘 / 清空名册都触发自动存档；主菜单阶段 _session_active 为 false，不会误写。
	if not StaffRegistry.staff_changed.is_connected(request_autosave):
		StaffRegistry.staff_changed.connect(request_autosave)
	EventBus.inventory_changed.connect(_on_inventory_changed)


# ---------------- 主菜单用 ----------------

## 是否有可读取的存档
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## 给主菜单 / 存档界面用的摘要，不返回员工立绘等大对象
func get_save_summary() -> Dictionary:
	var data := read_save()
	if data.is_empty():
		return {"exists": false}

	var staff_count := 0
	var staff: Variant = data.get("staff", [])
	if staff is Array:
		staff_count = (staff as Array).size()

	return {
		"exists": true,
		"gold": int(data.get("gold", DEFAULT_GOLD)),
		"staff_count": staff_count,
		"saved_at": String(data.get("saved_at", "")),
		"scene": String(data.get("scene", GAME_SCENE)),
	}


## 开始新游戏：清空名册、清掉旧存档，等农场场景 _ready 后写一份全新的。
func start_new_game() -> void:
	_pending_clock = {}
	StaffRegistry.clear()
	Inventory.reset_to_starting()
	_pending_gold = DEFAULT_GOLD
	_last_gold = DEFAULT_GOLD
	_session_active = false
	_autosave_timer.stop()
	delete_save()


## 把存档读进内存（员工名册立即恢复，金币等农场场景创建后再应用）。
## 返回 false 表示没有存档 / 存档损坏 / 版本不符。
func load_save() -> bool:
	var data := read_save()
	if data.is_empty():
		return false

	_pending_clock = data.get("clock", {}) if data.get("clock", {}) is Dictionary else {}
	StaffRegistry.from_dict(data.get("staff", []))
	_restore_inventory(data)
	_pending_gold = int(data.get("gold", DEFAULT_GOLD))
	_last_gold = _pending_gold
	_session_active = false
	_autosave_timer.stop()
	return true


## 删除存档。主菜单「存档」界面里的删除按钮走这里。
func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var dir := DirAccess.open("user://")
		if dir != null:
			var err := dir.remove(SAVE_PATH.get_file())
			if err != OK:
				push_warning("删除存档失败：%s" % error_string(err))
		save_changed.emit()


# ---------------- 农场场景用 ----------------

## 农场场景 _ready 时调用，取走主菜单准备好的金币（-1 = 没有，用场景默认值）。
func consume_pending_gold() -> int:
	var gold := _pending_gold
	_pending_gold = -1
	return gold


## 金币变化时由农场场景连接。更新缓存并延迟自动存档。
func note_gold(value: int) -> void:
	_last_gold = maxi(value, 0)
	request_autosave()


## 请求一次延迟自动存档。金币 / 名册频繁变化时只会写最后一次。
func request_autosave(_value: int = 0) -> void:
	if not _session_active:
		return
	if _autosave_timer != null:
		_autosave_timer.start()


## 进入农场后调用：启用数据变化时的自动存档，并立刻落一份初始进度。
func begin_session() -> void:
	_session_active = true
	_last_gold = _read_gold_from_scene()
	if _autosave_timer != null:
		_autosave_timer.stop()
	save_game()


## 离开农场 / 回到主菜单时调用：先保存，再停止自动存档。
func end_session() -> void:
	if _session_active:
		save_game()
	_session_active = false
	_pending_gold = -1
	if _autosave_timer != null:
		_autosave_timer.stop()


## 写存档。主菜单阶段调用返回 false，避免把菜单状态覆盖掉真实进度。
func save_game() -> bool:
	if not _session_active:
		return false

	var payload := {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"scene": GAME_SCENE,
		"gold": _read_gold_from_scene(),
		"staff": StaffRegistry.to_dict(),
		"clock": _read_clock_from_scene(),
		"inventory": Inventory.to_dict(),
		"warehouse_slots": Inventory.warehouse_slots,
	}

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		var message := "存档写入失败：%s" % error_string(FileAccess.get_open_error())
		push_warning(message)
		save_failed.emit(message)
		return false

	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	save_changed.emit()
	return true


# ---------------- 内部 ----------------

## 读取并校验存档。损坏 / 旧版本一律当作没有存档，避免把坏数据灌进名册。
func read_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("存档读取失败：%s" % error_string(FileAccess.get_open_error()))
		return {}
	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("存档损坏，已忽略：%s" % SAVE_PATH)
		return {}

	var data: Dictionary = parsed
	if int(data.get("version", 0)) != SAVE_VERSION:
		push_warning("存档版本不匹配（%s），已忽略" % str(data.get("version", 0)))
		return {}
	return data


func _read_gold_from_scene() -> int:
	var node := get_tree().get_first_node_in_group("coin_counter")
	if node != null and node.has_method("get_gold"):
		return int(node.call("get_gold"))
	return _last_gold


## 直接点窗口右上角关闭时，也把当前进度落盘（此时场景树还没拆，CoinCounter 还在）。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _session_active:
		save_game()


func consume_pending_clock() -> Dictionary:
	var clock := _pending_clock
	_pending_clock = {}
	return clock

func _read_clock_from_scene() -> Dictionary:
	var clock := get_tree().get_first_node_in_group("day_night_cycle")
	if clock != null:
		return clock.get_clock_state()
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
			Inventory.warehouse_slots.append(entry.duplicate() if entry is Dictionary else {})
	EventBus.inventory_reloaded.emit()
