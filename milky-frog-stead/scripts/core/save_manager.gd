extends Node
## 多槽位存档管理器（Autoload），存档底层核心。
##
## 统一接口：
##   save_game()               写当前槽位
##   load_game(slot)           读指定槽位；不传 slot 时读 active_slot
##
## 存档结构：
##   user://saves/slot_1.json   ← SaveData 序列化后的 JSON
##   user://saves/slot_1.png    ← 缩略图（保存时截取）
##   ... 共 SLOT_COUNT 个槽位
##
## 只存「纯数据」，不存场景节点 / Texture / Node 实例：
##   version / slot / saved_at / scene / farm_name
##   gold（经济）、staff（员工名册：岗位、状态、任务、体力等）
##   inventory（库存）、plots（地块状态）、clock（农场天数与时刻）
##
## 每个业务系统实现自己的存读档接口：
##   Inventory.get_save_data() / restore_data()
##   StaffRegistry.get_save_data() / restore_data()
##   PlotRegistry.get_save_data() / restore_data()
##   DayNightCycle.get_save_data() / restore_data()
##
## 加载顺序（防止 UI/依赖报错）：
##   1. 员工名册
##   2. 库存
##   3. 其他业务系统（地块、农场身份、经济、时间）
##   4. UI 刷新：发出 game_loaded 信号，并等场景加载后由 UI 读取恢复后的数据
##
## 旧版本：SAVE_VERSION = 4，MIN_COMPATIBLE_VERSION = 1；
##        v1/v2/v3 存档会标成 old / 可读取，读档后下一次保存自动升级。
##        旧单存档 user://save.json 会在启动时迁移到 1 号槽。
##        v3 及更早的扁平 inventory 会在 Inventory.restore_data() 里迁移为容器格式。

const SAVE_DIR: String = "user://saves"
const SAVE_VERSION: int = 4
const MIN_COMPATIBLE_VERSION: int = 1
const SLOT_COUNT: int = 3

const DEFAULT_GOLD: int = 500
const DEFAULT_FARM_NAME: String = "奶龙农场"
const DEFAULT_DAY: int = 1
const DEFAULT_HOUR: float = 9.0

const GAME_SCENE: String = "res://scenes/farm.tscn"
const MENU_SCENE: String = "res://scenes/main/scene_handler.tscn"
## 旧版单存档位置（v1）：启动时如果 1 号槽为空，会自动迁移
const LEGACY_SAVE_PATH: String = "user://save.json"

const AUTOSAVE_DELAY: float = 1.5
const AUTOSAVE_INTERVAL: float = 30.0
const THUMB_SIZE: Vector2i = Vector2i(320, 180)

signal save_changed()
signal save_failed(message: String)
## 数据层全部恢复完成、UI 可以刷新时发出（加载顺序的最后一步）
signal game_loaded(slot: int)

## 当前正在玩的槽位，0 = 未选择（例如直接从编辑器运行农场）
var active_slot: int = 0
## 当前农场名。存档备注里显示；新游戏恢复默认，读档从文件恢复。
var current_farm_name: String = DEFAULT_FARM_NAME

var _pending_gold: int = -1
var _pending_clock: Dictionary = {}
var _session_active: bool = false
var _last_gold: int = DEFAULT_GOLD

var _autosave_timer: Timer
var _periodic_timer: Timer
var _thumb_cache: Dictionary = {}
var _last_write_error: String = ""
## 读档过程中 UI 不应被中间信号提前刷新
var _is_restoring: bool = false


func _ready() -> void:
	_ensure_save_dir()
	_migrate_legacy_save()
	_setup_timers()

	# 名册 / 库存变化都触发延迟自动存档；主菜单阶段 session=false，不会误写。
	if not StaffRegistry.staff_changed.is_connected(request_autosave):
		StaffRegistry.staff_changed.connect(request_autosave)
	if not Inventory.inventory_changed.is_connected(request_autosave):
		Inventory.inventory_changed.connect(request_autosave)
	if not PlotRegistry.plots_changed.is_connected(request_autosave):
		PlotRegistry.plots_changed.connect(request_autosave)


