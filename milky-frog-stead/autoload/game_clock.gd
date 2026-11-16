extends Node
## 游戏内时钟代理（Autoload）。
##
## 主分支里「天数」的唯一真相是农场场景里的 DayNightCycle 节点（它自己会读档、
## 自己推进 24 小时制）。本节点只做一件小事：跟着它走，并在「进入新的一天」时
## 广播一次 day_started，让种地、养鸡、产出统计等系统统一按天结算。
##
## 约定：
##   · 换场景 / 读档后的第一次读取是「静默对齐」，不广播，避免把加载当成过了一天；
##   · 只有同一个 DayNightCycle 实例里天数变大时才广播；
##   · 没有农场场景（主菜单）时保持上次的值不动。

signal day_started(day: int)

var day: int = 1
var hour: float = 9.0

var _clock: Node = null
var _synced: bool = false


func _process(_delta: float) -> void:
	var clock := get_tree().get_first_node_in_group("day_night_cycle")
	if clock == null:
		return
	if clock != _clock:
		_clock = clock
		_synced = false
	# 场景里可能有别的节点也挂了 day_night_cycle 组（例如测试用的标记节点），
	# 只有真正带 hour/day 的时钟才参与推进。
	var hour_value: Variant = clock.get("hour")
	var day_value: Variant = clock.get("day")
	if hour_value == null or day_value == null:
		return
	hour = clampf(float(hour_value), 0.0, 24.0)
	var scene_day := maxi(1, int(day_value))
	if not _synced:
		# 进入农场 / 读档后的第一次读取：静默对齐，不算新的一天
		_synced = true
		day = scene_day
		return
	if scene_day == day:
		return
	var advanced := scene_day > day
	day = scene_day
	if advanced:
		day_started.emit(day)


func is_clock_ready() -> bool:
	return _synced


func phase_name() -> String:
	if hour >= 5.0 and hour < 12.0:
		return "早晨"
	if hour >= 12.0 and hour < 17.0:
		return "午后"
	if hour >= 17.0 and hour < 21.0:
		return "黄昏"
	return "夜晚"


func reset() -> void:
	day = 1
	hour = 9.0
	_clock = null
	_synced = false
