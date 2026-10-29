extends Node

const MAIN_MENU_SCENE:PackedScene = preload("res://scenes/ui/main_menu.tscn")

func _ready() -> void:
    print("✅ scene_handler 已经启动")
    load_main_menu("game_start")

func load_main_menu(origin:String) -> void:
    print("✅ 准备加载主菜单")
    if MAIN_MENU_SCENE == null:
        print("❌ preload加载失败！检查路径")
        return
    var main_menu:Control = MAIN_MENU_SCENE.instantiate()
    print("✅ 实例化 main_menu 成功")
    main_menu.game_begin_pressed.connect(_on_game_begin_pressed)
    main_menu.game_set_pressed.connect(_on_game_set_pressed)
    main_menu.game_exit_pressed.connect(_on_game_exit_pressed)
    add_child(main_menu)
    print("✅ main_menu 添加到场景树")

func _on_game_begin_pressed(origin:String) ->void:
    print("🟢 开始游戏，跳转农场")
    get_tree().change_scene_to_file("res://scenes/farm/game.tscn")

func _on_game_set_pressed(origin:String) ->void:
    print("🟢 打开设置界面")
    get_tree().change_scene_to_file("res://scenes/ui/ui场景.tscn")

func _on_game_exit_pressed(origin:String) ->void:
    print("🟢 退出游戏")
    get_tree().quit()
