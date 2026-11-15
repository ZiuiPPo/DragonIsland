extends Control
## 主菜单：只负责发信号，不直接切场景。
##
## 具体的「新游戏 / 读档 / 设置 / 退出」由 scenes/main/scene_handler.gd 处理，
## 这样菜单本身可以单独打开预览，也不会把跳转路径写散在各个 UI 脚本里。

signal new_game_pressed()
signal save_pressed()
signal settings_pressed()
signal exit_pressed()

@onready var _save_state: Label = %SaveState


func _ready() -> void:
	_refresh_save_state()


## 让玩家在点「读取存档」之前就能看到存档位使用情况
func _refresh_save_state() -> void:
	var used := SaveManager.get_used_slot_count()
	var summary := SaveManager.get_latest_summary()
	if used == 0:
		_save_state.text = "暂无存档 · 共 %d 个存档位" % SaveManager.SLOT_COUNT
		return
	if not bool(summary.get("exists", false)):
		_save_state.text = "已用 %d/%d · 没有可读取的存档" % [used, SaveManager.SLOT_COUNT]
		return

	_save_state.text = "已用 %d/%d · 最近：金币 %d · 员工 %d" % [
		used,
		SaveManager.SLOT_COUNT,
		int(summary.get("gold", 0)),
		int(summary.get("staff_count", 0)),
	]


func _on_new_game_pressed() -> void:
	new_game_pressed.emit()


func _on_save_pressed() -> void:
	save_pressed.emit()


func _on_settings_pressed() -> void:
	settings_pressed.emit()


func _on_exit_pressed() -> void:
	exit_pressed.emit()
