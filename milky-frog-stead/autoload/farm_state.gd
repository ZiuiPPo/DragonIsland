extends Node
## 农田数据层（Autoload）。
##
## 只负责 8 块地的状态和「按游戏日生长结算」，不负责画界面：
##   0 空地  1 已锄地  2 生长中  3 成熟
##
## 生长规则和主分支的昼夜时钟对齐：跨过新的一天时统一结算，
## 播种日 + 作物 grow_days ≤ 当前天 → 成熟。作物数据全部来自 data/crops/*.tres。

signal changed
signal plot_changed(index: int)

const PLOT_COUNT: int = 8
const CROP_DIR: String = "res://data/crops/"
const DEFAULT_CROP_ID: String = "turnip"

enum State { UNTILLED, TILLED, GROWING, RIPE }

## 每块地：{ state: int, crop_id: String, planted_day: int, planted_hour: float }
var plots: Array[Dictionary] = []
var selected_crop_id: String = DEFAULT_CROP_ID

var _crops: Dictionary = {}
var _crop_order: Array[String] = []
var _last_day: int = -1
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_load_crops()
	reset()


func _process(_delta: float) -> void:
	# 只在「天」变化时结算，不需要每帧遍历
	if GameClock.day == _last_day:
		return
	_last_day = GameClock.day
	_apply_growth()


# ---------------- 作物配置 ----------------

func _load_crops() -> void:
	_crops.clear()
	_crop_order.clear()
	var dir := DirAccess.open(CROP_DIR)
	if dir == null:
		push_error("[FarmState] 打不开作物目录：%s" % CROP_DIR)
		return
	var file_names := dir.get_files()
	file_names.sort()
	for file_name in file_names:
		if file_name.ends_with(".import"):
			continue
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var res: Variant = load(CROP_DIR + String(file_name))
		var crop := res as CropData
		if crop == null:
			push_warning("[FarmState] %s 不是 CropData，已跳过" % file_name)
			continue
		if crop.id.is_empty() or _crops.has(crop.id):
			continue
		_crops[crop.id] = crop
		_crop_order.append(crop.id)


func crop_ids() -> Array[String]:
	return _crop_order.duplicate()


func crops() -> Array:
	var out: Array = []
	for crop_id in _crop_order:
		out.append(_crops[crop_id])
	return out


func crop_by_id(crop_id: String) -> CropData:
	return _crops.get(crop_id, null) as CropData


func selected_crop() -> CropData:
	return crop_by_id(selected_crop_id)


func set_selected_crop(crop_id: String) -> bool:
	if not _crops.has(crop_id):
		return false
	if selected_crop_id == crop_id:
		return true
	selected_crop_id = crop_id
	changed.emit()
	return true


# ---------------- 地块操作 ----------------

func reset() -> void:
	plots.clear()
	for i in range(PLOT_COUNT):
		plots.append(_empty_plot())
	if _crops.has(DEFAULT_CROP_ID):
		selected_crop_id = DEFAULT_CROP_ID
	elif not _crop_order.is_empty():
		selected_crop_id = _crop_order[0]
	else:
		selected_crop_id = DEFAULT_CROP_ID
	_last_day = GameClock.day
	changed.emit()


func till(index: int) -> bool:
	if not _valid(index):
		return false
	if int(plots[index]["state"]) != State.UNTILLED:
		return false
	plots[index]["state"] = State.TILLED
	plot_changed.emit(index)
	changed.emit()
	return true


func plant(index: int, crop_id: String = "") -> bool:
	if not _valid(index):
		return false
	if int(plots[index]["state"]) != State.TILLED:
		return false
	var id := crop_id if not crop_id.is_empty() else selected_crop_id
	var crop := crop_by_id(id)
	if crop == null:
		return false
	if not Inventory.consume(String(crop.seed_item_id), 1):
		return false
	plots[index]["state"] = State.GROWING
	plots[index]["crop_id"] = id
	plots[index]["planted_day"] = GameClock.day
	plots[index]["planted_hour"] = GameClock.hour
	plot_changed.emit(index)
	changed.emit()
	return true


func harvest(index: int) -> Dictionary:
	if not _valid(index):
		return {}
	var plot: Dictionary = plots[index]
	if int(plot["state"]) != State.RIPE:
		return {}
	var crop := crop_by_id(String(plot["crop_id"]))
	if crop == null:
		plot["state"] = State.TILLED
		plot["crop_id"] = ""
		plot["planted_day"] = -1
		plot["planted_hour"] = 0.0
		plot_changed.emit(index)
		changed.emit()
		return {}
	var low := maxi(1, mini(int(crop.yield_min), int(crop.yield_max)))
	var high := maxi(low, maxi(int(crop.yield_min), int(crop.yield_max)))
	var amount := _rng.randi_range(low, high)
	var produced := FarmOutput.produce(String(crop.yield_item_id), amount)
	if produced <= 0:
		return {}
	plot["state"] = State.TILLED
	plot["crop_id"] = ""
	plot["planted_day"] = -1
	plot["planted_hour"] = 0.0
	plot_changed.emit(index)
	changed.emit()
	return {
		"ok": true,
		"item_id": String(crop.yield_item_id),
		"amount": produced,
		"display_name": String(crop.display_name),
	}