# ---------------- 槽位与路径 ----------------

func is_valid_slot(slot: int) -> bool:
	return slot >= 1 and slot <= SLOT_COUNT


func slot_file_name(slot: int) -> String:
	return "slot_%d.json" % slot


func slot_path(slot: int) -> String:
	return "%s/%s" % [SAVE_DIR, slot_file_name(slot)]


func thumbnail_path(slot: int) -> String:
	return "%s/slot_%d.png" % [SAVE_DIR, slot]


func has_slot(slot: int) -> bool:
	return is_valid_slot(slot) and FileAccess.file_exists(slot_path(slot))


func has_any_save() -> bool:
	for slot in range(1, SLOT_COUNT + 1):
		if has_slot(slot):
			return true
	return false


## 兼容旧调用：只要任意槽位有文件就算有存档
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


# ---------------- 槽位摘要 ----------------

## 单个槽位摘要。exists=有文件；valid/can_load=内容可读（含旧版本）；
## status: empty / ok / old / corrupt / future / unsupported。
func get_slot_summary(slot: int) -> Dictionary:
	var summary := {
		"slot": slot,
		"exists": false,
		"valid": false,
		"can_load": false,
		"status": "empty",
		"corrupt": false,
		"old_version": false,
		"version": 0,
		"farm_name": "",
		"day": 0,
		"hour": 0.0,
		"gold": 0,
		"staff_count": 0,
		"inventory_count": 0,
		"saved_at": "",
		"has_thumbnail": false,
	}
	if not is_valid_slot(slot) or not FileAccess.file_exists(slot_path(slot)):
		return summary

	summary["exists"] = true
	summary["has_thumbnail"] = FileAccess.file_exists(thumbnail_path(slot))

	var inspect := _inspect_file(slot_path(slot))
	var status := String(inspect.get("status", "corrupt"))
	var version := int(inspect.get("version", 0))
	summary["status"] = status
	summary["version"] = version
	summary["corrupt"] = status == "corrupt"
	summary["old_version"] = status == "old"
	summary["valid"] = status == "ok" or status == "old"
	summary["can_load"] = summary["valid"]

	if inspect.get("data") is Dictionary:
		var data: Dictionary = inspect["data"]
		var clock := _extract_clock(data)
		summary["farm_name"] = _safe_farm_name(data)
		summary["day"] = int(clock["day"])
		summary["hour"] = float(clock["hour"])
		summary["gold"] = int(data.get("gold", DEFAULT_GOLD))
		summary["saved_at"] = String(data.get("saved_at", ""))
		summary["staff_count"] = _array_size(data.get("staff", []))
		summary["inventory_count"] = _inventory_type_count(data.get("inventory", {}))
	return summary


func get_all_slot_summaries() -> Array:
	var out: Array = []
	for slot in range(1, SLOT_COUNT + 1):
		out.append(get_slot_summary(slot))
	return out


## 主菜单用：最近保存的一份可读存档；没有则返回空字典
func get_latest_summary() -> Dictionary:
	var best: Dictionary = {}
	for summary in get_all_slot_summaries():
		if not bool(summary.get("can_load", false)):
			continue
		if best.is_empty() or String(summary.get("saved_at", "")) > String(best.get("saved_at", "")):
			best = summary
	return best


## 兼容旧主菜单调用
func get_save_summary() -> Dictionary:
	return get_latest_summary()


# ---------------- 新游戏 / 读档 ----------------

## 在指定槽位开始新游戏：初始化所有业务系统默认值，清掉该槽位旧文件。
func start_new_game(slot: int) -> bool:
	if not is_valid_slot(slot):
		return false

	_session_active = false
	_stop_timers()
	active_slot = slot
	reset_runtime_systems()
	# 覆盖存档：先删旧数据和旧缩略图，等农场场景起来后重新保存
	delete_slot(slot, false)
	return true


