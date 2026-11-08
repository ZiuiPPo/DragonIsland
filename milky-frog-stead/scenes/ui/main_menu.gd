extends Control
## 主菜单：只负责发信号，不直接切场景。
##
## 菜单项：开始新游戏 / 读取存档 / 设置 / 退出。
## 真正的槽位选择、读档和场景跳转由 scenes/main/scene_handler.gd 处理。

signal new_game_pressed()
signal load_pressed()
signal settings_pressed()
signal exit_pressed()

@onready var _save_state: Label = %SaveState


func _ready() -> void:
	_refresh_save_state()


## 显示存档数量和最近一份存档摘要（农场名 + 天数）
func _refresh_save_state() -> void:
	var used := SaveManager.get_used_slot_count()
	if used == 0:
		_save_state.text = "暂无存档 · 共 %d 个存档位" % SaveManager.SLOT_COUNT
		return

	var latest := SaveManager.get_latest_summary()
	if latest.is_empty():
		_save_state.text = "已用 %d / %d 个存档位" % [used, SaveManager.SLOT_COUNT]
		return

	_save_state.text = "已用 %d/%d · 最近：%s 第 %d 天" % [
		used,
		SaveManager.SLOT_COUNT,
		String(latest.get("farm_name", SaveManager.DEFAULT_FARM_NAME)),
		int(latest.get("day", 1)),
	]


func _on_new_game_pressed() -> void:
	new_game_pressed.emit()


func _on_load_pressed() -> void:
	load_pressed.emit()


func _on_settings_pressed() -> void:
	settings_pressed.emit()


func _on_exit_pressed() -> void:
	exit_pressed.emit()