func harvest_all() -> Dictionary:
	var totals: Dictionary = {}
	for i in range(plots.size()):
		if int(plots[i]["state"]) != State.RIPE:
			continue
		var result := harvest(i)
		if result.is_empty() or not bool(result.get("ok", false)):
			continue
		var item_id := String(result["item_id"])
		totals[item_id] = int(totals.get(item_id, 0)) + int(result["amount"])
	return totals


# ---------------- 查询 ----------------

func plot_state(index: int) -> int:
	if not _valid(index):
		return -1
	return int(plots[index]["state"])


func plot_crop_id(index: int) -> String:
	if not _valid(index):
		return ""
	return String(plots[index]["crop_id"])


func growth_progress(index: int) -> float:
	if not _valid(index):
		return 0.0
	var plot: Dictionary = plots[index]
	if int(plot["state"]) == State.RIPE:
		return 1.0
	if int(plot["state"]) != State.GROWING:
		return 0.0
	var crop := crop_by_id(String(plot["crop_id"]))
	if crop == null:
		return 0.0
	var elapsed_hours := float(GameClock.day - int(plot["planted_day"])) * 24.0 		+ (GameClock.hour - float(plot["planted_hour"]))
	if elapsed_hours < 0.0:
		elapsed_hours += 24.0
	var needed_hours := float(maxi(1, int(crop.grow_days))) * 24.0
	return clampf(elapsed_hours / needed_hours, 0.0, 1.0)


func ripe_count() -> int:
	var count := 0
	for plot in plots:
		if int(plot["state"]) == State.RIPE:
			count += 1
	return count


func growing_count() -> int:
	var count := 0
	for plot in plots:
		if int(plot["state"]) == State.GROWING:
			count += 1
	return count


func state_label(state: int) -> String:
	match state:
		State.UNTILLED:
			return "空地"
		State.TILLED:
			return "已锄地"
		State.GROWING:
			return "生长中"
		State.RIPE:
			return "已成熟"
		_:
			return "未知"


# ---------------- 存档 ----------------

func to_dict() -> Dictionary:
	var rows: Array = []
	for plot in plots:
		rows.append({
			"state": int(plot["state"]),
			"crop_id": String(plot["crop_id"]),
			"planted_day": int(plot["planted_day"]),
			"planted_hour": float(plot["planted_hour"]),
		})
	return {"plots": rows, "selected_crop_id": selected_crop_id}


func from_dict(data: Dictionary) -> void:
	for i in range(PLOT_COUNT):
		plots[i] = _empty_plot()
	var rows: Variant = data.get("plots", [])
	if rows is Array:
		for i in range(mini((rows as Array).size(), PLOT_COUNT)):
			var row: Variant = (rows as Array)[i]
			if not (row is Dictionary):
				continue
			var state_value := clampi(int(row.get("state", State.UNTILLED)), 0, 3)
			var crop_id := String(row.get("crop_id", ""))
			if (state_value == State.GROWING or state_value == State.RIPE) and not _crops.has(crop_id):
				state_value = State.UNTILLED
				crop_id = ""
			plots[i] = {
				"state": state_value,
				"crop_id": crop_id,
				"planted_day": int(row.get("planted_day", -1)),
				"planted_hour": float(row.get("planted_hour", 0.0)),
			}
	var selected := String(data.get("selected_crop_id", ""))
	if _crops.has(selected):
		selected_crop_id = selected
	_last_day = GameClock.day
	changed.emit()


# ---------------- 内部 ----------------

func _empty_plot() -> Dictionary:
	return {
		"state": State.UNTILLED,
		"crop_id": "",
		"planted_day": -1,
		"planted_hour": 0.0,
	}


func _valid(index: int) -> bool:
	return index >= 0 and index < plots.size()


func _apply_growth() -> void:
	var day := GameClock.day
	var any := false
	for i in range(plots.size()):
		var plot: Dictionary = plots[i]
		if int(plot["state"]) != State.GROWING:
			continue
		var crop := crop_by_id(String(plot["crop_id"]))
		if crop == null:
			plot["state"] = State.TILLED
			plot["crop_id"] = ""
			plot["planted_day"] = -1
			plot["planted_hour"] = 0.0
			plot_changed.emit(i)
			any = true
			continue
		if day - int(plot["planted_day"]) >= maxi(1, int(crop.grow_days)):
			plot["state"] = State.RIPE
			plot_changed.emit(i)
			any = true
	if any:
		changed.emit()
