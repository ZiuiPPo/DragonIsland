extends CharacterBody2D
## 奶龙 · 双向行走角色（目前只有朝左素材）
##
## 素材：assets/sprites/nailong_walk_left.png
##   3328 x 256，是**一条横条**，切成 13 格、每格 256x256（1 行 x 13 列）。
##   角色朝**左**，是一个完整的步态循环。透明区是 alpha=1 的品红，角色是 alpha=255。
##
## 帧的角色分工（这是实测帧间差异后定的，换素材时要重新确认）：
##   #0        -> idle_left 待机（一帧，站定姿势）
##   #1 ~ #12  -> walk_left 行走循环，12 帧
##   把 #0 放进循环的话，接缝 #12->#0 的差异是 52.9，是平均相邻帧 28.6 的 1.85 倍，
##   循环到那一拍脚会顿一下；拿掉之后接缝降到 36.3，明显更顺。
##
## 锚点：节点原点在**脚底**（这样 y_sort_enabled 的场景里排序才对）。
##   实测 13 帧里有 9 帧的最低点落在帧内 y=235，所以脚底线取 GROUND_Y = 235，
##   精灵在场景里的 position.y = FRAME_SIZE/2 - GROUND_Y = -107（见 scenes/nailong.tscn）。
##   有几帧（#1 等）脚够不到这条线，那是**弹跳腾空帧，双脚离地本来就是动作的一部分**，
##   不是切片切错了；#3~#5 低于线 3px 是落地压缩。**不要加逐帧纵向补偿**，会把弹跳抹掉。
##   横向同理不补偿：左右重心摆动 116~132 是步态刻意的部分。
##
## 只有左右两个方向！右向素材还没画。所以：
##   朝右 -> 暂时复用朝左的图 + flip_h 翻转（见 FACINGS）
##   W/S 上下移动**不改变朝向**，沿用最后一次的左右朝向继续播动画
## 右向素材到位后只改三行（WALK_SHEETS 加一条 preload、FACINGS["right"] 改成 ["right", false]）。
##
## 这张图是**平滑渲染**的，不是像素画，所以：
##   不设 texture_filter = 1（保持默认线性过滤）、不开 snap_2d_transforms_to_pixel。
##   （nailongland 那个工程是像素风，那三条约定不能照抄过来。）
##
## 注意：sprite_frames 是 _ready() 里用代码切的，**在编辑器里打开场景只会看到一个空精灵**，
## 按 F5 跑起来才有动画。这不是坏了。
##
## 输入：WASD / 方向键（定义在 project.godot 的 [input]），按住 Shift 加速跑。

# ---------------------------------------------------------------- 素材常量
## 每格边长（像素）
const FRAME_SIZE := 256
## 横条里有几格。13 = 1 帧待机 + 12 帧行走
const SHEET_COLUMNS := 13
## 帧内脚底线（像素）。实测值，见文件头
const GROUND_Y := 235
## 待机用的那一格
const IDLE_FRAME := 0
## 行走循环的首尾帧（闭区间）
const WALK_FIRST := 1
const WALK_LAST := 12

## 动画名前缀，动作名形如 "walk_left" / "idle_left"
const WALK_PREFIX := "walk_"
const IDLE_PREFIX := "idle_"

## 速度归零阈值（walk_speed 的比例）：低于它就判定为"贴着障碍"，速度真正清零。
## **必须大于 MOVE_ANIM_RATIO**，理由见 _update_movement() 里的说明。
const STOP_VELOCITY_RATIO := 0.08
## 判定"在移动"的阈值（walk_speed 的比例）。**必须小于 STOP_VELOCITY_RATIO**。
const MOVE_ANIM_RATIO := 0.05

## 朝向 -> 行走用的精灵图。
## 用 preload 而不是运行时拼字符串 load()：拼路径的话 .gd 和图片之间没有静态依赖，
## 编辑器的资源扫描看不见它们，导出时若用了"仅导出选中资源"的预设，图不会进包，
## 运行起来角色直接消失（只有一条 push_warning）。
const WALK_SHEETS := {
	"left": preload("res://assets/sprites/nailong_walk_left.png"),
	# "right": preload("res://assets/sprites/nailong_walk_right.png"),  # ← 右向素材到位后解开
}

## 朝向 -> [用哪张行走图, 是否水平翻转]。
## 右向素材还没有，所以朝右先复用朝左的图翻过来。
## 素材到位后：把 "right" 改成 ["right", false]，并在上面 WALK_SHEETS 加一条。
const FACINGS := {
	"left": ["left", false],
	"right": ["left", true],
}