## 把所有业务系统恢复到新游戏默认值。
## 这里只重置内存数据；农场/DayNightCycle 会在场景 _ready 时消费 pending 值。
func reset_runtime_systems() -> void:
	Inventory.clear()                 # 库存为空
	StaffRegistry.clear()             # 员工名册为空
	PlotRegistry.clear()              # 地块状态为空
	current_farm_name = DEFAULT_FARM_NAME
	_pending_gold = DEFAULT_GOLD
	_last_gold = DEFAULT_GOLD
	_pending_clock = {"day": DEFAULT_DAY, "hour": DEFAULT_HOUR}
	_session_active = false


## 统一读档接口。不传 slot 时读当前 active_slot。
## 恢复顺序：员工名册 → 库存 → 其他业务系统（地块/身份/经济/时间）→ UI 刷新信号。
func load_game(slot: int = -1) -> bool:
	if slot <= 0:
		slot = active_slot
		if not is_valid_slot(slot):
			slot = first_loadable_slot()
	if not is_valid_slot(slot):
		return false

	var inspect := _inspect_file(slot_path(slot))
	var status := String(inspect.get("status", "empty"))
	if status != "ok" and status != "old":
		return false

	var raw: Dictionary = inspect.get("data", {})
	var save_data := SaveData.from_dict(raw)
	_session_active = false
	_stop_timers()
	active_slot = slot
	_is_restoring = true

	# 1) 员工名册（底层数据源，员工界面/岗位分配都依赖它）
	StaffRegistry.restore_data(save_data.staff)
	# 2) 库存（底层数据源，仓库和拖拽交互都依赖它）
	Inventory.restore_data(save_data.inventory)
	# 3) 其他业务系统：地块状态
	PlotRegistry.restore_data(save_data.plots)
	# 4) 农场身份 / 经济 / 时间
	current_farm_name = _safe_farm_name_from_string(save_data.farm_name)
	_pending_gold = save_data.gold if save_data.gold >= 0 else DEFAULT_GOLD
	_last_gold = _pending_gold
	_pending_clock = _sanitize_clock(save_data.clock)
	_is_restoring = false

	# 5) UI 刷新：数据层已全部恢复，UI 可以安全重读
	game_loaded.emit(slot)
	return true


## 数据层是否正在恢复。UI 收到 inventory_changed / staff_changed 时可据此跳过刷新，
## 等 game_loaded 一次性刷新，避免读到“只恢复了一半”的数据。
func is_restoring() -> bool:
	return _is_restoring


## 兼容旧调用
func load_slot(slot: int) -> bool:
	return load_game(slot)


## 兼容旧调用：读取第一个可读槽位
func load_save() -> bool:
	return load_game()


func delete_slot(slot: int, notify: bool = true) -> bool:
	if not is_valid_slot(slot):
		return false

	var removed := false
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		push_warning("存档目录打不开：%s" % SAVE_DIR)
		return false

	var json_file := slot_file_name(slot)
	if dir.file_exists(json_file):
		var err := dir.remove(json_file)
		if err == OK:
			removed = true
		else:
			push_warning("删除 %d 号存档失败：%s" % [slot, error_string(err)])

	var thumb_file := "slot_%d.png" % slot
	if dir.file_exists(thumb_file):
		dir.remove(thumb_file)

	_thumb_cache.erase(slot)
	if notify and removed:
		save_changed.emit()
	return removed


# ---------------- 农场运行期 ----------------

func consume_pending_gold() -> int:
	var gold := _pending_gold
	_pending_gold = -1
	return gold


func consume_pending_clock() -> Dictionary:
	var clock := _pending_clock
	_pending_clock = {}
	return clock


func note_gold(value: int) -> void:
	_last_gold = maxi(value, 0)
	request_autosave()


func request_autosave(_value: int = 0) -> void:
	if not _session_active or _autosave_timer == null:
		return
	_autosave_timer.start()


