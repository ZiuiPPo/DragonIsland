extends Node
## 主菜单路由器。
##
## 主菜单 / 存档界面 / 设置界面都以子节点的形式挂在 scene_handler 下面，
## 这样它们只负责显示和发信号，真正的场景跳转全部集中在这里。
##
## 场景连接：
##   主菜单「新游戏」 -> 确认覆盖 -> scenes/farm.tscn
##   主菜单「存档」   -> 存档界面 -> 读取 -> scenes/farm.tscn
##   主菜单「游戏设置」-> 设置界面
##   主菜单「退出游戏」-> 退出
##   农场「保存并返回主菜单」-> scenes/main/scene_handler.tscn

const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/ui/main_menu.tscn")
const SAVE_MENU_SCENE: PackedScene = preload("res://scenes/ui/save_menu.tscn")
const SETTINGS_MENU_SCENE: PackedScene = preload("res://scenes/ui/settings_menu.tscn")

var _main_menu: Control = null
var _save_menu: Control = null
var _settings_menu: Control = null


func _ready() -> void:
	print("✅ scene_handler 已经启动")
	_show_main_menu()


# ---------------- 界面切换 ----------------

func _show_main_menu() -> void:
	_main_menu = _show_screen(MAIN_MENU_SCENE) as Control
	if _main_menu == null:
		return
	_main_menu.new_game_pressed.connect(_on_new_game_pressed)
	_main_menu.save_pressed.connect(_on_save_pressed)
	_main_menu.settings_pressed.connect(_on_settings_pressed)
	_main_menu.exit_pressed.connect(_on_exit_pressed)
	print("✅ 主菜单已加载")


func _show_save_menu() -> void:
	_save_menu = _show_screen(SAVE_MENU_SCENE) as Control
	if _save_menu == null:
		return
	_save_menu.back_pressed.connect(_show_main_menu)
	_save_menu.load_requested.connect(_on_load_requested)
	print("✅ 存档界面已加载")


func _show_settings_menu() -> void:
	_settings_menu = _show_screen(SETTINGS_MENU_SCENE) as Control
	if _settings_menu == null:
		return
	_settings_menu.back_pressed.connect(_show_main_menu)
	print("✅ 设置界面已加载")


## 清掉当前菜单，挂上新菜单。菜单场景根节点必须是 Control。
func _show_screen(scene: PackedScene) -> Control:
	for child in get_children():
		if child is Control:
			remove_child(child)
			child.queue_free()

	if scene == null:
		push_error("菜单场景 preload 失败")
		return null
	var screen := scene.instantiate() as Control
	if screen == null:
		push_error("菜单场景根节点必须是 Control：%s" % scene.resource_path)
		return null
	add_child(screen)
	return screen


# ---------------- 主菜单按钮 ----------------

func _on_new_game_pressed() -> void:
	if SaveManager.has_save():
		_confirm_overwrite_save()
	else:
		_start_new_game()


func _start_new_game() -> void:
	print("🟢 新游戏，跳转农场")
	SaveManager.start_new_game()
	_go_to_game()


func _on_save_pressed() -> void:
	_show_save_menu()


func _on_settings_pressed() -> void:
	_show_settings_menu()


func _on_exit_pressed() -> void:
	print("🟢 退出游戏")
	get_tree().quit()


# ---------------- 存档界面回调 ----------------

func _on_load_requested() -> void:
	print("🟢 读取存档，跳转农场")
	_go_to_game()


# ---------------- 内部 ----------------

## 已有存档时，新游戏必须先确认，避免误点覆盖进度。
func _confirm_overwrite_save() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.name = "NewGameConfirm"
	dialog.title = "开始新游戏"
	dialog.dialog_text = "已有存档，开始新游戏会覆盖原来的进度。\n确定要重新开始吗？"
	dialog.ok_button_text = "重新开始"
	dialog.cancel_button_text = "取消"
	dialog.confirmed.connect(_start_new_game)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


func _go_to_game() -> void:
	var err := get_tree().change_scene_to_file(SaveManager.GAME_SCENE)
	if err != OK:
		push_error("进入农场失败：%s" % error_string(err))
		_show_main_menu()
