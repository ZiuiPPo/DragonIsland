extends Node
## 主菜单路由器。
##
## 主菜单 / 存档界面 / 设置界面都作为子节点挂在 scene_handler 下面，
## 它们只负责显示和发信号；新游戏初始化、读档和场景跳转集中在这里。
##
## 场景连接：
##   主菜单「开始新游戏」 -> 存档界面(新建模式) -> 选槽位 -> scenes/farm.tscn
##   主菜单「读取存档」   -> 存档界面(读取模式) -> 读取/新建/覆盖 -> scenes/farm.tscn
##   主菜单「设置」       -> 设置界面
##   主菜单「退出」       -> 退出
##   农场「保存并返回主菜单」 -> scenes/main/scene_handler.tscn

const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/ui/main_menu.tscn")
const SAVE_MENU_SCENE: PackedScene = preload("res://scenes/ui/save_menu.tscn")
const SETTINGS_MENU_SCENE: PackedScene = preload("res://scenes/ui/settings_menu.tscn")

## 与 scripts/ui/save_menu.gd 的 MODE_LOAD / MODE_NEW_GAME 保持一致
const SAVE_MODE_LOAD: int = 0
const SAVE_MODE_NEW_GAME: int = 1

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
	_main_menu.connect("new_game_pressed", _on_new_game_pressed)
	_main_menu.connect("load_pressed", _on_load_pressed)
	_main_menu.connect("settings_pressed", _on_settings_pressed)
	_main_menu.connect("exit_pressed", _on_exit_pressed)
	print("✅ 主菜单已加载")


func _show_save_menu(mode: int) -> void:
	_save_menu = _show_screen(SAVE_MENU_SCENE) as Control
	if _save_menu == null:
		return
	_save_menu.call("set_mode", mode)
	_save_menu.connect("back_pressed", _show_main_menu)
	_save_menu.connect("load_requested", _on_load_requested)
	_save_menu.connect("new_game_requested", _on_new_game_requested)
	print("✅ 存档界面已加载（模式 %d）" % mode)


func _show_settings_menu() -> void:
	_settings_menu = _show_screen(SETTINGS_MENU_SCENE) as Control
	if _settings_menu == null:
		return
	_settings_menu.connect("back_pressed", _show_main_menu)
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
	_show_save_menu(SAVE_MODE_NEW_GAME)


func _on_load_pressed() -> void:
	_show_save_menu(SAVE_MODE_LOAD)


func _on_settings_pressed() -> void:
	_show_settings_menu()


func _on_exit_pressed() -> void:
	print("🟢 退出游戏")
	get_tree().quit()


# ---------------- 存档界面回调 ----------------

func _on_load_requested(slot: int) -> void:
	if not SaveManager.load_game(slot):
		_save_message("存档 %d 读取失败，文件可能损坏或版本不兼容" % slot)
		return
	print("🟢 读取 %d 号存档，跳转农场" % slot)
	_go_to_game()


func _on_new_game_requested(slot: int) -> void:
	if not SaveManager.start_new_game(slot):
		_save_message("无法在 %d 号槽位开始新游戏" % slot)
		return
	print("🟢 在 %d 号槽位开始新游戏，跳转农场" % slot)
	_go_to_game()


func _save_message(text: String) -> void:
	if _save_menu != null and is_instance_valid(_save_menu):
		_save_menu.call("refresh_saves")
		_save_menu.call("show_message", text)


func _go_to_game() -> void:
	var err := get_tree().change_scene_to_file(SaveManager.GAME_SCENE)
	if err != OK:
		push_error("进入农场失败：%s" % error_string(err))
		_show_main_menu()
