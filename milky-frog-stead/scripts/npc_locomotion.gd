class_name NpcLocomotion
extends NavigationAgent2D
## NPC 的「腿」：只回答「这一帧该用什么速度走」，不回答「该去哪」，也不负责挪动身体。
##
## ── 为什么单独一层 ──────────────────────────────────────────────
## 决策（去哪个点、什么时候发呆）在 scripts/npc.gd 里；这里只把「一个目标坐标」变成速度。
## 于是以后两件事互不干扰：
##   要加「听指令走」——改 npc.gd 的状态机，这个文件一行都不用动；
##   要换寻路方式（导航网格 / AStar2D / 直线）——改这个文件，npc.gd 一行都不用动。
## 两层之间只有四个词：move_to(坐标) / stop() / 信号 arrived / 信号 stuck。
##
## ── 为什么挂在 NavigationAgent2D 上 ─────────────────────────────
## 这样「自动巡逻」和「听指令走」走的是**同一条代码路径**：都是 move_to(坐标)。
## 农场现在还没烘导航网格，use_navigation = false，就是直线走（撞到东西会顺着滑）；
## 等场景里加了 NavigationRegion2D 并烘好网格，把 use_navigation 打勾，
## 同一份巡逻代码立刻变成绕障碍走最短路径，npc.gd 不需要任何改动。
##
## ── 谁调用它 ────────────────────────────────────────────────────
## 父节点（NPC 本体）在每个物理帧调用 tick(delta)，拿到速度后自己 move_and_slide()。
## 也就是说：**位移始终由 CharacterBody2D 负责**，这里只出速度，方便碰撞/推挤交给物理引擎。

## 到达当前目标（和目标的距离 ≤ arrive_radius）
signal arrived
## 想走却走不动（被墙、家具挡住超过 stuck_time 秒）
signal stuck

@export_group("速度")
## 移动速度（像素/秒）
@export var move_speed: float = 90.0
## 起步加速度（像素/秒²）。越大越「跟手」，越小越像有惯性
@export var acceleration: float = 700.0
## 刹车减速度（像素/秒²）
@export var deceleration: float = 1100.0

@export_group("到达判定")
## 距目标多近算到达（像素）。**必须大于刹车距离 move_speed² / (2 × deceleration)**，
## 否则 NPC 会在目标点附近来回蹭、永远判不到达。90² / (2×1100) ≈ 3.7px，取 10 很安全
@export var arrive_radius: float = 10.0

@export_group("寻路")
## true = 沿导航网格走最短路径（要求场景里有烘好的 NavigationRegion2D）；
## false = 直线走，被挡住就顺着障碍滑。
## 农场现在的场景还没烘导航网格，所以默认关；以后烘好了打勾即可，别的都不用改
@export var use_navigation: bool = false

@export_group("卡住检测")
## 想走却几乎没挪动，连续这么多秒就判为卡住，发 stuck 信号（让决策层换目标）
@export var stuck_time: float = 1.5
## 判定「几乎没挪动」的门槛：上一物理帧的实际位移 < move_speed × 这个比例 × delta
@export var stuck_speed_ratio: float = 0.2

## 当前目标（世界坐标）。_has_target 为 false 时这个值没有意义
var _target := Vector2.ZERO
var _has_target := false
## 卡住计时
var _stuck_accum := 0.0
## 上一物理帧开始时身体的位置，用来算实际走了多远
var _last_position := Vector2.ZERO
## 父节点（NPC 本体）。挂错位置时是 null，_ready 里会报错
var _body: CharacterBody2D = null


func _ready() -> void:
	_body = get_parent() as CharacterBody2D
	if _body == null:
		push_error("[NPC移动层] 本节点必须是 CharacterBody2D 的子节点，现在挂在 %s 上"
			% get_parent().name)
		return

	# 和本脚本的 arrive_radius 保持同一套语义：agent 自己那两个阈值也按它设
	path_desired_distance = maxf(arrive_radius * 0.8, 1.0)
	target_desired_distance = arrive_radius
	# 默认关。要让 NPC 之间互相绕开时再打开 —— 官方文档明确说有性能开销，只在需要的 agent 上开
	avoidance_enabled = false
	_last_position = _body.global_position


## 让 NPC 去某个世界坐标。
##
## **重复调用同一个目标不会打断当前路径**：这条很重要 —— 决策层是每物理帧调一次这个函数的，
## 不判断的话导航路径会每秒重算 60 次，NPC 一多就掉帧。
func move_to(world_position: Vector2) -> void:
	if _has_target and _target.is_equal_approx(world_position):
		return
	_target = world_position
	_has_target = true
	_stuck_accum = 0.0
	# 直接设就好：导航地图还没同步完时它返回的是空路径，_desired_direction() 会退化成直线走，
	# 下一帧路径到位就自动接上，不需要特意等一帧
	target_position = world_position


## 放弃当前目标，原地刹车
func stop() -> void:
	_has_target = false
	_stuck_accum = 0.0


## 现在有没有目标要走去
func has_target() -> bool:
	return _has_target


## 离目标还剩多远（决策层想按距离做判断、或者要画调试线时用得上）
func distance_to_goal() -> float:
	if _body == null:
		return 0.0
	return _body.global_position.distance_to(_target)


## 本帧应有的移动速度。NPC 拿到之后自己 move_and_slide()。
## 位移不在这里做，是为了让「身体怎么和场景碰撞」始终归 CharacterBody2D 管
func tick(delta: float) -> Vector2:
	if _body == null:
		return Vector2.ZERO

	var body_velocity := _body.velocity
	# 实际位移要用「上一帧 move_and_slide 走出来的结果」，所以这里先量、再记下当前位置
	var moved := _body.global_position.distance_to(_last_position)
	_last_position = _body.global_position

	# 没有目标：刹车停住
	if not _has_target:
		return body_velocity.move_toward(Vector2.ZERO, deceleration * delta)

	# 到了：清掉目标、发信号，然后刹车（不是瞬间归零，免得看起来像急刹）
	if _body.global_position.distance_to(_target) <= arrive_radius:
		_has_target = false
		arrived.emit()
		return body_velocity.move_toward(Vector2.ZERO, deceleration * delta)

	_check_stuck(moved, delta)
	return body_velocity.move_toward(_desired_direction() * move_speed, acceleration * delta)


## 本帧该往哪个方向走（单位向量）
func _desired_direction() -> Vector2:
	var straight := (_target - _body.global_position).normalized()
	if not use_navigation:
		return straight

	# 官方要求：设过 target_position 之后，每物理帧都得调一次这个函数，导航的内部路径逻辑靠它推进
	var next_point := get_next_path_position()
	var to_next := next_point - _body.global_position

	# 下面两种情况都退化成直线走，不然 NPC 会站着不动：
	#   1. 场景里没有烘好的导航网格 / 目标落在网格外 —— is_navigation_finished() 会一直为真
	#   2. 拿不到路径时，agent 会把「父节点自己的位置」当下一段返回 —— 方向向量是 0
	if is_navigation_finished() or to_next.length() < 1.0:
		return straight
	return to_next.normalized()


## 卡住判定：想走但实际几乎没挪动，累计够久就报 stuck。
## 没有这个，NPC 被家具卡住或路点落在墙里时会一直顶着，看起来像死机
func _check_stuck(moved: float, delta: float) -> void:
	if moved < move_speed * stuck_speed_ratio * delta:
		_stuck_accum += delta
	else:
		_stuck_accum = 0.0

	if _stuck_accum >= stuck_time:
		_stuck_accum = 0.0
		_has_target = false
		stuck.emit()
