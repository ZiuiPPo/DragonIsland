extends Control

# 自定义信号，放在最上面
signal game_begin_pressed(origin: String)
signal game_set_pressed(origin: String)
signal game_exit_pressed(origin: String)


func _ready() -> void:
	pass

func _process(delta: float) -> void:
	pass


func _on_game_begin_pressed() -> void:
	game_begin_pressed.emit("game_menu")

func _on_game_set_pressed() -> void:
	game_set_pressed.emit("game_menu")

func _on_game_exit_pressed() -> void:
	game_exit_pressed.emit("game_menu")
