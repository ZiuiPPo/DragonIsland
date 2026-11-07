extends Control
## 游戏设置：全屏开关 + 主音量。
##
## 设置写在 user://settings.cfg，和存档分开，不参与存档版本。
## 场景切换仍然交给 scene_handler：这里只发 back_pressed。

signal back_pressed()

const SETTINGS_PATH: String = "user://settings.cfg"
const DEFAULT_VOLUME: float = 0.8

@onready var _fullscreen: CheckButton = %Fullscreen
@onready var _volume: HSlider = %Volume
@onready var _volume_value: Label = %VolumeValue
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_load_settings()
	_fullscreen.toggled.connect(_on_fullscreen_toggled)
	_volume.value_changed.connect(_on_volume_changed)
	_back_button.pressed.connect(_on_back_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


# ---------------- 按钮 ----------------

func _on_back_pressed() -> void:
	back_pressed.emit()


func _on_fullscreen_toggled(enabled: bool) -> void:
	_apply_fullscreen(enabled)
	_save_settings()


func _on_volume_changed(value: float) -> void:
	_apply_volume(value)
	_save_settings()


# ---------------- 应用设置 ----------------

func _apply_fullscreen(enabled: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)


func _apply_volume(value: float) -> void:
	_volume_value.text = "%d%%" % roundi(value * 100.0)
	var master := AudioServer.get_bus_index("Master")
	if master < 0:
		return
	AudioServer.set_bus_mute(master, value <= 0.001)
	AudioServer.set_bus_volume_db(master, linear_to_db(maxf(value, 0.001)))


# ---------------- 读写配置 ----------------

func _load_settings() -> void:
	var fullscreen := false
	var volume := DEFAULT_VOLUME

	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		fullscreen = bool(config.get_value("display", "fullscreen", false))
		volume = clampf(float(config.get_value("audio", "volume", DEFAULT_VOLUME)), 0.0, 1.0)

	# 初始化时用 no_signal，避免把「读配置」误当成玩家操作又存一遍
	_fullscreen.set_pressed_no_signal(fullscreen)
	_volume.set_value_no_signal(volume)
	_apply_fullscreen(fullscreen)
	_apply_volume(volume)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("display", "fullscreen", _fullscreen.button_pressed)
	config.set_value("audio", "volume", _volume.value)
	var err := config.save(SETTINGS_PATH)
	if err != OK:
		push_warning("设置保存失败：%s" % error_string(err))
