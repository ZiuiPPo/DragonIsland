class_name WalkSheet
extends RefCounted
## 把「一行 N 格」的角色横条图切成 SpriteFrames 的小工具。
##
## 为什么要单独抽出来：奶龙（scripts/nailong.gd）和 NPC（scripts/npc.gd）用的是同一套素材约定
##   —— 一张横条、每格 256x256、脚底线在帧内 y=235、只画了朝左的姿势，朝右靠 flip_h 翻出来。
## 这段切图代码抄第二遍就会有两份，换素材尺寸时必然漏改一份，所以放到这里共用。
##
## 生成出来的动画名固定是 walk_left / idle_left（朝右不另生成动画，靠 flip_h）。
##
## 用法：
##     $AnimatedSprite2D.sprite_frames = WalkSheet.build(tex, 13, 256, 1, 12, 0, 12.0)

## 切一份 SpriteFrames 出来。
##   sheet      —— 横条图。**调用方用 preload 传进来**，别在运行时拼字符串 load()，
##                 否则编辑器的资源扫描看不见这个依赖，导出时可能漏图（见 nailong.gd 里的说明）
##   columns    —— 横条里有几格
##   frame_size —— 每格边长（像素），格子按正方形切
##   walk_first / walk_last —— 行走循环的首尾格号（0 起，闭区间）
##   idle_frame —— 待机用第几格
##   walk_fps   —— 行走动画速度（帧/秒）。这个值和移动速度是配套的，改一个就要改另一个
##   facing     —— 动画名的后缀，默认 "left"
static func build(
		sheet: Texture2D,
		columns: int,
		frame_size: int,
		walk_first: int,
		walk_last: int,
		idle_frame: int,
		walk_fps: float,
		facing: String = "left") -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")

	if sheet == null:
		push_error("[WalkSheet] 图为空，切不出动画")
		return frames

	# 图的实际格数和调用方说的对不上，之后每一帧都会错位，先在日志里喊一声
	var real_columns := sheet.get_width() / frame_size
	if real_columns != columns:
		push_error("[WalkSheet] %s 实际有 %d 格，调用方写的是 %d 格 —— 切帧会错位"
			% [sheet.resource_path, real_columns, columns])

	var walk := StringName("walk_" + facing)
	frames.add_animation(walk)
	frames.set_animation_loop(walk, true)
	frames.set_animation_speed(walk, walk_fps)
	for i in range(walk_first, walk_last + 1):
		frames.add_frame(walk, _make_atlas(sheet, i, columns, frame_size))

	var idle := StringName("idle_" + facing)
	frames.add_animation(idle)
	frames.set_animation_loop(idle, true)
	frames.set_animation_speed(idle, 1.0)
	frames.add_frame(idle, _make_atlas(sheet, idle_frame, columns, frame_size))

	return frames


## 取横条上第 index 格（0 起）切成一张 AtlasTexture
static func _make_atlas(sheet: Texture2D, index: int, columns: int, frame_size: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(
		float((index % columns) * frame_size),
		float((index / columns) * frame_size),
		float(frame_size),
		float(frame_size)
	)
	# 不留这个的话，采样到格子外缘会取到相邻格子的像素，边缘会一闪一闪地脏
	atlas.filter_clip = true
	return atlas
