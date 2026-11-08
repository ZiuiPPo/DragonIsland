extends Node
## 地块状态注册表（Autoload）。
##
## 当前种植玩法还没完全接入，但存档底层需要先有稳定的数据入口：
## 每块地是一个纯字典，例如：
##   {"id": 0, "crop_id": "wheat", "stage": 2, "watered": true, "days_grown": 3}
##
## 地块只存数据，不挂节点；以后真正的 Plot 场景在 _ready 里按 id 向这里取状态。
## SaveManager 通过 get_save_data() / restore_data() 存取。

signal plots_changed()

## 地块状态列表，顺序即 id 顺序（也允许字典里带 id）
var plots: Array[Dictionary] = []


func clear() -> void:
	plots.clear()
	plots_changed.emit()


func is_empty() -> bool:
	return plots.is_empty()


func count() -> int:
	return plots.size()


func get_plot(plot_id: int) -> Dictionary:
	for plot in plots:
		if int(plot.get("id", -1)) == plot_id:
			return plot.duplicate(true)
	return {}


## 写入或更新一块地。state 必须包含 id；纯数据，不存节点。
func set_plot(state: Dictionary) -> void:
	var plot_id := int(state.get("id", -1))
	if plot_id < 0:
		return
	for i in range(plots.size()):
		if int(plots[i].get("id", -1)) == plot_id:
			plots[i] = state.duplicate(true)
			plots_changed.emit()
			return
	plots.append(state.duplicate(true))
	plots_changed.emit()


func remove_plot(plot_id: int) -> void:
	for i in range(plots.size() - 1, -1, -1):
		if int(plots[i].get("id", -1)) == plot_id:
			plots.remove_at(i)
	plots_changed.emit()


# ---------------- 存档接口 ----------------

func get_save_data() -> Array:
	return plots.duplicate(true)


## data 来自 JSON，理论上只可能是 Array；坏条目直接跳过。
func restore_data(data: Variant) -> void:
	plots.clear()
	if data is Array:
		var rows: Array = data
		for row in rows:
			if row is Dictionary:
				var plot: Dictionary = row
				plots.append(plot.duplicate(true))
	plots_changed.emit()
