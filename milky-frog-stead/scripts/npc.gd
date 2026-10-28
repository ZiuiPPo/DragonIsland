class_name Npc
extends CharacterBody2D
## NPC 的「决策层」：决定去哪、什么时候歇着。
##
## 分工：
##   本脚本                            决定"去哪个点、等多久"
##   NpcLocomotion                     把"一个目标坐标"变成"这一帧的速度"
##   CharacterBody2D.move_and_slide()  真正挪动身体
##
## 漫游的本质是 **低频决策 + 高频执行**：
##   决策（挑点、计时）一秒才发生一次；移动每物理帧都在跑。
##   决策写进每帧 → 抽搐；移动写成一次性 → 瞬移。

# ---------------------------------------------------------------- 可调参数
@export_group("漫游")
## 活动范围：以「编辑器里摆的位置」为中心的矩形（半宽, 半高），单位像素。
##
## 不用圆形的原因：圆的半径是固定的，走久了会看出"总在同一个圈里"的规律。
## 矩形 + 小步随机走动，落点分布更散，看起来才像自己在逛。
@export var wander_area: Vector2 = Vector2(320.0, 220.0)

## 每次随机走动的距离范围（像素）。小步 = 在附近晃，偶尔才走远。
## 想让 NPC 更"痒"、更频繁地换位置，就把下限调小
@export var step_range: Vector2 = Vector2(60.0, 160.0)

## 每次挑点时，「直接去范围内任意一点」的概率。
## 其余时候在当前位置附近小步挪动 —— 两者混着才不会
## "要么在原地打转，要么满地图乱跑"
@export_range(0.0, 1.0) var long_trip_chance: float = 0.25

## 静止时长：(基准, 波动幅度)，单位秒。
## 实际值落在 [基准 - 幅度, 基准 + 幅度]，而且偏向短的那一端。
## 想整体待得更久就调大 x；想"偶尔发很久的呆"就把 y 调大
@export var wait_range: Vector2 = Vector2(3.0, 2.0)

## 移动速度的随机乘数区间。每个 NPC 在 _ready 时取一个固定倍数，
## 让一群 NPC 快慢不同 —— 同一个速度跑 5 个，一眼就看得出是机器人
@export var speed_jitter: Vector2 = Vector2(0.85, 1.15)

## 撞上障碍后，停多久再挑下一个点（秒）。
## 调大会显得"撞一下愣一会儿"，调小会在墙角处频繁重挑
@export var block_wait: float = 0.35


@export_group("出生")
## 出生点随机：NPC 会在活动范围内随机一个位置出现。
## 你在编辑器里摆的位置是**范围中心**，不是它出生的地方。
## 想在编辑器里精确摆位调试时，把这个关掉就行
@export var random_spawn: bool = true


# ---------------------------------------------------------------- 常量
## 动画名。**必须和场景里 SpriteFrames 的动画名一字不差**，
## 写错了 Godot 不会报错，只会静默地什么都不播（_check_animations 会兜住）
const ANIM_IDLE_LEFT := &"idle_left"
const ANIM_IDLE_RIGHT := &"idle_right"
const ANIM_MOVE_LEFT := &"move_left"
const ANIM_MOVE_RIGHT := &"move_right"

## 判定"在移动"的速度阈值（像素/秒）。
## 低于它按待机算 —— 不加这个，停下瞬间残余速度会让 walk/idle 逐帧来回切
const MOVE_ANIM_SPEED := 8.0

## 朝向判定：|velocity.x| 超过它才认为"确实在往左/往右走"。
## 取一个很小的正数，是为了让"纯上下移动"(velocity.x 正好为 0) 不改朝向，
## 同时挡住浮点噪声 —— 否则 x 在 0 附近抖时朝向会左右闪
const FACING_EPSILON := 0.5

## 判定"被挡住"：这一帧实际走的路程，不到想走的路程的这个比例。
##
## 不能只看"有没有发生碰撞"：贴着墙**侧向滑行**时每帧都在碰撞，
## 但那种情况 NPC 其实在正常前进，一碰撞就停会在墙边一顿一顿地抽搐。
## 看比例就分得开：正面撞墙 ≈ 0%，沿墙滑行通常还有 60~80%。
const BLOCKED_PROGRESS_RATIO := 0.35


# ---------------------------------------------------------------- 节点
@onready var locomotion: NpcLocomotion = $NpcLocomotion
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D


