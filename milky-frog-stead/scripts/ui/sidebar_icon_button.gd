class_name SidebarIconButton
extends Button
## 侧边栏的一个图标按钮：点它 = 打开 menu_scene 指定的那个菜单。
##
## 用法（新增一个侧边栏入口的全部步骤）：
##   1. 在 scenes/ui/menus/ 下建一个菜单场景，根节点必须是 Control；
##   2. 在 sidebar.tscn 的 IconColumn 下复制一个按钮，换上图标；
##   3. 把这个菜单场景拖到按钮的 menu_scene 属性上。
## 不需要改 sidebar.gd——它会自动接管 IconColumn 下所有 SidebarIconButton。

## 这个按钮对应的菜单场景。为空时点击只会在控制台报错，不影响其它按钮。
@export var menu_scene: PackedScene


func _ready() -> void:
	# 由 sidebar.gd 统一管理按下状态，这里只保证它是可切换的按钮
	toggle_mode = true