## 农场 _ready 后调用：启动自动存档，并立刻写一份数据；缩略图等画面渲染后补拍。
func begin_session() -> void:
	if not is_valid_slot(active_slot):
		push_warning("没有选择存档位，自动存档已关闭")
		_session_active = false
		return

	_session_active = true
	_last_gold = _read_gold_from_scene()
	_stop_timers()
	_periodic_timer.start()
	save_game(false)
	_capture_thumbnail_later(active_slot)


func end_session() -> void:
	if _session_active:
		save_game(true)
	_session_active = false
	_pending_gold = -1
	_pending_clock = {}
	_stop_timers()


## 写当前槽位。capture_thumbnail=false 时只写数据（用于自动存档/初始保存）。
func save_game(capture_thumbnail: bool = true) -> bool:
	if not _session_active or not is_valid_slot(active_slot):
		return false

	var save_data := _build_save_data()
	if not _write_slot_data(active_slot, save_data.to_dict()):
		var message := "存档写入失败：%s" % _last_write_error
		push_warning(message)
		save_failed.emit(message)
		return false

	_last_gold = save_data.gold
	if capture_thumbnail:
		_capture_thumbnail(active_slot)
	_thumb_cache.erase(active_slot)
	save_changed.emit()
	return true


## 把各业务系统导出的纯数据打包成一个 SaveData。
## 这里只做收集，不出现任何 Node / Texture 实例。
func _build_save_data() -> SaveData:
	var data := SaveData.new()
	data.version = SAVE_VERSION
	data.slot = active_slot
	data.saved_at = Time.get_datetime_string_from_system(false, true)
	data.scene = GAME_SCENE
	data.farm_name = _safe_farm_name_from_string(current_farm_name)
	data.gold = _read_gold_from_scene()
	data.staff = StaffRegistry.get_save_data()
	data.inventory = Inventory.get_save_data()
	data.plots = PlotRegistry.get_save_data()
	data.clock = _read_clock_from_scene()
	return data


# ---------------- 缩略图 ----------------

## 读取槽位缩略图。没有缩略图返回 null，卡片会显示占位提示。
func get_slot_thumbnail(slot: int) -> Texture2D:
	if not has_slot(slot):
		return null
	if _thumb_cache.has(slot):
		return _thumb_cache[slot] as Texture2D

	var path := thumbnail_path(slot)
	if not FileAccess.file_exists(path):
		return null

	var image := Image.new()
	if image.load(path) != OK:
		return null
	var texture := ImageTexture.create_from_image(image)
	_thumb_cache[slot] = texture
	return texture


func _capture_thumbnail_later(slot: int) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if not _session_active or active_slot != slot:
		return
	if _capture_thumbnail(slot):
		save_changed.emit()


func _capture_thumbnail(slot: int) -> bool:
	if DisplayServer.get_name() == "headless" or not is_valid_slot(slot):
		return false
	var viewport := get_viewport()
	if viewport == null:
		return false
	var texture := viewport.get_texture()
	if texture == null:
		return false
	var image := texture.get_image()
	if image == null or image.is_empty():
		return false

	image.resize(THUMB_SIZE.x, THUMB_SIZE.y, Image.INTERPOLATE_BILINEAR)
	_ensure_save_dir()
	var err := image.save_png(thumbnail_path(slot))
	if err != OK:
		push_warning("缩略图保存失败：%s" % error_string(err))
		return false
	_thumb_cache.erase(slot)
	return true


# ---------------- 内部：读写与校验 ----------------