# ---------------------------------------------------------------- 运行时状态
## 每个 NPC 自己一个随机源：一个 NPC 的随机不会影响别的，
## 以后也能给某个 NPC 设固定 seed 来复现 bug
var _rng := RandomNumberGenerator.new()

## 活动范围的中心 = 编辑器里摆的位置（**不是**随机出生后的位置）
var _home: Vector2 = Vector2.ZERO

## 还要静止多久（秒）。> 0 时不挑新点
var _wait_left: float = 0.0

## 朝向：false = 朝左，true = 朝右
var _facing_right := false


# ---------------------------------------------------------------- 生命周期
func _ready() -> void:
	# 告诉草地系统：这货会踩开草丛（GrassField2D 的 pusher_group，最多取 4 个）
	add_to_group("grass_pusher")

	# 俯视角：不受重力、没有"地面"概念。不设的话 move_and_slide 会按
	# GROUNDED 那套逻辑处理碰撞，撞墙时的滑动方向会不对
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING

	_rng.randomize()

	# 先把"摆的位置"记成范围中心，再随机挪动。
	# 顺序反了的话，中心就成了随机的那个点，NPC 会一天天漂走
	_home = global_position

	# 每个 NPC 速度略有不同
	locomotion.move_speed *= _rng.randf_range(speed_jitter.x, speed_jitter.y)

	locomotion.arrived.connect(_on_arrived)
	locomotion.stuck.connect(_on_stuck)

	_check_animations()

	# 出生点随机：在活动范围内取一个点
	if random_spawn:
		global_position = _home + Vector2(
			_rng.randf_range(-wander_area.x, wander_area.x),
			_rng.randf_range(-wander_area.y, wander_area.y)
		)

	# 开局错开：不让所有 NPC 在同一帧一起起步
	_wait_left = _rng.randf_range(0.0, 2.0)

	# 让初始动画和 _facing_right 立刻一致，避免第一帧闪一下
	_update_anim()


func _physics_process(delta: float) -> void:
	# ── 执行：每帧都做 ──
	# 先存一份「腿想要的速度」。move_and_slide() 会把 velocity 改成
	# **沿墙滑行之后**的结果，撞墙判断必须拿"想要的那份"比才有意义
	var intended := locomotion.tick(delta)
	var start_pos := global_position
	velocity = intended
	move_and_slide()
	_update_anim()

	# ── 撞上障碍：放弃这个目标，停一下再重挑 ──
	if locomotion.has_target() and _is_blocked(intended, start_pos, delta):
		locomotion.stop()
		_wait_left = block_wait
		return

	# ── 决策：只在"手上没活 + 等够了"时才做 ──
	if locomotion.has_target():
		return                      # 正在走，不用管
	if _wait_left > 0.0:
		_wait_left -= delta         # 站着等，等够了再说
		return
	locomotion.move_to(_pick_point())


# ---------------------------------------------------------------- 决策
func _on_arrived() -> void:
	# 分布偏短：多数是短停，偶尔发一会儿呆。
	# randf() * randf() 的乘积落在 [0,1) 且偏向 0 —— 这就是"偶尔"的来源
	var t := _rng.randf() * _rng.randf()
	_wait_left = maxf(0.0, wait_range.x + lerpf(-wait_range.y, wait_range.y, t))


func _on_stuck() -> void:
	# 这个点走不到（挑到了墙里 / 被家具挡死）。
	# 移动层已经把 _has_target 清成 false 了，这里只需要停一下再挑下一个，
	# 否则会变成"撞 1.5 秒 → 立刻重挑 → 又撞 1.5 秒"的循环
	_wait_left = 0.3


## 这一帧是不是被障碍挡住了。
##
## 为什么不直接用 get_slide_collision_count() > 0：
## 贴着墙**侧向滑行**时每帧都有碰撞，但那种情况 NPC 其实在正常前进；
## 只要一有碰撞就停，它会在墙边一顿一顿地抽搐。
##
## 所以判据是「实际走了多少」对「想走多少」的比例：
##   正面撞上   → 实际 ≈ 0          → 判为被挡
##   沿墙滑行   → 实际 ≈ 想要的 70% → 继续走
##   卡进死角   → 实际 ≈ 0          → 判为被挡
func _is_blocked(intended: Vector2, start_pos: Vector2, delta: float) -> bool:
	var speed := intended.length()
	if speed < MOVE_ANIM_SPEED:
		return false                                      # 这一帧本来就没打算走（在刹车/待机）
	var wanted := speed * delta                           # 本来该走这么远
	var actual := global_position.distance_to(start_pos)  # 实际走了这么远
	return actual < wanted * BLOCKED_PROGRESS_RATIO


