extends Control
## 建筑界面里的细圆角进度条（自绘，避免默认 ProgressBar 的方角灰条）。
##
## 用法：
##   var bar := preload("res://scripts/ui/growth_bar.gd").new()
##   bar.setup(Color("6fbf4a"))          # 填充色（可选）
##   bar.custom_minimum_size = Vector2(64, 6)
##   bar.set_progress(0.42)
##
## 画法：圆角胶囊底槽 + 圆角胶囊填充 + 顶部一条很淡的高光。
## 进度为 0 时只画底槽；进度很小时用圆形帽兜底，不会画成尖角。

var progress: float = 0.0
var fill_color: Color = Color("6fbf4a")
var track_color: Color = Color(0.12, 0.09, 0.06, 0.78)
var highlight_color: Color = Color(1.0, 1.0, 1.0, 0.25)


func setup(color: Color, track: Color = Color(0.12, 0.09, 0.06, 0.78)) -> void:
	fill_color = color
	track_color = track
	queue_redraw()


func set_progress(value: float) -> void:
	var clamped := clampf(value, 0.0, 1.0)
	if is_equal_approx(clamped, progress):
		return
	progress = clamped
	queue_redraw()


func set_fill_color(color: Color) -> void:
	if color == fill_color:
		return
	fill_color = color
	queue_redraw()


func _draw() -> void:
	var bar_size := size
	if bar_size.x <= 1.0 or bar_size.y <= 1.0:
		return
	_draw_pill(Rect2(Vector2.ZERO, bar_size), track_color)
	if progress <= 0.0:
		return
	var fill_width := maxf(bar_size.y, bar_size.x * progress)
	_draw_pill(Rect2(Vector2.ZERO, Vector2(fill_width, bar_size.y)), fill_color)
	# 顶部高光：让细条看起来有点体积，而不是一块纯色
	var pad := bar_size.y * 0.30
	if fill_width > pad * 2.0:
		draw_line(
			Vector2(pad, bar_size.y * 0.32),
			Vector2(fill_width - pad, bar_size.y * 0.32),
			highlight_color, 1.0)


func _draw_pill(rect: Rect2, color: Color) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var radius := minf(rect.size.y * 0.5, rect.size.x * 0.5)
	draw_circle(rect.position + Vector2(radius, rect.size.y * 0.5), radius, color)
	draw_circle(rect.position + Vector2(rect.size.x - radius, rect.size.y * 0.5), radius, color)
	draw_rect(Rect2(
		rect.position + Vector2(radius, 0.0),
		Vector2(maxf(rect.size.x - radius * 2.0, 1.0), rect.size.y)), color)