func _inspect_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"status": "empty", "version": 0, "data": {}}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"status": "corrupt", "version": 0, "data": {}}
	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("存档损坏（JSON 解析失败）：%s 第 %d 行：%s" % [
			path, json.get_error_line(), json.get_error_message(),
		])
		return {"status": "corrupt", "version": 0, "data": {}}

	var parsed: Variant = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("存档损坏（根节点不是字典）：%s" % path)
		return {"status": "corrupt", "version": 0, "data": {}}

	var data: Dictionary = parsed
	var raw_version: Variant = data.get("version", null)
	if raw_version == null or not _is_number(raw_version):
		push_warning("存档损坏（缺少 version）：%s" % path)
		return {"status": "corrupt", "version": 0, "data": data}

	var version := int(raw_version)
	if version > SAVE_VERSION:
		return {"status": "future", "version": version, "data": data}
	if version < MIN_COMPATIBLE_VERSION:
		return {"status": "unsupported", "version": version, "data": data}
	if not _validate_payload(data, version):
		push_warning("存档损坏（字段类型或必需字段不完整）：%s" % path)
		return {"status": "corrupt", "version": version, "data": data}

	return {
		"status": "old" if version < SAVE_VERSION else "ok",
		"version": version,
		"data": data,
	}


func _validate_payload(data: Dictionary, version: int) -> bool:
	if not data.has("saved_at") or not (data.get("saved_at") is String):
		return false
	if data.has("staff") and not (data.get("staff") is Array):
		return false
	if data.has("gold") and not _is_number(data.get("gold")):
		return false
	if data.has("clock") and not (data.get("clock") is Dictionary):
		return false
	if data.has("inventory") and not (data.get("inventory") is Dictionary):
		return false
	if data.has("farm_name") and not (data.get("farm_name") is String):
		return false
	if data.has("plots") and not (data.get("plots") is Array):
		return false

	# v2 起基础业务字段必需
	if version >= 2:
		if not (
			data.has("staff")
			and data.has("gold")
			and data.has("clock")
			and data.has("inventory")
			and data.has("farm_name")
		):
			return false
	# v3 起地块状态也必须是数组（旧 v2 存档没有，按空地块兼容）
	if version >= 3:
		if not data.has("plots") or not (data.get("plots") is Array):
			return false
	return true


