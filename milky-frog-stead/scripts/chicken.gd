class_name Chicken
extends CharacterBody2D
## 小鸡：Npc 那套「低频决策 + 高频执行」的骨架上，长出了两件新事。
##
## 分工和 Npc 完全一样：
##   本脚本                            决定"去哪个点、干什么、等多久"
##   NpcLocomotion                     把"一个目标坐标"变成"这一帧的速度"
##   CharacterBody2D.move_and_slide()  真正挪动身体
##
## 和 Npc 的三处不同：
##   1. 没有命名系统 —— 员工才有名字标签，小鸡是农场的背景生物，谁叫什么无所谓
##   2. 多了一条 hunger 时间轴 —— 饿了自己走去食盆吃（喂食）
##   3. 多了一个显式状态机 —— Npc 只有「在走 / 在等」两个隐含状态，
##      小鸡有蹲下、进食这些「站着但在做别的事」的状态，摊开来写更清楚
##
## ── 状态机 ────────────────────────────────────────────────────
##
##   IDLE ─等待结束─┬─饿了且有食盆──→ TO_FOOD ──到达──→ EATING ──吃饱──┐
##                  ├─掷骰中了蹲下──→ CROUCH ──起身──→ IDLE（顺手掷一次蛋）│
##                  └─其余──────────→ WANDER ──到达──→ IDLE ←───────────┘
##
##   WANDER / TO_FOOD 期间**不在本脚本里推进位置**：走路由 NpcLocomotion 每帧出速度，
##   到了由它的 arrived 信号把状态翻回去；撞墙 / 卡住也由它的 stuck 信号兜底。
##   本脚本只管"下一件事干什么"，不碰位移 —— 这样换了寻路方式也不用动这里。
##
## ── 素材还没做的部分：全留成了口子，不需要改本脚本 ──────────────
##   · 食盆：随便什么 Node2D（或带贴图的 Sprite2D），加进 food_group 组就行。
##     想让食盆"空了就不来吃"，给它加一个 has_food() -> bool 方法即可（见 _find_food_spot）。
##   · 蛋：蹲下起身时掷骰，中了发 egg_laid 信号（带落点坐标）。
##     蛋的素材做好以后，要么接这个信号生成，要么直接在 _lay_egg() 里 instantiate，
##     别的地方一行都不用改。
##
## ── 朝向约定 ──────────────────────────────────────────────────
##   美术表里小鸡画在 64×64 格子的中间偏上，脚底在格子 y≈45 处，
##   场景里把 AnimatedSprite2D 的 offset 设成 (0, -13)，脚底就正好落在节点原点上。
##   所以**节点原点的位置 = 小鸡站着的那块地**，碰撞体也挂在原点附近。

# ---------------------------------------------------------------- 可调参数
@export_group("漫游")
## 活动范围：以「编辑器里摆的位置」为中心的矩形（半宽, 半高），单位像素。
## 小鸡是胆子小的动物，范围比员工小一半左右，看起来才会"在窝附近刨食"
@export var wander_area: Vector2 = Vector2(160.0, 120.0)

## 每次随机走动的距离范围（像素）。小鸡步子短，单次移动比员工近得多
@export var step_range: Vector2 = Vector2(24.0, 70.0)

## 每次挑点时，「直接去范围内任意一点」的概率（其余是在当前位置小步挪）
@export_range(0.0, 1.0) var long_trip_chance: float = 0.3

## 静止时长：(基准, 波动幅度)，单位秒。实际值落在 [基准-幅度, 基准+幅度] 且偏向短的一端
@export var wait_range: Vector2 = Vector2(2.2, 1.8)

## 移动速度的随机乘数区间。每只小鸡在 _ready 时取一个固定倍数，一群里快慢不同
@export var speed_jitter: Vector2 = Vector2(0.85, 1.15)

## 撞上障碍后停多久再挑下一个点（秒）
@export var block_wait: float = 0.3

@export_group("蹲下")
## 每次歇脚时蹲下来的概率。0 = 永远不蹲，1 = 一歇就蹲。
## 蹲下本身也是漫游的一部分：走一段 → 站一会儿 → 有时候就蹲着了
@export_range(0.0, 1.0) var crouch_chance: float = 0.35

## 蹲多久：(基准, 波动幅度)，单位秒。蹲着比站着久，才有"窝着不动"的感觉
@export var crouch_range: Vector2 = Vector2(5.0, 4.0)

