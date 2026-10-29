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
## 存档：名册由 SaveManager 调用 to_dict() / from_dict() 存读，退出游戏后仍能恢复。

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


## 序列化成可写 JSON 的数据（不直接存 Texture2D，存立绘路径，读档时再 load）
func to_dict() -> Array:
	var out: Array = []
	for member in members:
		out.append({
			"id": member.id,
			"display_name": member.display_name,
			"portrait_path": member.portrait_path,
			"look": member.look,
			"status": member.status,
		})
	return out


## 从存档恢复名册。空数据 / 坏条目会被跳过，不会抛错。
func from_dict(data: Variant) -> void:
	members.clear()
	_next_id = 1

	var rows: Array = []
	if data is Array:
		rows = data
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = row

		var display_name := String(entry.get("display_name", "")).strip_edges()
		if display_name.is_empty():
			continue

		var id := int(entry.get("id", _next_id))
		if id <= 0:
			id = _next_id

		var portrait_path := String(entry.get("portrait_path", ""))
		var portrait: Texture2D = null
		if not portrait_path.is_empty() and ResourceLoader.exists(portrait_path):
			portrait = load(portrait_path) as Texture2D

		var look := String(entry.get("look", ""))
		if look.is_empty() and not portrait_path.is_empty():
			look = portrait_path.get_file().get_basename()

		var member := StaffMember.new(id, display_name, portrait, portrait_path, look)
		member.status = String(entry.get("status", StaffMember.STATUS_PENDING))
		members.append(member)
		_next_id = maxi(_next_id, id + 1)

	staff_changed.emit()


## 清空名册（调试用）
func clear() -> void:
	members.clear()
	_next_id = 1
	staff_changed.emit()
