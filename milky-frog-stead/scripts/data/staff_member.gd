class_name StaffMember
extends RefCounted
## 一名已招聘的员工（纯数据，不挂节点）。
##
## 招聘菜单创建它，员工状态界面读取/修改它。
## 所有会影响存档的修改都应该走 StaffRegistry 的接口，让 staff_changed 发出去。

## 当前状态
const STATUS_IDLE: String = "空闲"
const STATUS_WORKING: String = "工作中"
const STATUS_RESTING: String = "休息"
## 兼容旧代码：招聘进来默认空闲（旧存档里的「待定」也会归一到空闲）
const STATUS_PENDING: String = STATUS_IDLE

## 可分配的岗位
const JOB_OPTIONS: Array[String] = ["农夫", "厨师", "服务员", "收银员", "清洁工"]

## 名册内的唯一编号（从 1 开始）
var id: int = 0
## 玩家起的名
var display_name: String = ""
## 招聘时的立绘
var portrait: Texture2D = null
## 立绘的资源路径，存档和查重都用它
var portrait_path: String = ""
## 外观编号：对应 assets/sprites/npcs/staff/<look>_idle_move_left/right.png。
## 招聘时取立绘文件名（npc1 / npc2 …），场景里就按它加载对应的序列帧。
var look: String = ""
## 当前状态：空闲 / 工作中 / 休息
var status: String = STATUS_IDLE
## 岗位（例如 厨师 / 服务员 / 农夫）；空字符串表示未分配
var job: String = ""
## 出勤状态（出勤 / 休息 / 请假）；默认出勤
var attendance: String = "出勤"

## 熟练度：1 最低，越高工作越熟练
var proficiency: int = 1
## 每日薪资（金币）
var salary: int = 100
## 当前工作目标（空字符串表示没有）
var current_task: String = ""
## 当前任务剩余工时
var remaining_hours: float = 0.0
## 体力 0-100
var stamina: float = 100.0
## 心情 0-100
var mood: float = 70.0


func _init(p_id: int = 0, p_name: String = "", p_portrait: Texture2D = null, p_portrait_path: String = "", p_look: String = "", p_job: String = "", p_attendance: String = "出勤") -> void:
	id = p_id
	display_name = p_name
	portrait = p_portrait
	portrait_path = p_portrait_path
	look = p_look
	job = p_job
	attendance = p_attendance


func is_working() -> bool:
	return status == STATUS_WORKING


func is_idle() -> bool:
	return status == STATUS_IDLE


func is_resting() -> bool:
	return status == STATUS_RESTING


## 把旧存档里的「待定」等状态归一成三种当前状态
static func normalize_status(value: String) -> String:
	var text := value.strip_edges()
	if text == STATUS_WORKING:
		return STATUS_WORKING
	if text == STATUS_RESTING:
		return STATUS_RESTING
	return STATUS_IDLE