@export_group("饥饿与进食")
## 饥饿值上限（0 ~ MAX_HUNGER）。涨到 hunger_seek_at 就主动去找吃的
@export var hunger_rate: float = 1.0

## 饿到这个值就开始找食盆。默认 65 / 每秒 1.0 ≈ 一分多钟吃一次
@export var hunger_seek_at: float = 65.0

## 一次吃多久（秒）。**上限**，不是保证 —— 吃饱了（hunger 掉到 0）会提前结束
@export var eat_duration: float = 5.0

## 进食时每秒把饥饿值降多少。默认 14 → 从 65 吃回 0 大约 4.6 秒
@export var eat_recovery: float = 14.0

## 食物点所在的组。往场景里放一个 Node2D 并加进这个组，小鸡就会自己找过去。
## 场上一个都没有时，饿了也只是继续溜达（不会报错、不会卡住）
@export var food_group: StringName = &"chicken_food"

## 找食盆的最大距离（像素）。太远的食盆当没看见，免得小鸡横穿整个农场
@export var food_search_radius: float = 700.0

## 到食盆旁边时的落点随机半径（像素）。几只鸡一起去吃时不会叠成一只
@export var food_queue_spread: float = 18.0

@export_group("产蛋")
## 每次蹲下，起身时下蛋的概率。**故意设得很小** —— 蛋是稀罕东西
@export_range(0.0, 1.0) var egg_chance: float = 0.05

## 打开后会把「开始吃 / 下蛋」打进输出，方便调概率
@export var debug_log: bool = false

@export_group("出生")
## 出生点随机：在活动范围内随机一个位置出现（编辑器里摆的位置是范围中心）
@export var random_spawn: bool = true


# ---------------------------------------------------------------- 常量
## 动画名。**必须和 chicken.tscn 里 SpriteFrames 的动画名一字不差**，
## 动画名必须与 SpriteFrames 一致；_check_animations 提前检查缺失配置。
const ANIM_IDLE := "idle"
const ANIM_MOVE := "move"
const ANIM_EAT := "eat"
const ANIM_CROUCH := "crouch"

## 饥饿值上限
const MAX_HUNGER := 100.0

## 判定"在移动"的速度阈值（像素/秒）。低于它按待机算
const MOVE_ANIM_SPEED := 6.0

## 朝向判定：|velocity.x| 超过它才认为"确实在往左/往右走"。
## 纯上下移动时 x 正好是 0，这时候不改朝向，挡住浮点噪声
const FACING_EPSILON := 0.5

## 判定"被挡住"：这一帧实际走的路程，不到想走的路程的这个比例。
## 正面撞墙 ≈ 0%；沿墙滑行通常还有 60~80%，不算被挡
const BLOCKED_PROGRESS_RATIO := 0.35

## 去食盆的路上被挡住后，冷却多久再考虑吃（秒）。
## 没有它的话，小鸡会"卡住 → 立刻又想饿 → 又往同一个点撞"地死循环
const FOOD_COOLDOWN_AFTER_BLOCK := 4.0


## 下了一个蛋。蛋的素材还没做，所以现在**只发信号**：
## 以后接这个信号生成蛋就行（或者直接在 _lay_egg() 里 instantiate）
signal egg_laid(egg_position: Vector2)


# ---------------------------------------------------------------- 状态
## 见文件开头那张图。IDLE / CROUCH / EATING 由本脚本计时，
## WANDER / TO_FOOD 由 NpcLocomotion 推进、由 arrived 信号结束
enum State { IDLE, WANDER, CROUCH, TO_FOOD, EATING }


# ---------------------------------------------------------------- 节点
@onready var locomotion: NpcLocomotion = $NpcLocomotion
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D


# ---------------------------------------------------------------- 运行时状态
## 每只小鸡自己一个随机源：一只的随机不影响别的，以后也能设固定 seed 复现问题
var _rng := RandomNumberGenerator.new()

## 活动范围的中心 = _ready() 时的位置，随后才应用 random_spawn 偏移。
var _home: Vector2 = Vector2.ZERO

## 当前状态
var _state: State = State.IDLE

## IDLE / CROUCH 还剩多久（秒）
var _wait_left: float = 0.0

## EATING 还剩多久（秒）
var _eat_left: float = 0.0

## 朝向：false = 朝左，true = 朝右
var _facing_right := false

## 饥饿值 0 ~ MAX_HUNGER。**只涨不掉的后果放大了会很烦**，
## 所以"饿"不是惩罚，只是"该去吃饭了"的提示
var hunger: float = 0.0

