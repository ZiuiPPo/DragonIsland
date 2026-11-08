class_name SaveData
extends RefCounted
## 一个存档的纯数据结构体。
##
## 只允许放数值、字符串、数组、字典等纯数据：
##   ❌ 不存 Node / Scene / Texture / Resource 实例
##   ✅ 图像等资源只存 res:// 路径
##
## 各业务系统负责把自己的状态导出成这里的字段：
##   Inventory.get_save_data()   -> inventory（container_id -> slots 容器的纯数据）
##   StaffRegistry.get_save_data() -> staff（岗位/状态/任务/体力等）
##   PlotRegistry.get_save_data() -> plots
##   DayNightCycle.get_save_data() -> clock（天数、时刻）
##
## SaveManager 只负责把这些字段打包、写 JSON / 读 JSON 和按顺序分发恢复。

var version: int = 1
var slot: int = 0
var saved_at: String = ""
var scene: String = ""
var farm_name: String = ""
## -1 表示旧存档没带经济字段，由 SaveManager 用默认金币补齐
var gold: int = -1
var staff: Array = []
var inventory: Dictionary = {}
var plots: Array = []
var clock: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"version": version,
		"slot": slot,
		"saved_at": saved_at,
		"scene": scene,
		"farm_name": farm_name,
		"gold": gold,
		"staff": staff.duplicate(true),
		"inventory": inventory.duplicate(true),
		"plots": plots.duplicate(true),
		"clock": clock.duplicate(true),
	}


## 从 JSON 字典还原结构体。缺失 / 类型不对的字段走默认值，
## 这样旧版本存档也能被读进来，由各系统 restore_data() 决定如何兼容。
static func from_dict(data: Dictionary) -> SaveData:
	var out := SaveData.new()
	out.version = int(data.get("version", 1))
	out.slot = int(data.get("slot", 0))
	out.saved_at = String(data.get("saved_at", ""))
	out.scene = String(data.get("scene", ""))
	out.farm_name = String(data.get("farm_name", ""))
	out.gold = int(data.get("gold", -1))

	var staff_value: Variant = data.get("staff", [])
	if staff_value is Array:
		out.staff = (staff_value as Array).duplicate(true)

	var inventory_value: Variant = data.get("inventory", {})
	if inventory_value is Dictionary:
		out.inventory = (inventory_value as Dictionary).duplicate(true)

	var plots_value: Variant = data.get("plots", [])
	if plots_value is Array:
		out.plots = (plots_value as Array).duplicate(true)

	var clock_value: Variant = data.get("clock", {})
	if clock_value is Dictionary:
		out.clock = (clock_value as Dictionary).duplicate(true)
	return out