func _write_slot_data(slot: int, data: Dictionary) -> bool:
	_ensure_save_dir()
	var file := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if file == null:
		_last_write_error = error_string(FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true


func _ensure_save_dir() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		push_warning("user:// 打不开，无法创建存档目录")
		return
	if not dir.dir_exists("saves"):
		var err := dir.make_dir_recursive("saves")
		if err != OK:
			push_warning("创建存档目录失败：%s" % error_string(err))


## 旧版单存档 user://save.json → 1 号槽（保留原始 version，读档时会提示旧版本）
func _migrate_legacy_save() -> void:
	if not FileAccess.file_exists(LEGACY_SAVE_PATH) or has_slot(1):
		return

	var inspect := _inspect_file(LEGACY_SAVE_PATH)
	var status := String(inspect.get("status", ""))
	if status != "ok" and status != "old":
		return

	var source := FileAccess.open(LEGACY_SAVE_PATH, FileAccess.READ)
	if source == null:
		return
	var text := source.get_as_text()
	source.close()

	_ensure_save_dir()
	var target := FileAccess.open(slot_path(1), FileAccess.WRITE)
	if target == null:
		return
	target.store_string(text)
	target.close()

	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove(LEGACY_SAVE_PATH.get_file())
	print("✅ 旧单存档已迁移到 1 号槽")


# ---------------- 内部：数据读取 ----------------

func _read_gold_from_scene() -> int:
	var node := get_tree().get_first_node_in_group("coin_counter")
	if node != null:
		if node.has_method("get_save_data"):
			var state: Variant = node.call("get_save_data")
			if state is Dictionary:
				var state_dict: Dictionary = state
				return int(state_dict.get("gold", _last_gold))
		if node.has_method("get_gold"):
			return int(node.call("get_gold"))
	return _last_gold


func _read_clock_from_scene() -> Dictionary:
	var clock := get_tree().get_first_node_in_group("day_night_cycle")
	if clock != null:
		if clock.has_method("get_save_data"):
			var state: Variant = clock.call("get_save_data")
			if state is Dictionary:
				var state_dict: Dictionary = state
				return _sanitize_clock(state_dict)
		if clock.has_method("get_clock_state"):
			var legacy_state: Variant = clock.call("get_clock_state")
			if legacy_state is Dictionary:
				var legacy_dict: Dictionary = legacy_state
				return _sanitize_clock(legacy_dict)
	return _sanitize_clock(_pending_clock)


func _extract_clock(data: Dictionary) -> Dictionary:
	var merged: Dictionary = {}
	var clock: Variant = data.get("clock", {})
	if clock is Dictionary:
		var clock_dict: Dictionary = clock
		merged = clock_dict
	# 兼容以后把 day/hour 放到顶层的格式
	if _is_number(data.get("day", null)):
		merged["day"] = data.get("day")
	if _is_number(data.get("hour", null)):
		merged["hour"] = data.get("hour")
	return _sanitize_clock(merged)


func _sanitize_clock(raw: Dictionary) -> Dictionary:
	var day := maxi(1, int(raw.get("day", DEFAULT_DAY)))
	var hour := fposmod(float(raw.get("hour", DEFAULT_HOUR)), 24.0)
	return {"day": day, "hour": hour}


func _safe_farm_name(data: Dictionary) -> String:
	return _safe_farm_name_from_string(String(data.get("farm_name", DEFAULT_FARM_NAME)))


func _safe_farm_name_from_string(raw: String) -> String:
	var name := raw.strip_edges()
	if name.is_empty():
		return DEFAULT_FARM_NAME
	return name


func _array_size(value: Variant) -> int:
	if value is Array:
		return (value as Array).size()
	return 0


func _dictionary_size(value: Variant) -> int:
	if value is Dictionary:
		return (value as Dictionary).size()
	return 0


## 库存摘要：新格式是 containers -> slots，统计有物品的种类数
func _inventory_type_count(value: Variant) -> int:
	if not (value is Dictionary):
		return 0
	var inventory: Dictionary = value
	var containers_value: Variant = inventory.get("containers", null)
	if not (containers_value is Dictionary):
		return inventory.size()

	var item_types: Dictionary = {}
	var containers: Dictionary = containers_value
	for container in containers.values():
		if not (container is Dictionary):
			continue
		var container_dict: Dictionary = container
		var slots_value: Variant = container_dict.get("slots", [])
		if not (slots_value is Array):
			continue
		for slot in slots_value:
			if not (slot is Dictionary):
				continue
			var slot_dict: Dictionary = slot
			var item_id := String(slot_dict.get("item_id", ""))
			if not item_id.is_empty() and int(slot_dict.get("amount", 0)) > 0:
				item_types[item_id] = true
	return item_types.size()


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


# ---------------- 内部：计时器 ----------------

func _setup_timers() -> void:
	_autosave_timer = Timer.new()
	_autosave_timer.name = "AutosaveDelay"
	_autosave_timer.one_shot = true
	_autosave_timer.wait_time = AUTOSAVE_DELAY
	_autosave_timer.timeout.connect(_on_autosave)
	add_child(_autosave_timer)

	_periodic_timer = Timer.new()
	_periodic_timer.name = "AutosaveInterval"
	_periodic_timer.wait_time = AUTOSAVE_INTERVAL
	_periodic_timer.timeout.connect(_on_periodic_save)
	add_child(_periodic_timer)


func _stop_timers() -> void:
	if _autosave_timer != null:
		_autosave_timer.stop()
	if _periodic_timer != null:
		_periodic_timer.stop()


func _on_autosave() -> void:
	save_game(false)


func _on_periodic_save() -> void:
	save_game(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _session_active:
		save_game(false)


# ---------------- 对外：农场名 ----------------

func get_farm_name() -> String:
	return current_farm_name


func set_farm_name(name: String) -> void:
	current_farm_name = _safe_farm_name_from_string(name)
	request_autosave()
