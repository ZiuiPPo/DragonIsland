extends VBoxContainer
## 时间菜单：除了显示天数，还提供手动保存和「保存并返回主菜单」。
##
## 这样玩家在主菜单里点「存档」时，一定是有一份最新进度可读的。

@onready var _save_button: Button = %SaveButton
@onready var _main_menu_button: Button = %MainMenuButton
@onready var _save_hint: Label = %SaveHint
@onready var _day_label: Label = %Day
@onready var _phase_label: Label = %Phase
@onready var _change_time_button: Button = %ChangeTimeButton
var _clock: Node


func _ready() -> void:
	_change_time_button.pressed.connect(_on_change_time_pressed)
	_refresh_clock()
	_save_button.pressed.connect(_on_save_pressed)
	_main_menu_button.pressed.connect(_on_main_menu_pressed)


func _on_save_pressed() -> void:
	_save_hint.show()
	if SaveManager.save_game():
		_save_hint.text = "已保存"
	else:
		_save_hint.text = "保存失败，请查看控制台"


func _on_main_menu_pressed() -> void:
	# end_session 内部会先 save_game()，再停掉自动存档
	SaveManager.end_session()
	get_tree().change_scene_to_file(SaveManager.MENU_SCENE)


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		_refresh_clock()

func _refresh_clock() -> void:
	if not is_instance_valid(_clock):
		_clock = get_tree().get_first_node_in_group("day_night_cycle")
	_change_time_button.disabled = not is_instance_valid(_clock)
	if is_instance_valid(_clock):
		_day_label.text = "第 %d 天" % _clock.day
		_phase_label.text = _clock.get_phase_name()

func _on_change_time_pressed() -> void:
	if is_instance_valid(_clock):
		_clock.advance_phase()
		_refresh_clock()