## 去食盆被挡住后的冷却（秒），> 0 时不考虑吃
var _food_cooldown: float = 0.0

## 这次蹲下会不会下蛋（蹲下时掷骰，起身时兑现）
var _egg_pending := false


# ---------------------------------------------------------------- 生命周期
func _ready() -> void:
	# 告诉草地系统：这货会踩开草丛（和员工同一个组）
	add_to_group("grass_pusher")
	# 以后喂食系统 / 数鸡的地方直接 get_tree().get_nodes_in_group("chicken")
	add_to_group("chicken")

	# 俯视角：不受重力。不设的话 move_and_slide 会按 GROUNDED 那套处理碰撞
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING

	_rng.randomize()

	# 先记下"摆的位置"当范围中心，再随机挪 —— 顺序反了范围中心就成了随机点
	_home = global_position

	# 每只速度略有不同
	locomotion.move_speed *= _rng.randf_range(speed_jitter.x, speed_jitter.y)

	locomotion.arrived.connect(_on_arrived)
	locomotion.stuck.connect(_on_stuck)

	_check_animations()

	if random_spawn:
		global_position = _home + Vector2(
			_rng.randf_range(-wander_area.x, wander_area.x),
			_rng.randf_range(-wander_area.y, wander_area.y)
		)

	# 开局错开：一整群鸡不要同一帧一起起步
	_wait_left = _rng.randf_range(0.0, 2.0)

	# 饥饿值也错开：否则一群鸡会同时饿、同时冲向同一个食盆
	hunger = _rng.randf_range(0.0, hunger_seek_at * 0.5)

	# 让初始动画和 _facing_right 立刻一致，避免第一帧闪一下
	_update_anim()


func _physics_process(delta: float) -> void:
	# ── 饥饿：每帧都涨，跟状态无关 ──
	_tick_hunger(delta)

	# ── 执行：每帧都做 ──
	# 先存一份「腿想要的速度」。move_and_slide() 会把 velocity 改成沿墙滑行之后的结果，
	# 撞墙判断必须拿"想要的那份"比才有意义
	var intended := locomotion.tick(delta)
	var start_pos := global_position
	velocity = intended
	move_and_slide()
	_update_anim()

	# ── 撞上障碍：放弃这个目标，停一下再重挑 ──
	if locomotion.has_target() and _is_blocked(intended, start_pos, delta):
		_abort_move()
		return

	# ── 决策：由状态机推进 ──
	_update_state(delta)


# ---------------------------------------------------------------- 状态机
func _update_state(delta: float) -> void:
	_food_cooldown = maxf(0.0, _food_cooldown - delta)

	match _state:
		State.IDLE:
			_wait_left -= delta
			if _wait_left <= 0.0:
				_decide_next()

		State.CROUCH:
			_wait_left -= delta
			if _wait_left <= 0.0:
				_finish_crouch()

		State.EATING:
			hunger = maxf(0.0, hunger - eat_recovery * delta)
			_eat_left -= delta
			# 两个结束条件：吃够了时间，或者已经吃饱了
			if _eat_left <= 0.0 or hunger <= 0.0:
				_finish_eating()

		# WANDER / TO_FOOD 期间位移归 NpcLocomotion 管，
		# 状态翻转只能由 arrived / stuck 信号触发，这里什么都不用做
		State.WANDER, State.TO_FOOD:
			pass


## 一站定了，决定下一件事干什么。优先级：吃饭 > 蹲下 > 溜达
func _decide_next() -> void:
	# ① 饿了先去吃饭（前提是场上真有食盆，且不是刚被挡回来）
	if _is_hungry() and _food_cooldown <= 0.0 and _go_to_food():
		return

	# ② 有概率蹲一会儿 —— 蹲下是漫游的一部分，不是特殊事件
	if _rng.randf() < crouch_chance:
		_start_crouch()
		return

	# ③ 其余时候挑个点溜达
	_state = State.WANDER
	locomotion.move_to(_pick_point())


func _on_arrived() -> void:
	match _state:
		State.TO_FOOD:
			_start_eating()
		_:
			# 走到地方了，站一会儿（下一次 _decide_next 再决定是蹲还是接着走）
			_state = State.IDLE
			_wait_left = _roll_wait(wait_range)


## NpcLocomotion 判为卡住（顶着墙 / 目标点在墙里）
func _on_stuck() -> void:
	_abort_move()


