class_name StaffMember
extends RefCounted
## 一名已招聘的员工（纯数据，不挂节点）。
## 招聘菜单创建它，员工状态菜单读它。

## 默认工作状态：还没分配岗位
const STATUS_PENDING: String = "待定"

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
## 工作状态，默认"待定"
var status: String = STATUS_PENDING


func _init(p_id: int = 0, p_name: String = "", p_portrait: Texture2D = null, p_portrait_path: String = "", p_look: String = "") -> void:
	id = p_id
	display_name = p_name
	portrait = p_portrait
	portrait_path = p_portrait_path
	look = p_look
