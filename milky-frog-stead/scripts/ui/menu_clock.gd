extends VBoxContainer
## 时间菜单：除了显示天数，还提供手动保存和「保存并返回主菜单」。
##
## 这样玩家在主菜单里点「存档」时，一定是有一份最新进度可读的。

@onready var _save_button: Button = %SaveButton
@onready var _main_menu_button: Button = %MainMenuButton
@onready var _save_hint: Label = %SaveHint


func _ready() -> void:
	_save_button.pressed.connect(_on_save_pressed)
	_main_menu_button.pressed.connect(_on_main_menu_pressed)


func _on_save_pressed() -> void:
	if SaveManager.save_game():
		_save_hint.text = "已保存"
	else:
		_save_hint.text = "保存失败，请查看控制台"


func _on_main_menu_pressed() -> void:
	# end_session 内部会先 save_game()，再停掉自动存档
	SaveManager.end_session()
	get_tree().change_scene_to_file(SaveManager.MENU_SCENE)