## 放弃当前这次移动，回到站着等。撞墙和卡住都走这里
func _abort_move() -> void:
	locomotion.stop()
	# 去吃饭的路上被挡住：凉几秒再考虑，别一直怼着同一个食盆
	if _state == State.TO_FOOD:
		_food_cooldown = FOOD_COOLDOWN_AFTER_BLOCK
	_state = State.IDLE
	_wait_left = block_wait


# ---------------------------------------------------------------- 饥饿与进食
func _tick_hunger(delta: float) -> void:
	# 吃的时候只往下掉，就别再往上叠了
	if _state == State.EATING:
		return
	hunger = minf(MAX_HUNGER, hunger + hunger_rate * delta)


func _is_hungry() -> bool:
	return hunger >= hunger_seek_at


## 找最近的、能用的食物点。找不到 / 都太远就返回 null（此时饿了也只是继续溜达）
func _find_food_spot() -> Node2D:
	var best: Node2D = null
	var best_distance := food_search_radius

	for node in get_tree().get_nodes_in_group(food_group):
		var spot := node as Node2D
		if spot == null or not is_instance_valid(spot):
			continue

		# 食盆可以自己说"现在没吃的"（比如被吃空了）。有这个方法的就听它的，
		# 没有方法的（单纯一个位置点）一律当成有吃的
		if spot.has_method("has_food") and not bool(spot.call("has_food")):
			continue

		var distance := global_position.distance_to(spot.global_position)
		if distance <= best_distance:
			best_distance = distance
			best = spot

	return best


## 开始往食物点走。走不了（场上没吃的）返回 false，让 _decide_next 接着往下判断
func _go_to_food() -> bool:
	var spot := _find_food_spot()
	if spot == null:
		return false

	# 落点稍微散开：几只鸡同时来吃，各自站在食盆边不同的位置
	var spread := Vector2(
		_rng.randf_range(-food_queue_spread, food_queue_spread),
		_rng.randf_range(-food_queue_spread * 0.5, food_queue_spread * 0.5)
	)
	_state = State.TO_FOOD
	locomotion.move_to(spot.global_position + spread)
	return true


func _start_eating() -> void:
	_state = State.EATING
	_eat_left = eat_duration
	if debug_log:
		print("[小鸡] %s 开始吃（饥饿 %.0f）" % [name, hunger])


func _finish_eating() -> void:
	_state = State.IDLE
	_wait_left = _roll_wait(wait_range)


# ---------------------------------------------------------------- 蹲下与产蛋
func _start_crouch() -> void:
	_state = State.CROUCH
	_wait_left = _roll_wait(crouch_range)
	# 蹲下去的时候就把这泡蛋的命运定下来：起身那一刻才兑现，
	# 这样"蹲着蹲着突然站起来 → 脚边多个蛋"的节奏是对的
	_egg_pending = _rng.randf() < egg_chance


func _finish_crouch() -> void:
	var laid := _egg_pending
	if laid:
		_lay_egg()
	_egg_pending = false

	_state = State.IDLE
	# 蹲完起来站一会儿。想「下完蛋多站一会儿」的话，把下面这行换成
	# _wait_left = _roll_wait(wait_range) * (2.5 if laid else 1.0) 之类的就行
	_wait_left = _roll_wait(wait_range)


## 下蛋。**素材还没做，所以这里只发信号**。
## 蛋的场景做好以后，二选一：
##   A. 别处接 egg_laid 信号，自己 instantiate（推荐，本脚本不用动）
##   B. 直接在下面 TODO 的地方生成
func _lay_egg() -> void:
	# 蛋落在屁股后面：朝右走时屁股在左，反之在右
	# （偏移量按现在屏幕上的鸡身大小给的：128px 美术 × 精灵 scale 0.8，身宽约 42px）
	var behind := -1.0 if _facing_right else 1.0
	var egg_position := global_position + Vector2(behind * 13.0, -5.0)

	if debug_log:
		print("[小鸡] %s 下了一个蛋：%s" % [name, egg_position])

	# TODO(蛋的素材就绪后)：拆掉这个注释即可，别的地方都不用改
	#   var egg := EGG_SCENE.instantiate()
	#   egg.global_position = egg_position
	#   get_parent().add_child(egg)

	egg_laid.emit(egg_position)


# ---------------------------------------------------------------- 决策工具
## 挑下一个目标点。两种策略混用：
##   A. 小步：从当前位置朝随机方向走一小段（多数时候）
##   B. 远行：直接去活动范围内的任意一点（偶尔）
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
## 直接 clamp 会让小鸡一直在边线上走，像被一堵看不见的墙推着
func _fold(value: float, limit: float) -> float:
	if absf(value) <= limit:
		return value
	var folded := signf(value) * (2.0 * limit - absf(value))
	return clampf(folded, -limit, limit)