# ---------------------------------------------------------------- 可调参数
@export_group("移动")
## 行走速度（像素/秒）
@export var walk_speed: float = 168.0
## 按住 Shift 时的奔跑速度（像素/秒）。
## 沿用参考工程的走跑比 73/42 ≈ 1.74 -> 168 x 1.74 ≈ 292
@export var run_speed: float = 292.0
## 起步加速度（像素/秒²），越大手感越"跟手"。
## 取值沿用参考工程的手感：那边是 333/42，从静止到全速约 0.126 秒；这里按同样的
## 时间常数换算 -> 168 / 0.126 ≈ 1330。改 walk_speed 时这两个要一起按比例改，
## 否则起步的"跟手程度"会跟着变。
@export var acceleration: float = 1330.0
## 松手减速度（像素/秒²）。参考工程 489/42 ≈ 0.086 秒刹停 -> 168 / 0.086 ≈ 1960
@export var deceleration: float = 1960.0
## 判定朝向的阈值：斜向走时 |x| 要超过它才改左右朝向
@export var direction_threshold: float = 0.35

@export_group("动画")
## 行走动画速度（帧/秒）。12 帧一个完整步态循环。
##
## 这个值和 walk_speed 是**配套的**，配套关系来自实测步长：
##   一个循环 12 帧 = 两步，实测每步约 84px
##   => walk_speed ≈ 84 x 2 x walk_fps / 12 = 14 x walk_fps
## 12fps + 168px/s 就是按这个配的，脚落地时相对地面基本不动（不打滑）。
## **要改就两个一起按比例改**（保持 14 倍关系），只改一个脚就会滑。
## 验证办法：跑 test_nailong.tscn，盯着地上的网格看落地那几帧。
@export var walk_fps: float = 12.0
## 动画随实际速度缩放的上限（跑起来时防止帧率飙到看不清动作）
@export var max_anim_speed_scale: float = 2.2
## 待机时的上下起伏幅度（像素），设 0 可关闭。
##
## 默认 0：待机只有一帧静止画，整只上下平移看起来像贴图在飘，而不是"呼吸"。
## 想要待机有生气，正道是给待机图加两帧动画，而不是靠脚本平移。
@export var idle_breathe: float = 0.0
## 待机呼吸的周期（秒）
@export var idle_breathe_period: float = 2.4

@export_group("影子")
## 脚下的椭圆投影，默认开。
##
## 为什么要它：农场背景整体是**黄调**的（土路、田垄、草地都是黄橙），奶龙也是黄的，
## 走在土路上会直接糊在一起、看不出人在哪（对比过截图，确实很明显）。
## 投影是最省事的解法，也是俯视角游戏的通行做法。
## 不想要就把这个勾去掉 —— 别的什么都不用改。
@export var shadow_enabled: bool = true
## 影子椭圆的半径（x 横半径、y 纵半径）
@export var shadow_radius: Vector2 = Vector2(46.0, 15.0)
## 影子相对脚底的偏移（往上抬一点，让它落在身体正下方）
@export var shadow_offset: Vector2 = Vector2(0.0, -6.0)
## 影子颜色，alpha 是**叠完之后的**浓度。调大就更压得住地面、调小就更接近没有。
@export var shadow_color: Color = Color(0.18, 0.11, 0.02, 0.40)

@export_group("相机")
## 相机跟随的平滑速度（越大越跟手）。设 0 表示不平滑，直接贴住玩家。
@export var camera_smoothing_speed: float = 8.0

# ---------------------------------------------------------------- 运行时状态
## 当前朝向：只有 left / right
var facing: String = "left"
## 精灵相对玩家的"原位"偏移，取自场景。玩家的原点在**脚底**
var _sprite_home := Vector2.ZERO
## 呼吸的当前值与相位
var _breathe_time: float = 0.0
var _breathe: float = 0.0
## 相机相对玩家的固定偏移，取自场景
var _cam_offset := Vector2.ZERO
## 平滑后的相机世界坐标
var _cam_pos := Vector2.ZERO
## 移动动作的死区（取四个动作里最大的那个）。常量，_ready() 里算一次
var _deadzone: float = 0.0

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _camera: Camera2D = $Camera2D


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING  # 俯视角：不受重力影响
	_sprite.sprite_frames = _build_sprite_frames()
	_sprite_home = _sprite.position
	_cam_offset = _camera.position
	_cam_pos = global_position + _cam_offset
	_cache_deadzone()
	_play_animation(IDLE_PREFIX + facing)


