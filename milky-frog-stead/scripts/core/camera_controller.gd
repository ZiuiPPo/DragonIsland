class_name CameraController
extends Camera2D
## 玩家操控的摄像机：**右键拖动平移，滚轮缩放**。
##
## 实现上有三条约束，后面改动别破坏：
##   1. **平移要除以 zoom**。鼠标给的是屏幕（画布）像素；放大 2 倍后同样拖 100px，
##      世界坐标里只该走 50px。不除的话，放大之后拖起来会明显"比鼠标快"，
##      缩小之后又"追不上鼠标"。
##   2. **缩放平滑，平移不平滑**。滚轮是一格一格的，直接跳会晕，所以缩放追一个目标值；
##      而拖动必须 1:1 跟手，加平滑就变成拖橡皮筋了。
##   3. **用 _unhandled_input 而不是 _input**。以后加了 UI（背包、对话框），
##      鼠标压在 UI 上时事件会被 UI 先吃掉，不应该还在拖地图。
##
## 用法：把本脚本挂到 Camera2D 上，在 Inspector 里调下面几组参数。
## 以后想让镜头跟着角色走，把 global_position 的赋值换成「角色位置 + 偏移」的平滑插值即可，
## 平移 / 缩放这部分一行都不用改。


@export_group("缩放")
## 视图缩放下限。默认 1.0 = 当前大小，也就是**最小视图大小**。
## Godot 4 里 zoom 越大画面越放大、看到的地图越少，所以下限就是"最近"。
## 想反过来（只允许缩小、看得更多），把这里设成 0.85 左右（正好装下农场宽度）、
## 上限设成 1.0 即可，代码不用动。
@export var zoom_min: float = 1.0
## 视图缩放上限，也就是**最大视图大小**。3.0 = 最多放大到 3 倍。
@export var zoom_max: float = 3.0
## 滚轮一格的缩放倍率：1.15 = 每格放大 15%
@export var zoom_step: float = 1.15
## 缩放平滑速度（越大越跟手）。<= 0 表示不平滑，滚一格跳一格。
@export var zoom_smoothing: float = 12.0


@export_group("平移")
## 拖动灵敏度。1.0 = 画面严格跟手；调小拖得慢，调大拖得快。
@export var drag_sensitivity: float = 1.0
## true  = 画面跟手：按住右键拖，地图像被手抓住一样跟着走（和拖动网页地图一致）。
## false = 镜头跟手：鼠标往右推，镜头就往右移（画面往左走）。
@export var drag_moves_world: bool = true


@export_group("边界")
## 打开后镜头会被夹在 limit_bounds 里，拖不出背景图、看不到空白。
## 地图还没定稿时可以关着。
@export var limits_enabled: bool = false
## 地图范围（世界坐标矩形）。填背景图覆盖的区域即可，比如农场背景是 1344x1280。
@export var limit_bounds: Rect2 = Rect2()


## 当前显示的缩放值和滚轮给的目标值（显示值平滑追目标值）
var _zoom: float = 1.0
var _zoom_target: float = 1.0
## 右键是否按住
var _dragging: bool = false


func _ready() -> void:
	if zoom_max < zoom_min:
		push_warning("[摄像机] zoom_max < zoom_min，已按 zoom_min 处理")
		zoom_max = zoom_min

	# 起始缩放取场景里 Camera2D 的 zoom，并夹进 [min, max]。
	# 场景目前没设 zoom，就是 1.0，即最小视图。
	_zoom = clampf(zoom.x, zoom_min, zoom_max)
	_zoom_target = _zoom
	zoom = Vector2(_zoom, _zoom)
	_clamp_to_bounds()


## 鼠标：右键拖动、滚轮缩放
func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button:
		if button.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = button.pressed
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_target = clampf(_zoom_target * zoom_step, zoom_min, zoom_max)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_target = clampf(_zoom_target / zoom_step, zoom_min, zoom_max)
		return

	var motion := event as InputEventMouseMotion
	if motion == null or not _dragging:
		return

	# 屏幕像素 -> 世界像素：除以当前 zoom。用显示值而不是目标值，
	# 这样缩放动画还没结束时拖动的速度也是对的。
	var world_delta := motion.relative / _zoom * drag_sensitivity
	if drag_moves_world:
		global_position -= world_delta
	else:
		global_position += world_delta
	_clamp_to_bounds()


## 窗口失焦时收不到右键松开事件，这里兜底，免得切回来还在拖
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_dragging = false


## 缩放平滑：指数插值，和帧率无关（1 - exp(-k * dt)）。
## 不用 lerp(a, b, k * dt)：那样在 185Hz 下每帧只走 5.4%，比 60Hz 的 16.7% 慢得多，
## 高刷屏上缩放手感会明显拖后。
func _process(delta: float) -> void:
	if is_equal_approx(_zoom, _zoom_target):
		return

	if zoom_smoothing <= 0.0:
		_zoom = _zoom_target
	else:
		_zoom = lerpf(_zoom, _zoom_target, 1.0 - exp(-zoom_smoothing * delta))
		# 差值小到看不出来就吸附，省得每帧都在算一个几乎相等的浮点
		if absf(_zoom - _zoom_target) < 0.0005:
			_zoom = _zoom_target

	zoom = Vector2(_zoom, _zoom)
	# 缩小（zoom 变小）会让可视范围变大，原来贴边的镜头可能已经越界，重新夹一次
	_clamp_to_bounds()


## 把镜头中心夹进 limit_bounds，并保证**整个可视矩形**都在范围内。
## 只夹中心是不够的：可视范围有一半在镜头左边/上边，光夹中心照样会露出空白。
func _clamp_to_bounds() -> void:
	if not limits_enabled or limit_bounds.size == Vector2.ZERO:
		return

	var bounds := limit_bounds.abs()
	# 当前视野的一半（世界像素）。用显示值：缩放动画期间也是按看得见的范围夹
	var half := get_viewport_rect().size * 0.5 / _zoom
	var pos := global_position

	# 地图比视野还小的时候没有可移动空间，直接居中，不然 clamp 会算出反向区间
	if bounds.size.x <= half.x * 2.0:
		pos.x = bounds.get_center().x
	else:
		pos.x = clampf(pos.x, bounds.position.x + half.x, bounds.end.x - half.x)
	if bounds.size.y <= half.y * 2.0:
		pos.y = bounds.get_center().y
	else:
		pos.y = clampf(pos.y, bounds.position.y + half.y, bounds.end.y - half.y)

	global_position = pos
