extends Node
## 员工名册（Autoload，员工底层数据源）。
##
## 招聘菜单往里加人，员工状态界面从里读人并调用这里的操作接口。
## 所有会改变员工状态/岗位/任务的操作统一发 staff_changed，UI 和 SaveManager 都监听它。
##
## 存档：StaffRegistry.get_save_data() 输出员工数组，字段包含岗位、状态、熟练度、
##       薪资、当前任务、剩余工时、体力、心情、出勤。读档由 restore_data() 恢复。

## 新增了一名员工（参数是那名员工）
signal staff_added(member: StaffMember)
## 某名员工的字段被修改（参数是那名员工）
signal staff_updated(member: StaffMember)
## 某名员工被解雇（参数是员工 ID）
signal staff_removed(member_id: int)
## 名册整体有变化（新增 / 删除 / 字段修改 / 清空），UI 监听这个
signal staff_changed()

## 当前所有员工，按招聘顺序
var members: Array[StaffMember] = []

var _next_id: int = 1


# ---------------- 查询 ----------------

## 名字是否已经被占用
func has_name(display_name: String) -> bool:
	for member in members:
		if member.display_name == display_name:
			return true
	return false


func count() -> int:
	return members.size()


func get_member(member_id: int) -> StaffMember:
	for member in members:
		if member.id == member_id:
			return member
	return null


## 返回当前所有已分配岗位（去重、排序）
func get_jobs() -> Array[String]:
	var jobs: Array[String] = []
	for member in members:
		if not member.job.is_empty() and not jobs.has(member.job):
			jobs.append(member.job)
	jobs.sort()
	return jobs


## 按当前状态/岗位筛选。state_filter: "" / 工作中 / 空闲 / 休息；job_filter: "" = 全部
func get_filtered_members(state_filter: String = "", job_filter: String = "") -> Array[StaffMember]:
	var out: Array[StaffMember] = []
	for member in members:
		if not job_filter.is_empty() and member.job != job_filter:
			continue
		if not state_filter.is_empty() and member.status != state_filter:
			continue
		out.append(member)
	return out


func count_status(status: String) -> int:
	var total := 0
	for member in members:
		if member.status == status:
			total += 1
	return total


# ---------------- 招聘 / 修改 ----------------

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


## 分配岗位。job 为空 / 「未分配」时会清空岗位；不会把正在工作的员工强行改成空闲。
func set_job(member_id: int, job: String) -> bool:
	var member := get_member(member_id)
	if member == null:
		return false
	var clean := job.strip_edges()
	if clean == "未分配":
		clean = ""
	member.job = clean
	_touch(member)
	return true


## 指派工作：写入当前任务和剩余工时，状态切到工作中。
func assign_task(member_id: int, task: String, hours: float) -> bool:
	var member := get_member(member_id)
	if member == null:
		return false
	var clean := task.strip_edges()
	if clean.is_empty():
		return false
	member.current_task = clean
	member.remaining_hours = maxf(0.0, hours)
	member.status = StaffMember.STATUS_WORKING
	member.attendance = "出勤"
	_touch(member)
	return true


## 强制休息：清空任务，恢复少量体力和心情。
func force_rest(member_id: int) -> bool:
	var member := get_member(member_id)
	if member == null:
		return false
	member.status = StaffMember.STATUS_RESTING
	member.attendance = "休息"
	member.current_task = ""
	member.remaining_hours = 0.0
	member.stamina = minf(100.0, member.stamina + 15.0)
	member.mood = minf(100.0, member.mood + 5.0)
	_touch(member)
	return true


## 解雇。成功返回 true，并从名册移除。
func dismiss_member(member_id: int) -> bool:
	for i in range(members.size() - 1, -1, -1):
		if members[i].id == member_id:
			members.remove_at(i)
			staff_removed.emit(member_id)
			staff_changed.emit()
			return true
	return false


## 兼容命名：解雇
func remove_member(member_id: int) -> bool:
	return dismiss_member(member_id)


## 把员工改成某个状态（供以后工作系统调用）
func set_status(member_id: int, status: String) -> bool:
	var member := get_member(member_id)
	if member == null:
		return false
	member.status = StaffMember.normalize_status(status)
	if member.status == StaffMember.STATUS_RESTING:
		member.attendance = "休息"
		member.current_task = ""
		member.remaining_hours = 0.0
	elif member.status == StaffMember.STATUS_IDLE:
		member.attendance = "出勤"
		member.current_task = ""
		member.remaining_hours = 0.0
	_touch(member)
	return true


func _touch(member: StaffMember) -> void:
	staff_updated.emit(member)
	staff_changed.emit()


# ---------------- 存档 ----------------

## 业务系统统一存档接口：员工数组，只存纯数据
func get_save_data() -> Array:
	return to_dict()


## 业务系统统一读档接口
func restore_data(data: Variant) -> void:
	from_dict(data)


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
			"job": member.job,
			"attendance": member.attendance,
			"proficiency": member.proficiency,
			"salary": member.salary,
			"current_task": member.current_task,
			"remaining_hours": member.remaining_hours,
			"stamina": member.stamina,
			"mood": member.mood,
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

		var member := StaffMember.new(
			id,
			display_name,
			portrait,
			portrait_path,
			look,
			String(entry.get("job", "")),
			String(entry.get("attendance", "出勤"))
		)
		member.status = StaffMember.normalize_status(String(entry.get("status", StaffMember.STATUS_IDLE)))
		member.proficiency = clampi(int(entry.get("proficiency", 1)), 1, 5)
		member.salary = maxi(0, int(entry.get("salary", 100)))
		member.current_task = String(entry.get("current_task", ""))
		member.remaining_hours = maxf(0.0, float(entry.get("remaining_hours", 0.0)))
		member.stamina = clampf(float(entry.get("stamina", 100.0)), 0.0, 100.0)
		member.mood = clampf(float(entry.get("mood", 70.0)), 0.0, 100.0)

		# 旧存档只有 attendance，没有当前状态时做一次温和归一
		if String(entry.get("status", "")).strip_edges() == "待定":
			member.status = StaffMember.STATUS_IDLE
		if member.status == StaffMember.STATUS_IDLE and member.attendance == "休息":
			member.status = StaffMember.STATUS_RESTING
		if member.status == StaffMember.STATUS_RESTING:
			member.attendance = "休息"
			member.current_task = ""
			member.remaining_hours = 0.0
		elif member.status == StaffMember.STATUS_IDLE:
			member.current_task = ""
			member.remaining_hours = 0.0
		else:
			member.attendance = "出勤"

		members.append(member)
		_next_id = maxi(_next_id, id + 1)

	staff_changed.emit()


## 清空名册（调试 / 新游戏）
func clear() -> void:
	members.clear()
	_next_id = 1
	staff_changed.emit()