func _physics_process(delta: float) -> void:
	_update_movement(delta)
	_update_animation(delta)


## 相机跟随放在**渲染帧**里：_physics_process 可能跑在 60Hz 之外的频率上，
## 而相机是画给眼睛看的，跟着渲染帧走才顺。
func _process(delta: float) -> void:
	_update_camera(delta)


## 画脚下的影子。
## 父节点的 _draw() 在子节点之前渲染，所以影子天然在精灵背后，不用管 z_index。
## 影子是静态的，不用 queue_redraw()。
func _draw() -> void:
	if not shadow_enabled:
		return
	# 由外到内叠几层同心椭圆：外圈只有一层、中心叠满，边缘就有了柔和的过渡，
	# 比单画一个实心椭圆自然得多。
	var rings := 5
	for i in rings:
		var t := float(i) / float(rings - 1)          # 0 = 最外圈，1 = 最内圈
		var radius := shadow_radius.lerp(shadow_radius * 0.45, t)
		var color := shadow_color
		color.a = shadow_color.a / float(rings)
		draw_colored_polygon(_ellipse_points(radius, 28), color)


## 生成一个以影子偏移为中心、横纵半径给定的椭圆多边形
func _ellipse_points(radius: Vector2, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in segments:
		var angle := TAU * float(i) / float(segments)
		points.append(shadow_offset + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	return points


## 相机跟随 + 指数平滑。
##
## 不用 Camera2D 自带的 position_smoothing_enabled：它用的是 speed * delta 的 lerp，
## 帧率相关的 —— 185Hz 下每帧只走 5.4%，比 60Hz 的 16.7% 慢得多，高刷屏上相机会明显拖后。
## 这里换成 1 - exp(-speed * delta)，与帧率无关。
func _update_camera(delta: float) -> void:
	var target := global_position + _cam_offset
	if camera_smoothing_speed > 0.0:
		_cam_pos = _cam_pos.lerp(target, 1.0 - exp(-camera_smoothing_speed * delta))
	else:
		_cam_pos = target
	_camera.global_position = _cam_pos


## 读输入 -> 算速度 -> 移动；同时记录朝向
func _update_movement(delta: float) -> void:
	var input_dir := _apply_deadzone(
		Input.get_vector("move_left", "move_right", "move_up", "move_down", 0.0))

	# 只有左右两个方向的素材：**上下移动不改朝向**，沿用最后一次的左右朝向。
	# 等以后补了背身/正面素材，这里再加 elif 分支判 |y|。
	# 用阈值而不是 != 0：斜向走时 x 分量很小，不加阈值会让朝向在左右之间来回抽搐。
	if absf(input_dir.x) > direction_threshold:
		facing = "right" if input_dir.x > 0.0 else "left"

	var speed: float = run_speed if Input.is_action_pressed("sprint") else walk_speed
	var target_velocity := input_dir * speed
	var rate := acceleration if input_dir != Vector2.ZERO else deceleration
	velocity = velocity.move_toward(target_velocity, rate * delta)
	move_and_slide()

	# 顶着障碍时，move_and_slide 会让"速度"在每个物理帧结束时都留下一点残余
	# （滑到接触面就停下），下一帧又从头加速，表现为贴墙抖动 / 速度读数乱跳。
	# 这里判定为"贴着障碍"并让速度真正归零。注意不依赖输入：松手那一刻的残余
	# 速度同样要清掉，否则"静止"状态是观测不到的。
	#
	# 约束：归零阈值 STOP_VELOCITY_RATIO 必须**大于**判定"在移动"的 MOVE_ANIM_RATIO。
	# 顺序反了的话，残余速度会落在两个阈值之间没被清掉，判"在移动"就一帧真一帧假，
	# walk_/idle_ 逐帧来回切 —— 而切动画会把帧号重置到 0，看起来就是在抽搐。
	# 顺序对了就没事：_update_animation() 在下一行之后才调用，它看到的速度要么是
	# 归零后的 0，要么已经高过 MOVE_ANIM_RATIO，不存在摇摆的中间态。
	if velocity.length() < walk_speed * STOP_VELOCITY_RATIO:
		velocity = Vector2.ZERO


## 在 _ready() 里把死区算一次 —— 它是常量，没必要每个物理帧重建 StringName 查表
func _cache_deadzone() -> void:
	_deadzone = 0.0
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		_deadzone = maxf(_deadzone, InputMap.action_get_deadzone(StringName(action)))


## 把每个轴按死区归零。
## 注意 Input.get_vector(..., 0.0) 传 0.0 是"关闭引擎死区、由本函数接管"的意思，
## 别改成 -1.0，那会变成引擎和脚本各扣一次死区。
func _apply_deadzone(raw_dir: Vector2) -> Vector2:
	var dir := raw_dir
	if absf(dir.x) <= _deadzone:
		dir.x = 0.0
	if absf(dir.y) <= _deadzone:
		dir.y = 0.0
	return dir


## 按"是否在移动"切换 walk_/idle_ 动画，并做呼吸起伏
func _update_animation(delta: float) -> void:
	var speed := velocity.length()
	var moving := speed > walk_speed * MOVE_ANIM_RATIO
	_play_animation((WALK_PREFIX if moving else IDLE_PREFIX) + facing)
	_sprite.flip_h = bool(FACINGS[facing][1])

	if moving:
		# 动画速度跟着实际速度走，消除"脚底打滑"。
		# 12 帧一个步态周期，走满一个周期的位移约等于两步，所以按 speed/walk_speed 等比缩放。
		_sprite.speed_scale = clampf(speed / walk_speed, 0.25, max_anim_speed_scale)
		_breathe = lerpf(_breathe, 0.0, 0.25)
	else:
		# 待机呼吸：待机图是静止的一帧，完全不动看起来像贴图卡住了，
		# 给一点点极慢的上下起伏就能读出"活着"。（默认关，见 idle_breathe 的说明）
		_breathe_time = fmod(_breathe_time + delta * TAU / maxf(idle_breathe_period, 0.01), TAU)
		_breathe = lerpf(_breathe, sin(_breathe_time) * idle_breathe, 0.15)

	_sprite.position = _sprite_home - Vector2(0.0, _breathe)


func _play_animation(anim_name: String) -> void:
	if not _sprite.sprite_frames.has_animation(anim_name):
		return
	if _sprite.animation != anim_name:
		_sprite.animation = anim_name
		_sprite.frame = 0
	if not _sprite.is_playing():
		_sprite.play()


# ---------------------------------------------------------------- 用精灵图生成 SpriteFrames
## 把横条切成 256x256 的 AtlasTexture，组装成 walk_*/idle_* 动画。
## 13 格是匀的（1 行 x 13 列），帧号就是格号：待机取 #0，行走取 #1~#12。
## 因为图本身已经画在同一个 256x256 画布上（脚底线一致），这里不需要任何逐帧偏移表。
func _build_sprite_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")

	for dir in FACINGS:
		var sheet_key: String = FACINGS[dir][0]
		if not WALK_SHEETS.has(sheet_key):
			push_error("[奶龙] 朝向 %s 指向的行走图 '%s' 不在 WALK_SHEETS 里，该方向已跳过" % [dir, sheet_key])
			continue

		var tex: Texture2D = WALK_SHEETS[sheet_key]
		var columns := tex.get_width() / FRAME_SIZE
		var rows := tex.get_height() / FRAME_SIZE
		if columns != SHEET_COLUMNS or rows != 1:
			push_error("[奶龙] %s 的网格是 %dx%d，与脚本假设的 %dx1 不符 —— 切帧会错位"
				% [tex.resource_path, columns, rows, SHEET_COLUMNS])

		var walk := StringName(WALK_PREFIX + dir)
		frames.add_animation(walk)
		frames.set_animation_loop(walk, true)
		frames.set_animation_speed(walk, walk_fps)
		for i in range(WALK_FIRST, WALK_LAST + 1):
			frames.add_frame(walk, _make_atlas(tex, i))

		var idle := StringName(IDLE_PREFIX + dir)
		frames.add_animation(idle)
		frames.set_animation_loop(idle, true)
		frames.set_animation_speed(idle, 1.0)
		frames.add_frame(idle, _make_atlas(tex, IDLE_FRAME))

	return frames


## 取横条上第 index 格（0 起）
func _make_atlas(tex: Texture2D, index: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(
		float((index % SHEET_COLUMNS) * FRAME_SIZE),
		float((index / SHEET_COLUMNS) * FRAME_SIZE),
		float(FRAME_SIZE),
		float(FRAME_SIZE)
	)
	# 不留这个的话，采样到格子外缘时会取到相邻格子的像素，边缘会出现一闪一闪的脏边
	atlas.filter_clip = true
	return atlas
