extends Control
## 金币计数器 HUD：金币图标 + 数字，数字会平滑滚动到目标值。
##
## 结构约定（见 scenes/ui/coin_counter.tscn）：
##   CoinCounter(Control)
##     ├─ Panel            背景底板（纯装饰，可以删）
##     └─ HBoxContainer
##          ├─ Icon        金币图标（可选，脚本不依赖）
##          └─ NumLable    数字，脚本唯一依赖的节点
##
## real_gold 是真实余额，display_gold 会按 count_speed 追上去，
## 所以别人只改余额也能看到「数钱」的过程。没人调用时它只安静显示 start_gold。
##
## 用法：
##   coin_counter.add_gold(15)          # 加钱，数字会跳一下
##   coin_counter.set_gold(1280)        # 直接设余额
##   if coin_counter.spend_gold(30):    # 花钱，余额不足返回 false
##       ...
##   coin_counter.gold_changed.connect(_on_gold_changed)

## 目标余额变了（滚动开始前）
signal gold_changed(value: int)
## 加钱（只有 amount > 0 才会发）
signal gold_gained(amount: int)
## 数字滚到目标值了
signal count_finished(value: int)

## 差距小于这个值就算滚到位了（显示层是浮点，没必要无限逼近）
const SNAP_EPSILON: float = 0.05

## 初始金币：_ready 时直接显示，不播放滚动
@export var start_gold: int = 0
## 数字追上目标值的速度，越大越快；9 大约 0.4 秒追完
@export_range(1.0, 40.0, 0.5) var count_speed: float = 9.0
## 千位分隔符：1234 显示成 1,234
@export var use_thousands_separator: bool = true
## 加钱时数字弹一下
@export var punch_on_gain: bool = true
## 弹到多大
@export_range(1.0, 1.6, 0.01) var punch_scale: float = 1.18

@onready var num_lable: Label = $HBoxContainer/NumLable

## 真实金币数（逻辑值）
var real_gold: int = 0
## 正在显示的金币数（会从旧值滚到 real_gold）
var display_gold: float = 0.0

var _shown_value: int = -1
var _punch_tween: Tween = null


func _ready() -> void:
	real_gold = maxi(start_gold, 0)
	display_gold = float(real_gold)
	_refresh_label()
	set_process(false)


func _process(delta: float) -> void:
	var target := float(real_gold)
	if absf(target - display_gold) <= SNAP_EPSILON:
		display_gold = target
		_refresh_label()
		set_process(false)
		count_finished.emit(real_gold)
		return
	display_gold = lerpf(display_gold, target, 1.0 - exp(-count_speed * delta))
	_refresh_label()


# ---------------- 对外接口 ----------------

## 业务系统统一存档接口：只导出金币数值
func get_save_data() -> Dictionary:
	return {"gold": real_gold}


## 业务系统统一读档接口。data 可以是 {"gold": 123}，也兼容直接传数字。
func restore_data(data: Variant) -> void:
	var value := 0
	if data is Dictionary:
		var dict: Dictionary = data
		value = int(dict.get("gold", 0))
	elif typeof(data) == TYPE_INT or typeof(data) == TYPE_FLOAT:
		value = int(data)
	set_gold(value, false)


## 设置余额。animate = false 时数字直接跳过去，不滚动。
func set_gold(value: int, animate: bool = true) -> void:
	value = maxi(value, 0)
	if value == real_gold:
		if not animate and display_gold != float(value):
			display_gold = float(value)
			set_process(false)
			_refresh_label()
			count_finished.emit(real_gold)
		return

	var delta_gold := value - real_gold
	real_gold = value
	gold_changed.emit(real_gold)
	if delta_gold > 0:
		gold_gained.emit(delta_gold)

	if animate and is_inside_tree():
		if punch_on_gain and delta_gold > 0:
			_punch()
		set_process(true)
		return

	# 不滚动：直接落到目标值
	display_gold = float(real_gold)
	set_process(false)
	_refresh_label()
	count_finished.emit(real_gold)


## 加钱（amount 为负就是扣钱，不会弹跳）
func add_gold(amount: int) -> void:
	if amount == 0:
		return
	set_gold(real_gold + amount)


## 尝试花钱：余额够就扣掉并返回 true，不够返回 false（什么都不改）
func spend_gold(amount: int) -> bool:
	if amount <= 0:
		return true
	if real_gold < amount:
		return false
	set_gold(real_gold - amount)
	return true


## 当前真实余额
func get_gold() -> int:
	return real_gold


## 数字还在滚动吗（滚到位时 display_gold 会被精确写成 real_gold）
func is_counting() -> bool:
	return display_gold != float(real_gold)


# ---------------- 内部 ----------------

func _refresh_label() -> void:
	var shown := roundi(display_gold)
	if shown == _shown_value:
		return
	_shown_value = shown
	num_lable.text = _format_gold(shown)


## 加钱反馈：数字弹一下。pivot 取当前尺寸的一半，保证是从中心放大。
func _punch() -> void:
	num_lable.pivot_offset = num_lable.size * 0.5
	if _punch_tween != null and _punch_tween.is_valid():
		_punch_tween.kill()

	var tween := create_tween()
	tween.tween_property(num_lable, "scale", Vector2.ONE * punch_scale, 0.08) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(num_lable, "scale", Vector2.ONE, 0.24) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_punch_tween = tween


## 1234 -> "1,234"；不想要分隔符就把 use_thousands_separator 关掉
func _format_gold(value: int) -> String:
	if not use_thousands_separator:
		return str(value)

	var digits := str(absi(value))
	var text := ""
	for i in range(digits.length() - 1, -1, -1):
		text = digits[i] + text
		if i > 0 and (digits.length() - i) % 3 == 0:
			text = "," + text
	return ("-" if value < 0 else "") + text
