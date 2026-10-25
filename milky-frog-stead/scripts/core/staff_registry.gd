extends Node
## 员工名册（Autoload）。
##
## 招聘菜单往里加人，员工状态菜单从里读人，两边互不认识——
## 谁改了名册，另一边通过 staff_changed 自动刷新。
##
## 用法：
##   StaffRegistry.add_member("青蛙三号", texture, "res://assets/icons/recruit/npc3.png")
##   for member in StaffRegistry.members:
##       print(member.display_name, " / ", member.status)
##
## 注意：还没做存档，退出游戏名册就清空（等 SaveManager 接上再补）。

## 新增了一名员工（参数是那名员工）
signal staff_added(member: StaffMember)
## 名册有变化（新增 / 清空 / 改名），员工状态菜单监听这个
signal staff_changed()

## 当前所有员工，按招聘顺序
var members: Array[StaffMember] = []

var _next_id: int = 1


# ---------------- 对外接口 ----------------

## 招聘一名员工。名字重复由调用方先挡掉（用 has_name 判断）。
## look 决定进场景后长什么样；不传就按立绘文件名推（npc3.png → npc3）。
func add_member(display_name: String, portrait: Texture2D, portrait_path: String = "", look: String = "") -> StaffMember:
	if look.is_empty() and not portrait_path.is_empty():
		look = portrait_path.get_file().get_basename()
	var member := StaffMember.new(_next_id, display_name, portrait, portrait_path, look)
	_next_id += 1
	members.append(member)
	staff_added.emit(member)
	staff_changed.emit()
	return member


## 名字是否已经被占用
func has_name(display_name: String) -> bool:
	for member in members:
		if member.display_name == display_name:
			return true
	return false


func count() -> int:
	return members.size()


## 清空名册（调试用）
func clear() -> void:
	members.clear()
	_next_id = 1
	staff_changed.emit()