## 在 [基准-幅度, 基准+幅度] 里取一个**偏小**的值。
## randf() * randf() 的乘积落在 [0,1) 且偏向 0 —— 这就是"多数是短停，偶尔发很久的呆"的来源
func _roll_wait(wait_spec: Vector2) -> float:
	var t := _rng.randf() * _rng.randf()
	return maxf(0.0, wait_spec.x + lerpf(-wait_spec.y, wait_spec.y, t))


## 这一帧是不是被障碍挡住了。
## 不用 get_slide_collision_count() > 0 的原因：贴墙侧向滑行时每帧都有碰撞，
## 但那种情况小鸡其实在正常前进，一碰撞就停会在墙边一顿一顿地抽搐。
## 所以判据是「实际走了多少」对「想走多少」的比例
func _is_blocked(intended: Vector2, start_pos: Vector2, delta: float) -> bool:
	var speed := intended.length()
	if speed < MOVE_ANIM_SPEED:
		return false                                      # 这一帧本来就没打算走
	var wanted := speed * delta                           # 本来该走这么远
	var actual := global_position.distance_to(start_pos)  # 实际走了这么远
	return actual < wanted * BLOCKED_PROGRESS_RATIO


# ---------------------------------------------------------------- 表现
func _update_anim() -> void:
	var speed := velocity.length()
	var moving := speed > MOVE_ANIM_SPEED

	# ① 朝向：x 分量为负走左边，为正走右边；纯上下移动时 x 正好是 0，沿用上一次朝向
	var speed_x := velocity.x
	if absf(speed_x) > FACING_EPSILON:
		_facing_right = speed_x > 0.0

	# ② 状态 × 朝向，选出动画名
	var action := ANIM_IDLE
	match _state:
		State.WANDER, State.TO_FOOD:
			action = ANIM_MOVE if moving else ANIM_IDLE
		State.EATING:
			action = ANIM_EAT
		State.CROUCH:
			action = ANIM_CROUCH
		_:
			action = ANIM_IDLE

	var want := _anim_name(action, _facing_right)

	# ③ 素材缺动画时兜底回待机，而不是原地隐形或者刷报错。
	#    以后要是换成别的美术表、少了一两个动作，游戏不会因此坏掉
	if not _has_anim(want):
		want = _anim_name(ANIM_IDLE, _facing_right)

	# ④ 切换动画时显式从首帧开始。
	if animated_sprite_2d.animation != want:
		animated_sprite_2d.animation = want
		animated_sprite_2d.frame = 0

	# ⑤ 光设 animation 不会让帧往前走（playing 为 false 时只贴第 0 帧），
	#    仅在停止播放时启动，避免重复调用。
	if not animated_sprite_2d.is_playing():
		animated_sprite_2d.play()

	# ⑥ 走路动画速度跟着实际速度走，减少脚底打滑。
	#    每帧按当前动作更新 speed_scale，停止走路时恢复为 1.0。
	if moving and (action == ANIM_MOVE):
		animated_sprite_2d.speed_scale = clampf(
			speed / maxf(locomotion.move_speed, 1.0), 0.5, 2.0)
	else:
		# 必须显式归 1.0，否则会从走路状态残留下来
		animated_sprite_2d.speed_scale = 1.0


func _anim_name(action: String, right: bool) -> StringName:
	return StringName("%s_%s" % [action, "right" if right else "left"])


func _has_anim(anim: StringName) -> bool:
	var frames := animated_sprite_2d.sprite_frames
	return frames != null and frames.has_animation(anim)


## 动画名必须与 SpriteFrames 一致；_check_animations 提前检查缺失配置。
## 这个检查把"它在滑步/隐形"从猜变成日志里一行字（配了兜底，只是警告不是错误）
func _check_animations() -> void:
	var frames := animated_sprite_2d.sprite_frames
	if frames == null:
		push_error("[小鸡] AnimatedSprite2D 上没有 SpriteFrames")
		return
	for action in [ANIM_IDLE, ANIM_MOVE, ANIM_EAT, ANIM_CROUCH]:
		for right in [false, true]:
			var anim := _anim_name(action, right)
			if not frames.has_animation(anim):
				push_warning("[小鸡] 场景里没有动画 '%s'，实际有：%s"
					% [anim, frames.get_animation_names()])
