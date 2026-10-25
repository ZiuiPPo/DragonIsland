class_name StaffLooks
extends RefCounted
## 员工外观表：一个 look 名字对应一套「左/右 序列帧」，现场拼成 SpriteFrames。
##
## 为什么不做「一个颜色一个场景」：
##   所有员工的动画完全一样（64×64，1 帧 idle + 7 帧 move），区别只有颜色。
##   把颜色做成 look，场景只保留一份 staff_npc.tscn；招聘进来的每个人只是 look 不同。
##
## look 的命名约定（招聘立绘 → 序列帧）：
##   assets/icons/recruit/npc3.png
##   assets/sprites/npcs/staff/npc3_idle_move_left.png
##   assets/sprites/npcs/staff/npc3_idle_move_right.png
## 也就是说 look 就是立绘文件名，抽到谁就加载谁的帧。
##
## 注意：原始素材的 npc2~npc6 是按「渲染时的角色编号」排的，和立绘 npc1~npc5
## 差一位（黄/红/粉/绿/蓝）；导入时已经按立绘编号改名，后续加新角色也按立绘编号来。
##
## 同一套帧会被缓存：招 5 个同色员工，内存里也只有一份 SpriteFrames。

## 序列帧目录
const SHEET_DIR: String = "res://assets/sprites/npcs/staff"
## 单帧边长（所有帧都是 64×64）
const FRAME_SIZE: int = 64
## idle 用第 0 帧（站立），move 用第 1~7 帧（7 帧走路循环）
const IDLE_FRAME: int = 0
const MOVE_FIRST: int = 1
const MOVE_LAST: int = 7
## 走路动画帧率。和 npc.gd 里的 speed_scale 一起决定脚底滑不滑
const MOVE_FPS: float = 7.0

## look -> SpriteFrames，避免同色员工重复建帧
static var _cache: Dictionary = {}


## 这个 look 的两张序列帧都在吗（招聘池用它过滤掉没做动画的角色）
static func has_look(look: String) -> bool:
	return ResourceLoader.exists(_left_path(look)) and ResourceLoader.exists(_right_path(look))


## 拿某个 look 的 SpriteFrames；拼好后缓存。资源缺失时返回 null。
static func frames_for(look: String) -> SpriteFrames:
	if _cache.has(look):
		return _cache[look]

	var left := load(_left_path(look)) as Texture2D
	var right := load(_right_path(look)) as Texture2D
	if left == null or right == null:
		push_error("[员工外观] 找不到「%s」的序列帧：%s / %s" % [look, _left_path(look), _right_path(look)])
		return null

	var frames := SpriteFrames.new()
	# SpriteFrames 自带一个空的 "default"，删掉免得编辑器里多一个没用的动画
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")
	_add_anim(frames, &"idle_left", left, IDLE_FRAME, IDLE_FRAME, 1.0)
	_add_anim(frames, &"idle_right", right, IDLE_FRAME, IDLE_FRAME, 1.0)
	_add_anim(frames, &"move_left", left, MOVE_FIRST, MOVE_LAST, MOVE_FPS)
	_add_anim(frames, &"move_right", right, MOVE_FIRST, MOVE_LAST, MOVE_FPS)

	_cache[look] = frames
	return frames


static func _left_path(look: String) -> String:
	return "%s/%s_idle_move_left.png" % [SHEET_DIR, look]


static func _right_path(look: String) -> String:
	return "%s/%s_idle_move_right.png" % [SHEET_DIR, look]


## 从一张横排图里切出 [first, last] 帧，作为一个动画。
## 每帧用 AtlasTexture 引用原图，不复制像素。
static func _add_anim(frames: SpriteFrames, anim: StringName, sheet: Texture2D, first: int, last: int, fps: float) -> void:
	frames.add_animation(anim)
	frames.set_animation_speed(anim, fps)
	frames.set_animation_loop(anim, true)
	for i in range(first, last + 1):
		var region := AtlasTexture.new()
		region.atlas = sheet
		region.region = Rect2(i * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
		frames.add_frame(anim, region)