## 挑下一个目标点。两种策略混用：
##   A. 小步：从当前位置朝随机方向走一小段（多数时候）
##   B. 远行：直接去活动范围内的任意一点（偶尔）
##
## 只用 A 会变成"原地附近打转"，只用 B 会变成"满地图乱窜"，
## 混起来才像闲逛。
func _pick_point() -> Vector2:
	if _rng.randf() < long_trip_chance:
		return _clamp_to_area(Vector2(
			_rng.randf_range(-wander_area.x, wander_area.x),
			_rng.randf_range(-wander_area.y, wander_area.y)
		) + _home)

	var angle := _rng.randf() * TAU
	var step := _rng.randf_range(step_range.x, step_range.y)
	return _clamp_to_area(global_position + Vector2(cos(angle), sin(angle)) * step)


## 把点限制在活动矩形内
func _clamp_to_area(point: Vector2) -> Vector2:
	var offset := point - _home
	return _home + Vector2(
		_fold(offset.x, wander_area.x),
		_fold(offset.y, wander_area.y)
	)


## 超出 ±limit 时按边界**镜像折回**，再夹紧兜底。
##
## 为什么不直接 clamp：直接夹紧会让 NPC 一直在边线上走，
## 看起来像被一堵看不见的墙推着。折回是"撞到边界弹回来"，自然得多。
func _fold(value: float, limit: float) -> float:
	if absf(value) <= limit:
		return value
	var folded := signf(value) * (2.0 * limit - absf(value))
	return clampf(folded, -limit, limit)


# ---------------------------------------------------------------- 表现
func _update_anim() -> void:
	var moving := velocity.length() > MOVE_ANIM_SPEED

	# ① 朝向：以 y 轴为界 —— x 分量为负走左边，为正走右边。
	#    纯上下移动时 x 正好是 0，这时候**不改**朝向，沿用上一次的。
	var speed_x := velocity.x
	if absf(speed_x) > FACING_EPSILON:
		_facing_right = speed_x > 0.0

	# ② 动作 × 朝向，选出动画名
	var want: StringName
	if moving:
		want = ANIM_MOVE_RIGHT if _facing_right else ANIM_MOVE_LEFT
	else:
		want = ANIM_IDLE_RIGHT if _facing_right else ANIM_IDLE_LEFT

	# ③ 只在真的换了动画时才动 frame
	#    不重置的话：move_left 有 7 帧，切到只有 1 帧的 idle_right 会读到越界帧
	if animated_sprite_2d.animation != want:
		animated_sprite_2d.animation = want
		animated_sprite_2d.frame = 0

	# ④ 启动播放。
	#    **光设 animation 不会让帧往前走** —— playing 为 false 时，
	#    设 animation 只负责把第 0 帧贴上去，看起来就是"卡在首帧"。
	#    但也**不能每帧都调 play()**：它内部会把帧重置到 0，
	#    每帧调一次反而永远停在第 0 帧。所以必须"只在没播的时候播一次"。
	if not animated_sprite_2d.is_playing():
		animated_sprite_2d.play()

	# ⑤ 动画速度跟着实际速度走，减少"脚底打滑"。
	#    放在 play() 之后：play() 会把 speed_scale 重置成 1.0
	if moving:
		animated_sprite_2d.speed_scale = clampf(
			velocity.length() / maxf(locomotion.move_speed, 1.0), 0.5, 2.0)
	else:
		# 必须显式归 1.0。
		# speed_scale 是**角色身上的属性**，会从走路状态残留下来 ——
		# 单帧 idle 看不出来（它本来就不动），但多帧 idle 会按错误速度播：
		# 快走之后停下来发呆，呼吸动画会明显偏快 / 偏慢。
		animated_sprite_2d.speed_scale = 1.0


## 动画名如果和场景里对不上，Godot 不会报错 —— 只会静默地什么都不播。
## 这个检查能把"它在滑步/不动"从"猜"变成"日志里一行字"
func _check_animations() -> void:
	var frames := animated_sprite_2d.sprite_frames
	if frames == null:
		push_error("[NPC] AnimatedSprite2D 上没有 SpriteFrames")
		return
	for anim in [ANIM_IDLE_LEFT, ANIM_IDLE_RIGHT, ANIM_MOVE_LEFT, ANIM_MOVE_RIGHT]:
		if not frames.has_animation(anim):
			push_error("[NPC] 场景里没有动画 '%s'，实际有：%s"
				% [anim, frames.get_animation_names()])
